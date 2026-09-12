#include "Common/precompiled.h"

// ZephyrU iOS platform layer
// AudioUnit (RemoteIO) backend for Cemu's IAudioAPI.

#include "AudioUnitAPI.h"

#include <algorithm>
#include <cstring>
#include <stdexcept>

#import <AVFAudio/AVFAudio.h>

#include "Cemu/Logging/CemuLogging.h"

AudioUnitAPI::AudioUnitAPI(uint32 samplerate, uint32 channels, uint32 samples_per_block, uint32 bits_per_sample)
	: IAudioAPI(samplerate, channels, samples_per_block, bits_per_sample)
{
	if (channels != 2)
		cemuLog_log(LogType::Force, "AudioUnitAPI: expected stereo output, got {} channels", channels);

	AudioComponentDescription desc{};
	desc.componentType = kAudioUnitType_Output;
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;

	AudioComponent component = AudioComponentFindNext(nullptr, &desc);
	if (!component)
		throw std::runtime_error("AudioUnitAPI: no RemoteIO audio component available");

	OSStatus status = AudioComponentInstanceNew(component, &m_audioUnit);
	if (status != noErr || !m_audioUnit)
		throw std::runtime_error(fmt::format("AudioUnitAPI: AudioComponentInstanceNew failed ({})", (int)status));

	AudioStreamBasicDescription format{};
	format.mSampleRate = (Float64)samplerate;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	format.mFramesPerPacket = 1;
	format.mChannelsPerFrame = channels;
	format.mBitsPerChannel = bits_per_sample;
	format.mBytesPerFrame = channels * (bits_per_sample / 8);
	format.mBytesPerPacket = format.mBytesPerFrame;

	status = AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
	if (status != noErr)
	{
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
		throw std::runtime_error(fmt::format("AudioUnitAPI: failed to set stream format ({})", (int)status));
	}

	AURenderCallbackStruct callback{};
	callback.inputProc = &AudioUnitAPI::RenderCallback;
	callback.inputProcRefCon = this;
	status = AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback));
	if (status != noErr)
	{
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
		throw std::runtime_error(fmt::format("AudioUnitAPI: failed to set render callback ({})", (int)status));
	}

	m_buffer.reserve((size_t)m_bytesPerBlock * kBlockCount);

	status = AudioUnitInitialize(m_audioUnit);
	if (status != noErr)
	{
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
		throw std::runtime_error(fmt::format("AudioUnitAPI: AudioUnitInitialize failed ({})", (int)status));
	}
}

AudioUnitAPI::~AudioUnitAPI()
{
	if (m_audioUnit)
	{
		Stop();
		AudioUnitUninitialize(m_audioUnit);
		AudioComponentInstanceDispose(m_audioUnit);
		m_audioUnit = nullptr;
	}
}

OSStatus AudioUnitAPI::RenderCallback(void* refCon, AudioUnitRenderActionFlags* actionFlags,
                                      const AudioTimeStamp* timeStamp, UInt32 busNumber,
                                      UInt32 numberFrames, AudioBufferList* data)
{
	auto* self = static_cast<AudioUnitAPI*>(refCon);
	if (!self || !data || data->mNumberBuffers == 0)
		return noErr;

	self->FillOutput(data->mBuffers[0].mData, data->mBuffers[0].mDataByteSize);
	for (UInt32 i = 1; i < data->mNumberBuffers; ++i)
	{
		if (data->mBuffers[i].mData && data->mBuffers[i].mDataByteSize)
			memset(data->mBuffers[i].mData, 0, data->mBuffers[i].mDataByteSize);
	}
	return noErr;
}

void AudioUnitAPI::FillOutput(void* outputBuffer, size_t byteCount)
{
	std::unique_lock lock(m_mutex);
	if (m_buffer.empty())
	{
		memset(outputBuffer, 0, byteCount);
		return;
	}

	const size_t copied = std::min(m_buffer.size(), byteCount);
	memcpy(outputBuffer, m_buffer.data(), copied);
	m_buffer.erase(m_buffer.begin(), std::next(m_buffer.begin(), (ptrdiff_t)copied));
	lock.unlock();

	if (copied != byteCount)
		memset((uint8*)outputBuffer + copied, 0, byteCount - copied);
}

bool AudioUnitAPI::NeedAdditionalBlocks() const
{
	std::shared_lock lock(m_mutex);
	return m_buffer.size() < (size_t)GetAudioDelay() * m_bytesPerBlock;
}

bool AudioUnitAPI::FeedBlock(sint16* data)
{
	std::unique_lock lock(m_mutex);
	if (m_buffer.capacity() <= m_buffer.size() + m_bytesPerBlock)
	{
		cemuLog_logDebug(LogType::Force, "AudioUnitAPI: dropped block, output queue full");
		return false;
	}

	m_buffer.insert(m_buffer.end(), (uint8*)data, (uint8*)data + m_bytesPerBlock);
	return true;
}

bool AudioUnitAPI::Play()
{
	if (m_isPlaying || !m_audioUnit)
		return true;

	const OSStatus status = AudioOutputUnitStart(m_audioUnit);
	if (status == noErr)
	{
		m_isPlaying = true;
		return true;
	}
	cemuLog_log(LogType::Force, "AudioUnitAPI: AudioOutputUnitStart failed ({})", (int)status);
	return false;
}

bool AudioUnitAPI::Stop()
{
	if (!m_isPlaying || !m_audioUnit)
		return true;

	const OSStatus status = AudioOutputUnitStop(m_audioUnit);
	if (status == noErr)
	{
		m_isPlaying = false;
		return true;
	}
	return false;
}

void AudioUnitAPI::SetVolume(sint32 volume)
{
	IAudioAPI::SetVolume(volume);
	if (!m_audioUnit)
		return;
	AudioUnitSetParameter(m_audioUnit, kHALOutputParam_Volume, kAudioUnitScope_Global, 0, (Float32)volume / 100.0f, 0);
}

bool AudioUnitAPI::InitializeStatic()
{
	NSError* error = nil;
	AVAudioSession* session = [AVAudioSession sharedInstance];
	if (![session setCategory:AVAudioSessionCategoryPlayback error:&error])
	{
		cemuLog_log(LogType::Force, "AudioUnitAPI: failed to set AVAudioSession category: {}", error ? error.localizedDescription.UTF8String : "unknown");
		return false;
	}
	// Request the lowest documented buffer duration (>= 5 ms / 256 frames); the
	// session may grant a different value, which is fine.
	[session setPreferredIOBufferDuration:0.005 error:nil];
	return true;
}

void AudioUnitAPI::Destroy()
{
}

std::vector<IAudioAPI::DeviceDescriptionPtr> AudioUnitAPI::GetDevices()
{
	std::vector<DeviceDescriptionPtr> result;
	result.emplace_back(std::make_shared<AudioUnitDeviceDescription>(L"Default Output"));
	return result;
}
