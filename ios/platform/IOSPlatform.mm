// ZephyrU iOS platform layer
// JIT capability probing and error presentation.
//
// Executable memory on iOS is only available when the kernel's JIT policy allows
// it (development-signed app attached to a debugger -> CS_DEBUGGED, Apple-granted
// dynamic-codesigning, or an OS version that permits mprotect for development
// builds). We do not trust mmap/mprotect return values: we map a page, write an
// AArch64 "ret" stub, mark it executable and actually execute it while catching
// a fault. This is the only reliable test, because mprotect(PROT_EXEC) can report
// success on iOS while executing the page still faults.
// See docs/IOS_PORT_RESEARCH.md section 3.3/3.4 for sources.

#include "IOSPlatformCallbacks.h"

#include <atomic>
#include <mutex>
#include <setjmp.h>
#include <signal.h>
#include <string>

#include <sys/mman.h>
#include <unistd.h>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <mach/vm_map.h>

namespace
{
	std::atomic_int s_jitState{-1}; // -1 = unknown, 0 = unavailable, 1 = available
	std::string s_jitDescription;

	std::mutex s_jitMutex;

	bool RegionHasExecutePermission(void* mapping)
	{
		vm_address_t address = (vm_address_t)(uintptr_t)mapping;
		vm_size_t regionSize = 0;
		vm_region_basic_info_data_64_t info{};
		mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
		mach_port_t objectName = MACH_PORT_NULL;
		const kern_return_t kr = vm_region_64(mach_task_self(), &address, &regionSize, VM_REGION_BASIC_INFO_64,
		                                      (vm_region_info_t)&info, &infoCount, &objectName);
		return kr == KERN_SUCCESS && (info.protection & VM_PROT_EXECUTE) != 0;
	}

	// On iOS mprotect(PROT_EXEC) can report success while executing the pages still
	// faults (TXM/JIT policy). The only reliable check is to run a one-instruction
	// stub and catch the fault, so the recompiler is never selected on a false positive.
	sigjmp_buf s_executeTestJump;
	volatile sig_atomic_t s_executeTestActive = 0;

	void ExecuteTestSignalHandler(int signal)
	{
		if (s_executeTestActive)
			siglongjmp(s_executeTestJump, 1);
	}

	bool ExecuteTest(void* mapping, size_t size)
	{
		if (size < 4)
			return false;
		// AArch64 "ret"
		((uint32_t*)mapping)[0] = 0xD65F03C0;

		struct sigaction handler{}, oldSegv{}, oldBus{};
		handler.sa_handler = ExecuteTestSignalHandler;
		sigemptyset(&handler.sa_mask);
		handler.sa_flags = SA_NODEFER;
		sigaction(SIGSEGV, &handler, &oldSegv);
		sigaction(SIGBUS, &handler, &oldBus);

		bool executed = false;
		s_executeTestActive = 1;
		if (sigsetjmp(s_executeTestJump, 1) == 0)
		{
			((void (*)())mapping)();
			executed = true;
		}
		s_executeTestActive = 0;

		sigaction(SIGSEGV, &oldSegv, nullptr);
		sigaction(SIGBUS, &oldBus, nullptr);
		return executed;
	}

	bool TryExecutableMapping(bool viaMprotect)
	{
		const size_t pageSize = (size_t)getpagesize();
		const size_t mapSize = pageSize * 4;
		const int mapProtection = viaMprotect ? (PROT_READ | PROT_WRITE) : (PROT_READ | PROT_WRITE | PROT_EXEC);
		void* mapping = mmap(nullptr, mapSize, mapProtection, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (mapping == MAP_FAILED)
			return false;

		if (viaMprotect && mprotect(mapping, mapSize, PROT_READ | PROT_EXEC) != 0)
		{
			munmap(mapping, mapSize);
			return false;
		}

		const bool executable = RegionHasExecutePermission(mapping) && ExecuteTest(mapping, mapSize);
		munmap(mapping, mapSize);
		return executable;
	}

	bool ProbeExecutableMemory()
	{
		// Path xbyak uses: mmap read/write + mprotect to read/execute.
		if (TryExecutableMapping(true))
		{
			s_jitDescription = "Executable memory verified (mmap+mprotect; JIT enabled)";
			return true;
		}

		// Apple dynamic-codesigning path: direct PROT_EXEC mapping.
		if (TryExecutableMapping(false))
		{
			s_jitDescription = "Executable memory verified (PROT_EXEC mapping; JIT enabled)";
			return true;
		}

		s_jitDescription = "Executable memory is not permitted for this process. Attach a debugger "
		                   "(StikDebug-class) to a development-signed build to enable the AArch64 recompiler.";
		return false;
	}
}

extern "C" int IOSPlatform_IsJITAvailable(void)
{
	int state = s_jitState.load(std::memory_order_acquire);
	if (state >= 0)
		return state;

	std::lock_guard<std::mutex> lock(s_jitMutex);
	state = s_jitState.load(std::memory_order_relaxed);
	if (state < 0)
	{
		state = ProbeExecutableMemory() ? 1 : 0;
		s_jitState.store(state, std::memory_order_release);
	}
	return state;
}

extern "C" const char* IOSPlatform_GetJITStatusDescription(void)
{
	IOSPlatform_IsJITAvailable();
	return s_jitDescription.c_str();
}

extern "C" void IOSPlatform_PresentError(const char* title, const char* message, int category)
{
	NSString* t = title && title[0] ? [NSString stringWithUTF8String:title] : @"ZephyrU";
	NSString* m = message ? [NSString stringWithUTF8String:message] : @"";
	NSLog(@"[ZephyrU][error][%d] %@: %@", category, t, m);

	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController* root = nil;
		for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
		{
			if (![scene isKindOfClass:[UIWindowScene class]])
				continue;
			for (UIWindow* window in ((UIWindowScene*)scene).windows)
			{
				if (window.isKeyWindow && window.rootViewController)
				{
					root = window.rootViewController;
					break;
				}
			}
			if (root)
				break;
		}
		if (!root)
			return;

		while (root.presentedViewController)
			root = root.presentedViewController;

		UIAlertController* alert = [UIAlertController alertControllerWithTitle:t message:m preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
		[root presentViewController:alert animated:YES completion:nil];
	});
}

extern "C" void IOSPlatform_NotifyGameLoaded(void)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:@"ZephyrUGameLoaded" object:nil];
	});
}

extern "C" void IOSPlatform_NotifyGameExited(void)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:@"ZephyrUGameExited" object:nil];
	});
}
