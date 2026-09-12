// ZephyrU — iOS embedding bridge for the Cemu core.
// Owns process-wide initialization, title loading and lifecycle, and exposes
// telemetry to the UIKit frontend.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ZephyrUGameLoadedNotification;
extern NSNotificationName const ZephyrUGameExitedNotification;

@interface CemuIOS : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, readonly) BOOL coreInitialized;
@property (nonatomic, readonly) BOOL jitAvailable;
@property (nonatomic, readonly, copy) NSString* jitStatusDescription;
@property (nonatomic, readonly) BOOL titleRunning;

/// Initializes config paths, MLC storage, audio, input and the Cafe system.
/// Must be called once before loadGameAtPath:.
- (BOOL)initializeCoreWithError:(NSError**)error;

/// Scans and prepares a title. Supports standalone .rpx and Wii U images
/// (.wua/.wud/.wux) that Cemu's title list can parse.
- (BOOL)loadGameAtPath:(NSString*)path error:(NSError**)error;

/// Launches the prepared title. Non-blocking (emulation runs on its own threads).
- (void)startEmulation;

/// Requests the running title to shut down.
- (void)stopEmulation;

/// Attaches the emulator's CAMetalLayer host view to the core.
- (void)setWindowSurface:(UIView*)view;

/// Updates the drawable size in physical pixels.
- (void)updateDrawableSize:(CGSize)pixelSize scale:(CGFloat)scale;

/// Current frame counters and title info. Safe to call from the main thread.
- (NSDictionary<NSString*, id>*)telemetry;

/// Writes one telemetry line to Cemu's log.txt (used by unattended test runs).
- (void)logTelemetry;

@end

NS_ASSUME_NONNULL_END
