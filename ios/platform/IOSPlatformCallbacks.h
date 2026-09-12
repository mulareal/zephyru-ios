// ZephyrU iOS platform callbacks
// Small C surface that lets core/platform code talk to the UIKit frontend
// without importing Objective-C types.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Present an error to the user. Safe to call from any thread.
// category maps to WindowSystem::ErrorCategory.
void IOSPlatform_PresentError(const char* title, const char* message, int category);

// Emulation lifecycle notifications. Safe to call from any thread.
void IOSPlatform_NotifyGameLoaded(void);
void IOSPlatform_NotifyGameExited(void);

// JIT capability of the current process (computed once via a real mmap probe).
// Returns 1 if the process can create executable memory.
int IOSPlatform_IsJITAvailable(void);

// Human readable reason for the JIT status, for display in diagnostics.
const char* IOSPlatform_GetJITStatusDescription(void);

#ifdef __cplusplus
}
#endif
