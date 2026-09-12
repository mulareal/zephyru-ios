// ZephyrU iOS platform layer
// GameController.framework provider for Cemu's input abstraction.
// The provider keeps a C++-side snapshot per controller (updated from the
// framework's value-changed handlers on the main queue) so the emulation
// threads never touch Objective-C objects.
//
// This header intentionally does not include Controller.h (which includes
// InputManager.h) to avoid an include cycle; see GameControllerController.h.

#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "input/api/ControllerProvider.h"
#include "input/api/ControllerState.h"

struct GCControllerSnapshot;

class GameControllerProvider : public ControllerProviderBase
{
public:
	inline static InputAPI::Type kAPIType = InputAPI::IOSController;

	GameControllerProvider();
	~GameControllerProvider() override;

	InputAPI::Type api() const override { return kAPIType; }
	std::vector<std::shared_ptr<ControllerBase>> get_controllers() override;

	// used by GameControllerController
	ControllerState get_state(const std::string& uuid) const;
	bool is_connected(const std::string& uuid) const;
	void set_rumble(const std::string& uuid, bool state);

	// called from the platform layer
	static void RefreshControllers();

	// internal state, public so the platform .mm translation unit can update it
	inline static std::mutex s_mutex;
	inline static std::unordered_map<std::string, std::shared_ptr<GCControllerSnapshot>> s_snapshots;
	inline static std::atomic_int s_observerCount{0};
	inline static void* s_connectObserver = nullptr;
	inline static void* s_disconnectObserver = nullptr;

private:
	static void EnsureObservers();
};
