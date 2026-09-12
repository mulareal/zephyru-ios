// ZephyrU iOS platform layer
// JIT capability probing and error presentation.
//
// Executable memory on iOS is only available to processes that the kernel
// considers JIT-enabled (development-signed app with get-task-allow attached to
// a debugger -> CS_DEBUGGED, or Apple-granted dynamic-codesigning for browser
// engines). Without it, mmap(PROT_READ|PROT_WRITE|PROT_EXEC) succeeds but the
// kernel silently strips execute permission on iOS.
//
// We therefore do not trust the mmap return value. We map a page, then query the
// actual protection bits through mach_vm_region and look for VM_PROT_EXECUTE.
// See docs/IOS_PORT_RESEARCH.md section 3.3/3.4 for sources.

#include "IOSPlatformCallbacks.h"

#include <atomic>
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

	bool ProbeExecutableMemory()
	{
		const size_t pageSize = (size_t)getpagesize();
		const size_t mapSize = pageSize * 4;

		// Realistic path first: xbyak (and therefore Cemu's recompiler) maps read/write
		// and then flips the pages to executable via mprotect. With a debugger attached
		// (CS_DEBUGGED) that succeeds even though a direct PROT_EXEC mapping is stripped.
		{
			void* mapping = mmap(nullptr, mapSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
			if (mapping != MAP_FAILED)
			{
				const bool protectOk = mprotect(mapping, mapSize, PROT_READ | PROT_EXEC) == 0;
				const bool executable = protectOk && RegionHasExecutePermission(mapping);
				munmap(mapping, mapSize);
				if (executable)
				{
					s_jitDescription = "Executable memory available via mprotect (JIT enabled, debugger attached)";
					return true;
				}
			}
		}

		// Fallback: direct PROT_EXEC mapping (Apple dynamic-codesigning / allow-jit).
		void* mapping = mmap(nullptr, mapSize, PROT_READ | PROT_WRITE | PROT_EXEC,
		                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (mapping == MAP_FAILED)
		{
			s_jitDescription = "mmap/mprotect could not create executable memory. Attach a debugger "
			                   "(StikDebug-class) to a development-signed build to enable the AArch64 recompiler.";
			return false;
		}

		const bool executable = RegionHasExecutePermission(mapping);
		munmap(mapping, mapSize);

		if (executable)
		{
			s_jitDescription = "Executable memory available (JIT enabled)";
			return true;
		}

		s_jitDescription = "Executable memory was created but the kernel stripped execute permission "
		                   "(iOS JIT restriction). Enable JIT with a development-signed build attached to a debugger "
		                   "(StikDebug/Jitterbug-style) to use the AArch64 recompiler.";
		return false;
	}
}

extern "C" int IOSPlatform_IsJITAvailable(void)
{
	int state = s_jitState.load(std::memory_order_acquire);
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
