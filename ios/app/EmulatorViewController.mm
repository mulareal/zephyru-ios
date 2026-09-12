#import "EmulatorViewController.h"

#import <QuartzCore/CAMetalLayer.h>

#import "CemuIOSBridge.h"

@interface EmulatorViewController ()
@property (nonatomic, strong) NSURL* gameURL;
@property (nonatomic, strong) UILabel* telemetryLabel;
@property (nonatomic, strong) UIButton* stopButton;
@property (nonatomic, strong) UIVisualEffectView* overlayView;
@property (nonatomic, strong) NSTimer* telemetryTimer;
@property (nonatomic) BOOL emulationStarted;
@property (nonatomic) BOOL overlayVisible;
@end

@implementation EmulatorViewController

+ (Class)layerClass
{
	return [CAMetalLayer class];
}

- (instancetype)initWithGameURL:(NSURL*)gameURL
{
	self = [super initWithNibName:nil bundle:nil];
	if (self)
	{
		_gameURL = gameURL;
		_overlayVisible = YES;
	}
	return self;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.view.backgroundColor = UIColor.blackColor;
	self.navigationController.navigationBarHidden = YES;

	CAMetalLayer* layer = (CAMetalLayer*)self.view.layer;
	layer.framebufferOnly = YES;
	layer.opaque = YES;

	UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleOverlay)];
	[self.view addGestureRecognizer:tap];

	UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
	self.overlayView = [[UIVisualEffectView alloc] initWithEffect:blur];
	self.overlayView.translatesAutoresizingMaskIntoConstraints = NO;
	self.overlayView.alpha = 1.0;
	[self.view addSubview:self.overlayView];

	self.telemetryLabel = [[UILabel alloc] init];
	self.telemetryLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.telemetryLabel.textColor = UIColor.whiteColor;
	self.telemetryLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	self.telemetryLabel.numberOfLines = 0;
	[self.overlayView.contentView addSubview:self.telemetryLabel];

	self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
	[self.stopButton setTitle:@"Stop" forState:UIControlStateNormal];
	[self.stopButton addTarget:self action:@selector(stopEmulation) forControlEvents:UIControlEventTouchUpInside];
	[self.overlayView.contentView addSubview:self.stopButton];

	UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
	[NSLayoutConstraint activateConstraints:@[
		[self.overlayView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
		[self.overlayView.topAnchor constraintEqualToAnchor:safe.topAnchor],
		[self.overlayView.widthAnchor constraintEqualToConstant:340],

		[self.telemetryLabel.leadingAnchor constraintEqualToAnchor:self.overlayView.contentView.leadingAnchor constant:12],
		[self.telemetryLabel.topAnchor constraintEqualToAnchor:self.overlayView.contentView.topAnchor constant:8],
		[self.telemetryLabel.trailingAnchor constraintEqualToAnchor:self.overlayView.contentView.trailingAnchor constant:-12],

		[self.stopButton.topAnchor constraintEqualToAnchor:self.telemetryLabel.bottomAnchor constant:4],
		[self.stopButton.leadingAnchor constraintEqualToAnchor:self.overlayView.contentView.leadingAnchor constant:12],
		[self.stopButton.bottomAnchor constraintEqualToAnchor:self.overlayView.contentView.bottomAnchor constant:-8],
	]];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	CemuIOS* cemu = [CemuIOS sharedInstance];
	[cemu setWindowSurface:self.view];
	[self updateDrawableSize];

	if (!self.emulationStarted)
	{
		self.emulationStarted = YES;
		__weak EmulatorViewController* weakSelf = self;
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSError* error = nil;
			if (![cemu loadGameAtPath:weakSelf.gameURL.path error:&error])
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Cannot start game"
					                                                              message:error.localizedDescription
					                                                       preferredStyle:UIAlertControllerStyleAlert];
					[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
						[weakSelf.navigationController popViewControllerAnimated:YES];
					}]];
					[weakSelf presentViewController:alert animated:YES completion:nil];
				});
				return;
			}
			[cemu startEmulation];
		});
	}

	self.telemetryTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer* timer) {
		[weakSelf updateTelemetry];
	}];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.telemetryTimer invalidate];
	self.telemetryTimer = nil;
	self.navigationController.navigationBarHidden = NO;
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	[self updateDrawableSize];
}

- (void)updateDrawableSize
{
	CGFloat scale = self.view.window.screen.scale;
	if (scale <= 0)
		scale = UIScreen.mainScreen.scale;
	const CGSize pixelSize = CGSizeMake(self.view.bounds.size.width * scale, self.view.bounds.size.height * scale);
	[[CemuIOS sharedInstance] updateDrawableSize:pixelSize scale:scale];
}

- (void)toggleOverlay
{
	self.overlayVisible = !self.overlayVisible;
	[UIView animateWithDuration:0.15 animations:^{
		self.overlayView.alpha = self.overlayVisible ? 1.0 : 0.0;
	}];
}

- (void)updateTelemetry
{
	NSDictionary* telemetry = [[CemuIOS sharedInstance] telemetry];
	static uint32 lastFrameCounter = 0;
	static NSTimeInterval lastSampleTime = 0;

	const uint32 frameCounter = [telemetry[@"frameCounter"] unsignedIntValue];
	const NSTimeInterval now = NSDate.date.timeIntervalSince1970;

	double fps = 0.0;
	if (lastSampleTime > 0 && now > lastSampleTime)
	{
		uint32 frames = frameCounter >= lastFrameCounter ? frameCounter - lastFrameCounter : (UINT32_MAX - lastFrameCounter + frameCounter);
		fps = frames / (now - lastSampleTime);
	}
	lastFrameCounter = frameCounter;
	lastSampleTime = now;

	self.telemetryLabel.text = [NSString stringWithFormat:
		@"Title: %@\n"
		@"Running: %@\n"
		@"Emulation FPS (GPU frames/s): %.1f\n"
		@"GPU frame counter: %u\n"
		@"Draw calls (last cycle): %u\n"
		@"AArch64 recompiler: %@\n"
		@"Tap to hide overlay",
		[telemetry[@"titleName"] length] ? telemetry[@"titleName"] : @"-",
		[telemetry[@"running"] boolValue] ? @"yes" : @"no",
		fps,
		frameCounter,
		[telemetry[@"drawCalls"] unsignedIntValue],
		[telemetry[@"jit"] boolValue] ? @"available" : @"unavailable (interpreter)"];
}

- (void)stopEmulation
{
	[[CemuIOS sharedInstance] stopEmulation];
	[self.navigationController popViewControllerAnimated:YES];
}

@end
