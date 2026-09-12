// ZephyrU iOS platform layer
// GameController.framework provider implementation.

#include "GameControllerProvider.h"
#include "GameControllerController.h"

#include <algorithm>

#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include "Cemu/Logging/CemuLogging.h"

// C++-owned snapshot of one controller. Objective-C objects are only touched on
// the main queue (handlers/refresh); raw_state() reads under m_mutex.
struct GCControllerSnapshot
{
	std::string uuid;
	std::string displayName;
	bool connected = false;

	mutable std::mutex mutex;
	ControllerState state;

	void* controller = nullptr; // __bridge GCController*
};

namespace
{
	std::string MakeUuid(GCController* controller)
	{
		NSString* name = controller.vendorName ?: @"Controller";
		NSString* category = controller.productCategory ?: @"";
		return std::string(name.UTF8String) + "|" + std::string(category.UTF8String);
	}

	std::string MakeDisplayName(GCController* controller)
	{
		return std::string((controller.vendorName ?: @"Game Controller").UTF8String);
	}

	void ApplyButtons(GCExtendedGamepad* pad, ControllerState& state)
	{
		// Physical button ids follow Cemu's SDL generic mapping convention:
		// A=kButton1, B=kButton0, X=kButton3, Y=kButton2, L=kButton9, R=kButton10,
		// Menu=kButton6, Options=kButton4, Home=kButton5,
		// dpad up/down/left/right = kButton11..14, stick clicks kButton7/8.
		state.buttons.SetButtonState(kButton1, pad.buttonA.isPressed);
		state.buttons.SetButtonState(kButton0, pad.buttonB.isPressed);
		state.buttons.SetButtonState(kButton3, pad.buttonX.isPressed);
		state.buttons.SetButtonState(kButton2, pad.buttonY.isPressed);

		state.buttons.SetButtonState(kButton9, pad.leftShoulder.isPressed);
		state.buttons.SetButtonState(kButton10, pad.rightShoulder.isPressed);

		state.buttons.SetButtonState(kButton6, pad.buttonMenu.isPressed);
		if (@available(iOS 13.0, *))
			state.buttons.SetButtonState(kButton4, pad.buttonOptions.isPressed);
		if (@available(iOS 14.0, *))
			state.buttons.SetButtonState(kButton5, pad.buttonHome.isPressed);

		state.buttons.SetButtonState(kButton11, pad.dpad.up.isPressed);
		state.buttons.SetButtonState(kButton12, pad.dpad.down.isPressed);
		state.buttons.SetButtonState(kButton13, pad.dpad.left.isPressed);
		state.buttons.SetButtonState(kButton14, pad.dpad.right.isPressed);

		state.buttons.SetButtonState(kButton7, pad.leftThumbstickButton.isPressed);
		state.buttons.SetButtonState(kButton8, pad.rightThumbstickButton.isPressed);
	}

	void ApplyAxes(GCExtendedGamepad* pad, ControllerState& state)
	{
		state.axis = glm::vec2((float)pad.leftThumbstick.xAxis.value, (float)pad.leftThumbstick.yAxis.value);
		state.rotation = glm::vec2((float)pad.rightThumbstick.xAxis.value, (float)pad.rightThumbstick.yAxis.value);
		state.trigger = glm::vec2((float)pad.leftTrigger.value, (float)pad.rightTrigger.value);
	}

	void RefreshOnMainThread()
	{
		auto* controllerList = [GCController controllers];
		for (GCController* controller in controllerList)
		{
			@autoreleasepool
			{
				const std::string uuid = MakeUuid(controller);
				std::shared_ptr<GCControllerSnapshot> snapshot;

				{
					std::lock_guard lock(GameControllerProvider::s_mutex);
					auto it = GameControllerProvider::s_snapshots.find(uuid);
					if (it == GameControllerProvider::s_snapshots.end())
					{
						snapshot = std::make_shared<GCControllerSnapshot>();
						snapshot->uuid = uuid;
						snapshot->displayName = MakeDisplayName(controller);
						GameControllerProvider::s_snapshots.emplace(uuid, snapshot);
					}
					else
					{
						snapshot = it->second;
					}
				}

				snapshot->connected = true;
				snapshot->controller = (__bridge void*)controller;

				GCExtendedGamepad* pad = controller.extendedGamepad;
				if (!pad)
					continue;

				// Install once per controller
				if (!pad.valueChangedHandler)
				{
					GCController* controllerRef = controller;
					pad.valueChangedHandler = ^(GCExtendedGamepad* gamepad, GCControllerElement* element) {
						const std::string key = MakeUuid(controllerRef);
						std::shared_ptr<GCControllerSnapshot> snap;
						{
							std::lock_guard lock(GameControllerProvider::s_mutex);
							auto it = GameControllerProvider::s_snapshots.find(key);
							if (it == GameControllerProvider::s_snapshots.end())
								return;
							snap = it->second;
						}
						std::lock_guard lock(snap->mutex);
						ApplyButtons(gamepad, snap->state);
						ApplyAxes(gamepad, snap->state);
					};
				}

				std::lock_guard lock(snapshot->mutex);
				ApplyButtons(pad, snapshot->state);
				ApplyAxes(pad, snapshot->state);
			}
		}

		// mark disconnected controllers
		std::lock_guard lock(GameControllerProvider::s_mutex);
		for (auto& [uuid, snapshot] : GameControllerProvider::s_snapshots)
		{
			bool found = false;
			for (GCController* controller in controllerList)
			{
				if (MakeUuid(controller) == uuid)
				{
					found = true;
					break;
				}
			}
			if (!found)
				snapshot->connected = false;
		}
	}
}

