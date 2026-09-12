#import "GameListViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "CemuIOSBridge.h"
#import "EmulatorViewController.h"

@interface GameListViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray<NSURL*>* gameURLs;
@property (nonatomic, strong) UILabel* footerLabel;
@end

@implementation GameListViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	self.title = @"ZephyrU";
	self.tableView.tableFooterView = [[UIView alloc] init];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Import"
	                                                                          style:UIBarButtonItemStylePlain
	                                                                         target:self
	                                                                         action:@selector(importGame:)];
	self.gameURLs = [NSMutableArray array];
	[self refreshGames];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self refreshGames];
}

- (NSURL*)gamesDirectory
{
	NSURL* documents = [NSFileManager.defaultManager URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
	return [documents URLByAppendingPathComponent:@"games" isDirectory:YES];
}

- (void)refreshGames
{
	[self.gameURLs removeAllObjects];
	NSURL* directory = [self gamesDirectory];
	NSArray<NSString*>* extensions = @[ @"wua", @"wud", @"wux", @"rpx" ];
	NSArray<NSURL*>* contents = [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory
	                                                       includingPropertiesForKeys:nil
	                                                                          options:NSDirectoryEnumerationSkipsHiddenFiles
	                                                                            error:nil];
	for (NSURL* url in contents)
	{
		if ([extensions containsObject:url.pathExtension.lowercaseString])
			[self.gameURLs addObject:url];
	}
	[self.gameURLs sortUsingComparator:^NSComparisonResult(NSURL* a, NSURL* b) {
		return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
	}];
	[self.tableView reloadData];
}

- (void)importGame:(id)sender
{
	NSMutableArray<UTType*>* types = [NSMutableArray array];
	for (NSString* identifier in @[ @"com.zephyru.wua", @"public.data" ])
	{
		UTType* type = [UTType typeWithIdentifier:identifier];
		if (type)
			[types addObject:type];
	}
	UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
	picker.delegate = self;
	picker.allowsMultipleSelection = NO;
	[self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
	NSURL* source = urls.firstObject;
	if (!source)
		return;

	NSURL* destination = [[self gamesDirectory] URLByAppendingPathComponent:source.lastPathComponent];
	NSFileManager* fileManager = NSFileManager.defaultManager;
	[fileManager removeItemAtURL:destination error:nil];
	NSError* error = nil;
	if (![fileManager copyItemAtURL:source toURL:destination error:&error])
	{
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Import failed"
		                                                              message:error.localizedDescription
		                                                       preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
		[self presentViewController:alert animated:YES completion:nil];
		return;
	}
	[self refreshGames];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
	return 2;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
	if (section == 0)
		return 1; // environment / JIT status
	return (NSInteger)self.gameURLs.count;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
	return section == 0 ? @"Environment" : @"Games";
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	if (indexPath.section == 0)
	{
		CemuIOS* cemu = [CemuIOS sharedInstance];
		cell.textLabel.text = cemu.jitAvailable ? @"AArch64 recompiler: available" : @"AArch64 recompiler: unavailable";
		cell.detailTextLabel.text = cemu.jitAvailable
		    ? @"Executable memory is permitted. Full speed emulation possible."
		    : @"Running the PowerPC interpreter. Enable JIT (development build + debugger) for full speed.";
		cell.detailTextLabel.numberOfLines = 0;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	else
	{
		NSURL* url = self.gameURLs[(NSUInteger)indexPath.row];
		cell.textLabel.text = url.lastPathComponent;
		cell.detailTextLabel.text = @"Tap to play";
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0)
		return;

	NSURL* url = self.gameURLs[(NSUInteger)indexPath.row];
	EmulatorViewController* emulator = [[EmulatorViewController alloc] initWithGameURL:url];
	[self.navigationController pushViewController:emulator animated:YES];
}

@end
