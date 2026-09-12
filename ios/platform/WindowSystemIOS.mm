// ZephyrU iOS platform layer
// Implements the WindowSystem interface from src/gui/interface/WindowSystem.h
// This replaces the wxWidgets implementation (src/gui/wxgui/wxWindowSystem.cpp)
// on iOS. The emulator core only depends on this header, never on wx directly.

#include "WindowSystem.h"

#include <atomic>
#include <mutex>
#include <string>

#include <fmt/format.h>

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include "IOSPlatformCallbacks.h"
#include "WindowSystemIOS.h"

namespace WindowSystem
{
	static WindowInfo s_windowInfo{};

	// pixels of the Metal drawable backing the emulator view, set by EmulatorViewController
	static std::atomic_int32_t s_viewPixelWidth{0};
	static std::atomic_int32_t s_viewPixelHeight{0};
	static std::atomic<double> s_viewScale{1.0};
	static std::atomic_bool s_emulationRunning{false};

	void IOSPlatform_SetDrawableSize(int width, int height, double scale)
	{
		s_viewPixelWidth.store(width);
		s_viewPixelHeight.store(height);
		s_viewScale.store(scale);

		s_windowInfo.phys_width.store(width);
		s_windowInfo.phys_height.store(height);
		s_windowInfo.width.store((int)(width / (scale > 0 ? scale : 1.0)));
		s_windowInfo.height.store((int)(height / (scale > 0 ? scale : 1.0)));
		s_windowInfo.dpi_scale.store(scale);
	}

	void IOSPlatform_SetAppActive(bool active)
	{
		s_windowInfo.app_active.store(active);
	}

	void IOSPlatform_SetEmulationRunning(bool running)
	{
		s_emulationRunning.store(running);
	}

	void ShowErrorDialog(std::string_view message, std::string_view title, std::optional<ErrorCategory> errorCategory)
	{
		std::string msg(message);
		std::string ttl(title);
		IOSPlatform_PresentError(ttl, msg, (int)(errorCategory ? *errorCategory : ErrorCategory::KEYS_TXT_CREATION));
	}

	void Create()
	{
		s_windowInfo.app_active.store(false);
		s_windowInfo.pad_open.store(false);
		s_windowInfo.is_fullscreen.store(true);
		s_windowInfo.debugger_focused.store(false);
	}

	WindowInfo& GetWindowInfo()
	{
		return s_windowInfo;
	}

	void UpdateWindowTitles(bool isIdle, bool isLoading, double fps)
	{
		// no window titles on iOS
	}

	void GetWindowSize(int& w, int& h)
	{
		w = s_windowInfo.width.load();
		h = s_windowInfo.height.load();
	}

	void GetPadWindowSize(int& w, int& h)
	{
		w = s_windowInfo.pad_width.load();
		h = s_windowInfo.pad_height.load();
	}

	void GetWindowPhysSize(int& w, int& h)
	{
		w = s_windowInfo.phys_width.load();
		h = s_windowInfo.phys_height.load();
	}

	void GetPadWindowPhysSize(int& w, int& h)
	{
		w = s_windowInfo.phys_pad_width.load();
		h = s_windowInfo.phys_pad_height.load();
	}

	double GetWindowDPIScale()
	{
		return s_windowInfo.dpi_scale.load();
	}

	double GetPadDPIScale()
	{
		return s_windowInfo.pad_dpi_scale.load();
	}

	bool IsPadWindowOpen()
	{
		return s_windowInfo.pad_open.load();
	}

	bool IsKeyDown(uint32 key)
	{
		return s_windowInfo.get_keystate(key);
	}

	bool IsKeyDown(PlatformKeyCodes key)
	{
		return s_windowInfo.get_keystate((uint32)key);
	}

	std::string GetKeyCodeName(uint32 key)
	{
		return fmt::format("key{}", key);
	}

	bool InputConfigWindowHasFocus()
	{
		return false;
	}

	void NotifyGameLoaded()
	{
		IOSPlatform_SetEmulationRunning(true);
		IOSPlatform_NotifyGameLoaded();
	}

	void NotifyGameExited()
	{
		IOSPlatform_SetEmulationRunning(false);
		IOSPlatform_NotifyGameExited();
	}

	void RefreshGameList()
	{
		// iOS frontend refresh is driven by the Swift/UIKit layer
	}

	bool IsFullScreen()
	{
		return true;
	}

	void CaptureInput(const ControllerState& currentState, const ControllerState& lastState)
	{
		// The iOS touch overlay writes into the same inputs through the
		// GameController provider; nothing to merge here yet.
	}
} // namespace WindowSystem