GameControllerProvider::GameControllerProvider()
{
	EnsureObservers();
	if (s_observerCount.fetch_add(1) == 0)
	{
		// initial enumeration must happen on the main thread
		dispatch_async(dispatch_get_main_queue(), ^{
			RefreshOnMainThread();
			[GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
		});
	}
}

GameControllerProvider::~GameControllerProvider()
{
	if (s_observerCount.fetch_sub(1) == 1)
	{
		if (s_connectObserver)
		{
			[[NSNotificationCenter defaultCenter] removeObserver:(__bridge id)s_connectObserver];
			s_connectObserver = nullptr;
		}
		if (s_disconnectObserver)
		{
			[[NSNotificationCenter defaultCenter] removeObserver:(__bridge id)s_disconnectObserver];
			s_disconnectObserver = nullptr;
		}
	}
}

void GameControllerProvider::EnsureObservers()
{
	static std::once_flag once;
	std::call_once(once, []
	{
		s_connectObserver = (__bridge_retained void*)[[NSNotificationCenter defaultCenter]
			addObserverForName:GCControllerDidConnectNotification
			            object:nil
			             queue:[NSOperationQueue mainQueue]
			        usingBlock:^(NSNotification* note) {
				        (void)note;
				        RefreshOnMainThread();
			        }];
		s_disconnectObserver = (__bridge_retained void*)[[NSNotificationCenter defaultCenter]
			addObserverForName:GCControllerDidDisconnectNotification
			            object:nil
			             queue:[NSOperationQueue mainQueue]
			        usingBlock:^(NSNotification* note) {
				        (void)note;
				        RefreshOnMainThread();
			        }];
	});
}

void GameControllerProvider::RefreshControllers()
{
	if ([NSThread isMainThread])
		RefreshOnMainThread();
	else
		dispatch_async(dispatch_get_main_queue(), ^{
			RefreshOnMainThread();
		});
}

std::vector<std::shared_ptr<ControllerBase>> GameControllerProvider::get_controllers()
{
	std::vector<std::shared_ptr<ControllerBase>> result;
	std::lock_guard lock(s_mutex);
	for (auto& [uuid, snapshot] : s_snapshots)
	{
		if (!snapshot->connected)
			continue;
		result.emplace_back(std::make_shared<GameControllerController>(uuid, snapshot->displayName));
	}
	return result;
}

ControllerState GameControllerProvider::get_state(const std::string& uuid) const
{
	std::shared_ptr<GCControllerSnapshot> snapshot;
	{
		std::lock_guard lock(s_mutex);
		auto it = s_snapshots.find(uuid);
		if (it == s_snapshots.end())
			return {};
		snapshot = it->second;
	}
	std::lock_guard lock(snapshot->mutex);
	return snapshot->state;
}

bool GameControllerProvider::is_connected(const std::string& uuid) const
{
	std::lock_guard lock(s_mutex);
	auto it = s_snapshots.find(uuid);
	if (it == s_snapshots.end())
		return false;
	return it->second->connected;
}

void GameControllerProvider::set_rumble(const std::string& uuid, bool state)
{
	// Rumble via GCDeviceHaptics requires a haptic engine; deferred to a later
	// milestone. Keep the API so controllers can opt in once implemented.
}

bool GameControllerController::is_connected()
{
	auto provider = std::dynamic_pointer_cast<GameControllerProvider>(m_provider);
	if (!provider)
		return false;
	return provider->is_connected(m_uuidString);
}

ControllerState GameControllerController::raw_state()
{
	auto provider = std::dynamic_pointer_cast<GameControllerProvider>(m_provider);
	if (!provider)
		return {};
	ControllerState state = provider->get_state(m_uuidString);
	if (!provider->is_connected(m_uuidString))
		return {};
	return state;
}

void GameControllerController::start_rumble()
{
	auto provider = std::dynamic_pointer_cast<GameControllerProvider>(m_provider);
	if (provider)
		provider->set_rumble(m_uuidString, true);
}

void GameControllerController::stop_rumble()
{
	auto provider = std::dynamic_pointer_cast<GameControllerProvider>(m_provider);
	if (provider)
		provider->set_rumble(m_uuidString, false);
}
