// ZephyrU iOS platform layer
// Additional WindowSystem entry points used by the iOS frontend and bridge.
// These are ZephyrU-specific and have no desktop equivalent.

#pragma once

namespace WindowSystem
{
	// Sets the drawable size in physical pixels and its scale factor.
	void IOSPlatform_SetDrawableSize(int width, int height, double scale);

	// Tracks application active state (used by the core for a few heuristics).
	void IOSPlatform_SetAppActive(bool active);

	// Mirrors the emulation running state for the frontend.
	void IOSPlatform_SetEmulationRunning(bool running);
}
