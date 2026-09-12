// ZephyrU iOS platform layer
// IAudioAPI backend built on AudioUnit RemoteIO (the lowest-latency documented
// iOS output path). Mirrors the design of CubebAPI: the emulator pushes S16
// blocks and the render callback drains a lock-protected ring buffer, filling
// silence if the emulator falls behind. Audio never drives emulation timing.

#pragma once

#include "audio/IAudioAPI.h"

#include <AudioToolbox/AudioToolbox.h>

#include <atomic>
#include <memory>
#include <shared_mutex>
#include <vector>

class AudioUnitAPI : public IAudioAPI
{
public:
	class AudioUnitDeviceDescription : public DeviceDescription
	{
	public:
		explicit AudioUnitDeviceDescription(const std::wstring& name)
			: DeviceDescription(name) { }

		std::wstring GetIdentifier() const override { return L"default"; }
	};

	AudioUnitAPI(uint32 samplerate, uint32 channels, uint32 samples_per_block, uint32 bits_per_sample);
	~AudioUnitAPI() override;

	AudioAPI GetType() const override { return AudioUnit; }
	bool NeedAdditionalBlocks() const override;
	bool FeedBlock(sint16* data) override;
	bool Play() override;
	bool Stop() override;
	void SetVolume(sint32 volume) override;

	static std::vector<DeviceDescriptionPtr> GetDevices();

	static bool InitializeStatic();
	static void Destroy();

private:
	static OSStatus RenderCallback(void* refCon, AudioUnitRenderActionFlags* actionFlags,
	                               const AudioTimeStamp* timeStamp, UInt32 busNumber,
	                               UInt32 numberFrames, AudioBufferList* data);

	void FillOutput(void* outputBuffer, size_t byteCount);

	AudioUnit m_audioUnit = nullptr;
	bool m_isPlaying = false;

	mutable std::mutex m_mutex;
	std::vector<uint8> m_buffer;
};
