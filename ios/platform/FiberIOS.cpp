// ZephyrU iOS platform layer
// Fiber implementation for iOS. Cemu's scheduler is built on cooperative
// fibers (util/Fiber). The POSIX ucontext API, which the desktop Unix
// implementation uses, is stubbed out on iOS: getcontext/makecontext/
// swapcontext return ENOTSUP and never switch context.
//
// UTM and QEMU solved the same problem by vendoring libucontext, a small
// ISC-licensed ucontext implementation with AArch64 assembly. This file uses
// the vendored copy in ios/third_party/libucontext (see docs/IOS_PORT_RESEARCH.md).
//
// Difference from FiberUnix.cpp: libucontext reads makecontext varargs as
// 64-bit machine words ("unsigned long"), so the two 32-bit halves have to be
// passed as two separate 64-bit values. Cemu's arm64 fiber entry
// (coreinit::__OSFiberThreadEntry) reconstructs the pointer from a high/low
// pair, exactly like Apple's makecontext ABI on arm64.

#include "util/Fiber/Fiber.h"

#include <libucontext/libucontext.h>

#include <atomic>
#include <cstdlib>

thread_local Fiber* sCurrentFiber{};

Fiber::Fiber(void(*FiberEntryPoint)(void* userParam), void* userParam, void* privateData) : m_privateData(privateData)
{
	auto* ctx = (libucontext_ucontext_t*)calloc(1, sizeof(libucontext_ucontext_t));
	if (!ctx)
		abort();

	const size_t stackSize = 2 * 1024 * 1024;
	m_stackPtr = malloc(stackSize);
	if (!m_stackPtr)
		abort();

	if (libucontext_getcontext(ctx) != 0)
		abort();
	ctx->uc_stack.ss_sp = m_stackPtr;
	ctx->uc_stack.ss_size = stackSize;
	ctx->uc_link = ctx;

	const uintptr_t param = (uintptr_t)userParam;
	libucontext_makecontext(ctx, (void(*)())FiberEntryPoint, 2, (unsigned long)(param >> 32), (unsigned long)param);
	this->m_implData = (void*)ctx;
}

Fiber::Fiber(void* privateData) : m_privateData(privateData)
{
	auto* ctx = (libucontext_ucontext_t*)calloc(1, sizeof(libucontext_ucontext_t));
	if (!ctx)
		abort();
	if (libucontext_getcontext(ctx) != 0)
		abort();
	this->m_implData = (void*)ctx;
	m_stackPtr = nullptr;
}

Fiber::~Fiber()
{
	if (m_stackPtr)
		free(m_stackPtr);
	free(m_implData);
}

Fiber* Fiber::PrepareCurrentThread(void* privateData)
{
	cemu_assert_debug(sCurrentFiber == nullptr);
	sCurrentFiber = new Fiber(privateData);
	return sCurrentFiber;
}

void Fiber::Switch(Fiber& targetFiber)
{
	Fiber* leavingFiber = sCurrentFiber;
	sCurrentFiber = &targetFiber;
	std::atomic_thread_fence(std::memory_order_seq_cst);
	libucontext_swapcontext((libucontext_ucontext_t*)(leavingFiber->m_implData),
	                        (libucontext_ucontext_t*)(targetFiber.m_implData));
	std::atomic_thread_fence(std::memory_order_seq_cst);
}

void* Fiber::GetFiberPrivateData()
{
	return sCurrentFiber->m_privateData;
}
