// ZephyrU — iOS embedding bridge implementation.

#import "CemuIOSBridge.h"

#include <fstream>
#include <set>
#include <string>
#include <strings.h>
#include <system_error>
#include <vector>

#include "Cafe/CafeSystem.h"
#include "Cafe/GraphicPack/GraphicPack2.h"
#include "Cafe/HW/Espresso/PPCState.h"
#include "Cafe/HW/Latte/Core/LattePerformanceMonitor.h"
#include "Cafe/TitleList/SaveList.h"
#include "Cafe/TitleList/TitleList.h"
#include "Cemu/Logging/CemuLogging.h"
#include "Cemu/ncrypto/ncrypto.h"
#include "Common/ExceptionHandler/ExceptionHandler.h"
#include "config/ActiveSettings.h"
#include "config/CemuConfig.h"
#include "input/InputManager.h"
#include "audio/IAudioAPI.h"
#include "util/crypto/aes128.h"
#include "util/helpers/helpers.h"
#include "WindowSystem.h"
#include "WindowSystemIOS.h"

#include "IOSPlatformCallbacks.h"

NSNotificationName const ZephyrUGameLoadedNotification = @"ZephyrUGameLoaded";
NSNotificationName const ZephyrUGameExitedNotification = @"ZephyrUGameExited";

namespace
{
	bool s_coreInitialized = false;

	class IOSSystemImplementation : public CafeSystem::SystemImplementation
	{
	public:
		void CafeRecreateCanvas() override
		{
			// The frontend reattaches the CAMetalLayer when this notification fires.
			dispatch_async(dispatch_get_main_queue(), ^{
				[[NSNotificationCenter defaultCenter] postNotificationName:@"ZephyrURecreateCanvas" object:nil];
			});
		}

		void CafePPCProcessExit() override
		{
			WindowSystem::NotifyGameExited();
		}
	};

	IOSSystemImplementation s_systemImplementation;

	bool CreateDirectoriesIfNotExist(const fs::path& path)
	{
		std::error_code ec;
		if (fs::exists(path, ec))
			return true;
		return fs::create_directories(path, ec);
	}

	// Port of CemuApp::CreateDefaultMLCFiles (desktop UI free version)
	bool CreateDefaultMLCFiles(const fs::path& mlc)
	{
		const fs::path directories[] = {
			mlc,
			mlc / "sys",
			mlc / "usr",
			mlc / "usr/title/00050000",
			mlc / "usr/title/0005000c",
			mlc / "usr/title/0005000e",
			mlc / "usr/save/00050010/1004a000/user/common/db",
			mlc / "usr/save/00050010/1004a100/user/common/db",
			mlc / "usr/save/00050010/1004a200/user/common/db",
			mlc / "sys/title/0005001b/1005c000/content"
		};
		for (auto& path : directories)
		{
			if (!CreateDirectoriesIfNotExist(path))
				return false;
		}

		try
		{
			const auto langDir = fs::path(mlc).append("sys/title/0005001b/1005c000/content");
			const auto langFile = fs::path(langDir).append("language.txt");
			if (!fs::exists(langFile))
			{
				std::ofstream file(langFile);
				if (file.is_open())
				{
					const char* langStrings[] = { "ja","en","fr","de","it","es","zh","ko","nl","pt","ru","zh" };
					for (const char* lang : langStrings)
						file << "\"" << lang << "\"," << std::endl;
					file.flush();
				}
			}

			const auto countryFile = fs::path(langDir).append("country.txt");
			if (!fs::exists(countryFile))
			{
				std::ofstream file(countryFile);
				for (size_t i = 0; i < NCrypto::GetCountryCount(); i++)
				{
					const char* countryCode = NCrypto::GetCountryAsString((sint32)i);
					if (!countryCode)
						continue;
					if (strcasecmp(countryCode, "NN") == 0)
						file << "NULL," << std::endl;
					else
						file << "\"" << countryCode << "\"," << std::endl;
				}
				file.flush();
			}

			const auto dummyFile = fs::path(mlc).append("writetestdummy");
			std::ofstream file(dummyFile);
			if (!file.is_open())
				return false;
			file.close();
			fs::remove(dummyFile);
		}
		catch (const std::exception& ex)
		{
			cemuLog_log(LogType::Force, "CreateDefaultMLCFiles failed: {}", ex.what());
			return false;
		}
		return true;
	}

