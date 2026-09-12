#import "AppDelegate.h"

#import "CemuIOSBridge.h"
#import "GameListViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

	GameListViewController* gameList = [[GameListViewController alloc] init];
	UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:gameList];
	navigation.navigationBarHidden = NO;

	self.window.rootViewController = navigation;
	[self.window makeKeyAndVisible];

	// Initialize the emulator core after the UI exists so any startup errors can
	// be presented to the user.
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSError* error = nil;
		if (![[CemuIOS sharedInstance] initializeCoreWithError:&error])
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"ZephyrU"
				                                                              message:error.localizedDescription
				                                                       preferredStyle:UIAlertControllerStyleAlert];
				[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
				[self.window.rootViewController presentViewController:alert animated:YES completion:nil];
			});
		}
	});

	return YES;
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
	// Emulation threads must not keep running in the background.
	if ([[CemuIOS sharedInstance] titleRunning])
		[[CemuIOS sharedInstance] stopEmulation];
}

- (void)applicationWillTerminate:(UIApplication*)application
{
	[[CemuIOS sharedInstance] stopEmulation];
}

@end
