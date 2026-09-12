// ZephyrU iOS platform layer
// ControllerBase implementation backed by GameControllerProvider.

#pragma once

#include <string>
#include <string_view>

#include "GameControllerProvider.h"
#include "input/api/Controller.h"

class GameControllerController : public Controller<GameControllerProvider>
{
public:
	GameControllerController(std::string_view uuid, std::string_view display_name)
		: Controller<GameControllerProvider>(uuid, display_name), m_uuidString(uuid) { }

	InputAPI::Type api() const override { return GameControllerProvider::kAPIType; }
	std::string_view api_name() const override { return InputAPI::to_string(GameControllerProvider::kAPIType); }

	bool is_connected() override;
	ControllerState raw_state() override;

	bool has_rumble() override { return true; }
	void start_rumble() override;
	void stop_rumble() override;

private:
	std::string m_uuidString;
};