	NSError* MakeError(NSString* message)
	{
		return [NSError errorWithDomain:@"ZephyrU.CemuIOS" code:1
		                       userInfo:@{NSLocalizedDescriptionKey : message}];
	}
}

@implementation CemuIOS

+ (instancetype)sharedInstance
{
	static CemuIOS* instance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		instance = [[CemuIOS alloc] init];
	});
	return instance;
}

- (BOOL)coreInitialized
{
	return s_coreInitialized ? YES : NO;
}

- (BOOL)jitAvailable
{
	return IOSPlatform_IsJITAvailable() ? YES : NO;
}

- (NSString*)jitStatusDescription
{
	return [NSString stringWithUTF8String:IOSPlatform_GetJITStatusDescription()];
}

- (BOOL)titleRunning
{
	return CafeSystem::IsTitleRunning() ? YES : NO;
}

- (BOOL)initializeCoreWithError:(NSError**)error
{
	if (s_coreInitialized)
		return YES;

	@try
	{
		NSFileManager* fileManager = NSFileManager.defaultManager;
		NSURL* documents = [fileManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
		NSURL* appSupport = [fileManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
		NSURL* caches = [fileManager URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];

		const fs::path documentsPath(documents.path.UTF8String);
		const fs::path supportPath(appSupport.path.UTF8String);
		const fs::path cachePath(caches.path.UTF8String);
		const fs::path bundlePath(NSBundle.mainBundle.bundlePath.UTF8String);
		const fs::path executablePath(NSBundle.mainBundle.executablePath.UTF8String);

		const fs::path userDataPath = supportPath;
		const fs::path configPath = supportPath;
		const fs::path dataPath = bundlePath / "SharedSupport";
		const fs::path mlcPath = supportPath / "mlc01";
		const fs::path gamesPath = documentsPath / "games";

		// keep the data path fallback usable when the bundle copy is absent
		std::error_code ec;
		fs::path effectiveDataPath = fs::exists(dataPath, ec) ? dataPath : executablePath.parent_path();

		std::set<fs::path> failedWriteAccess;
		ActiveSettings::SetPaths(false, executablePath, userDataPath, configPath, cachePath, effectiveDataPath, failedWriteAccess);

		GetConfigHandle().SetFilename(ActiveSettings::GetConfigPath("settings.xml").generic_wstring());
		GetConfigHandle().Load();

		GetConfig().graphic_api = kMetal;
		GetConfig().audio_api = IAudioAPI::AudioUnit;
		GetConfig().mlc_path = mlcPath.generic_string();
		GetConfigHandle().Save();

		if (!CreateDirectoriesIfNotExist(ActiveSettings::GetConfigPath("controllerProfiles")) ||
		    !CreateDirectoriesIfNotExist(ActiveSettings::GetUserDataPath("memorySearcher")) ||
		    !CreateDirectoriesIfNotExist(gamesPath))
		{
			if (error)
				*error = MakeError(@"Failed to create ZephyrU application directories.");
			return NO;
		}

		if (!CreateDefaultMLCFiles(mlcPath))
		{
			if (error)
				*error = MakeError(@"Failed to initialize MLC storage (mlc01).");
			return NO;
		}

		AES128_init();
		PPCTimer_init();
		ExceptionHandler_Init();

		IAudioAPI::InitializeStatic();
		InputManager::instance().load();

		GraphicPack2::LoadAll();

		CafeSystem::SetImplementation(&s_systemImplementation);
		CafeSystem::Initialize();

		CafeTitleList::Initialize(ActiveSettings::GetUserDataPath("title_list_cache.xml"));
		CafeTitleList::AddScanPath(gamesPath);
		CafeTitleList::SetMLCPath(mlcPath);
		CafeTitleList::Refresh();

		CafeSaveList::Initialize();
		CafeSaveList::SetMLCPath(mlcPath);

		ActiveSettings::Init();

		cemuLog_log(LogType::Force, "ZephyrU: core initialized (JIT: {})", IOSPlatform_IsJITAvailable() ? "yes" : "no");
		cemuLog_log(LogType::Force, "ZephyrU: data path {}", effectiveDataPath.generic_string());
		cemuLog_log(LogType::Force, "ZephyrU: mlc path {}", mlcPath.generic_string());

		s_coreInitialized = true;
		return YES;
	}
	@catch (NSException* exception)
	{
		if (error)
			*error = MakeError([NSString stringWithFormat:@"Core initialization failed: %@", exception.reason]);
		return NO;
	}
}

- (BOOL)loadGameAtPath:(NSString*)path error:(NSError**)error
{
	if (!s_coreInitialized)
	{
		if (error)
			*error = MakeError(@"Core has not been initialized.");
		return NO;
	}
	if (!path || path.length == 0)
	{
		if (error)
			*error = MakeError(@"No game path provided.");
		return NO;
	}

	const fs::path gamePath(path.UTF8String);
	std::error_code ec;
	if (!fs::exists(gamePath, ec))
	{
		if (error)
			*error = MakeError([NSString stringWithFormat:@"Game file not found: %@", path]);
		return NO;
	}

	const std::string extension = _pathToUtf8(gamePath.extension());
	if (extension == ".rpx" || extension == ".RPX")
	{
		const auto status = CafeSystem::PrepareForegroundTitleFromStandaloneRPX(gamePath);
		if (status != CafeSystem::PREPARE_STATUS_CODE::SUCCESS)
		{
			if (error)
				*error = MakeError(@"Failed to prepare standalone RPX (invalid executable or unable to mount).");
			return NO;
		}
		return YES;
	}

	// disk image / installed title: scan its directory and locate the title by path
	const fs::path scanDir = gamePath.parent_path();
	CafeTitleList::AddScanPath(scanDir);
	CafeTitleList::Refresh();

	TitleId matchedTitleId = 0;
	for (TitleId titleId : CafeTitleList::GetAllTitleIds())
	{
		TitleInfo titleInfo;
		if (!CafeTitleList::GetFirstByTitleId(titleId, titleInfo))
			continue;
		if (titleInfo.GetPath() == gamePath)
		{
			matchedTitleId = titleId;
			break;
		}
	}

	if (matchedTitleId == 0)
	{
		if (error)
			*error = MakeError(@"Cemu could not identify this title. Use a decrypted .wua image or a standalone .rpx.");
		return NO;
	}

	const auto status = CafeSystem::PrepareForegroundTitle(matchedTitleId);
	if (status != CafeSystem::PREPARE_STATUS_CODE::SUCCESS)
	{
		if (error)
			*error = MakeError(@"Failed to mount or prepare the selected title.");
		return NO;
	}
	return YES;
}

- (void)startEmulation
{
	if (!s_coreInitialized)
		return;
	WindowSystem::IOSPlatform_SetAppActive(true);
	CafeSystem::LaunchForegroundTitle();
}

- (void)stopEmulation
{
	if (!s_coreInitialized)
		return;
	if (CafeSystem::IsTitleRunning())
		CafeSystem::ShutdownTitle();
	WindowSystem::NotifyGameExited();
}

- (void)setWindowSurface:(UIView*)view
{
	WindowSystem::GetWindowInfo().window_main.surface = (__bridge void*)view;
	WindowSystem::GetWindowInfo().canvas_main.surface = (__bridge void*)view;
}

- (void)updateDrawableSize:(CGSize)pixelSize scale:(CGFloat)scale
{
	WindowSystem::IOSPlatform_SetDrawableSize((int)pixelSize.width, (int)pixelSize.height, (double)scale);
}

- (NSDictionary<NSString*, id>*)telemetry
{
	performanceMonitor_t& monitor = performanceMonitor;
	const uint32 frameCounter = monitor.cycle[monitor.cycleIndex].frameCounter;
	const uint32 drawCalls = monitor.cycle[monitor.cycleIndex].drawCallCounter;

	NSString* titleName = @"";
	if (CafeSystem::IsTitleRunning())
	{
		@try
		{
			titleName = [NSString stringWithUTF8String:CafeSystem::GetForegroundTitleName().c_str()];
		}
		@catch (NSException*)
		{
			titleName = @"";
		}
	}

	return @{
		@"frameCounter" : @(frameCounter),
		@"drawCalls" : @(drawCalls),
		@"titleName" : titleName,
		@"running" : @(CafeSystem::IsTitleRunning()),
		@"jit" : @(IOSPlatform_IsJITAvailable() != 0),
		@"jitStatus" : [NSString stringWithUTF8String:IOSPlatform_GetJITStatusDescription()],
	};
}

@end
