//
//  curagoController.m
//  curago
//
//  Created by Matt Clarke on 21/02/2015.
//  Copyright (c) 2015 __MyCompanyName__. All rights reserved.
//

#import "curagoController.h"
#import "IBKCarouselCell.h"
#import <Preferences/PSSpecifier.h>
#import "OrderedDictionary.h"
#import "IBKWidgetSettingsController.h"
#import <sys/utsname.h>
#import <libMobileGestalt.h>
#include <sys/stat.h>
#import <objc/runtime.h>

enum {
    ALApplicationIconSizeSmall = 29,
    ALApplicationIconSizeLarge = 59
};
typedef NSUInteger ALApplicationIconSize;

@interface ALApplicationList : NSObject {
@private
    NSMutableDictionary *cachedIcons;
}

+ (ALApplicationList *)sharedApplicationList;

@property (nonatomic, readonly) NSDictionary *applications;
- (NSDictionary *)applicationsFilteredUsingPredicate:(NSPredicate *)predicate;
- (id)valueForKeyPath:(NSString *)keyPath forDisplayIdentifier:(NSString *)displayIdentifier;
- (id)valueForKey:(NSString *)keyPath forDisplayIdentifier:(NSString *)displayIdentifier;
- (CGImageRef)copyIconOfSize:(ALApplicationIconSize)iconSize forDisplayIdentifier:(NSString *)displayIdentifier;
- (UIImage *)iconOfSize:(ALApplicationIconSize)iconSize forDisplayIdentifier:(NSString *)displayIdentifier;
- (BOOL)hasCachedIconOfSize:(ALApplicationIconSize)iconSize forDisplayIdentifier:(NSString *)displayIdentifier;

@end

static curagoController *shared;
static int currentIndex = 0;
NSBundle *strings;

static OrderedDictionary *dataSourceSystem;
static OrderedDictionary *dataSourceUser;

@implementation curagoController

+(instancetype)sharedInstance {
    return shared;
}

-(id)init {
    self = [super init];
    if (self) {
        shared = self;
        self.headerview = [[IBKHeaderView alloc] initWithFrame:CGRectMake(0, 0, self.table.frame.size.width, 345)];
    }
    
    return self;
}

-(id)specifiers {
    if (_specifiers == nil) {
		NSMutableArray *testingSpecs = [self loadSpecifiersFromPlistName:@"Root" target:self];
        testingSpecs = [[self localizedSpecifiersForSpecifiers:testingSpecs] mutableCopy];
        
        [testingSpecs addObjectsFromArray:[self getPrefsForIndex:currentIndex]];
        
        _specifiers = testingSpecs;
    }
    
	return _specifiers;
}

-(NSArray *)localizedSpecifiersForSpecifiers:(NSArray *)s {
	int i;
	for (i=0; i<[s count]; i++) {
		if ([[s objectAtIndex: i] name]) {
			[[s objectAtIndex: i] setName:[[self bundle] localizedStringForKey:[[s objectAtIndex: i] name] value:[[s objectAtIndex: i] name] table:nil]];
		}
		if ([[s objectAtIndex: i] titleDictionary]) {
			NSMutableDictionary *newTitles = [[NSMutableDictionary alloc] init];
			for(NSString *key in [[s objectAtIndex: i] titleDictionary]) {
				[newTitles setObject: [[self bundle] localizedStringForKey:[[[s objectAtIndex: i] titleDictionary] objectForKey:key] value:[[[s objectAtIndex: i] titleDictionary] objectForKey:key] table:nil] forKey: key];
			}
			[[s objectAtIndex: i] setTitleDictionary: newTitles];
		}
	}
	
	return s;
}

-(NSArray*)getPrefsForIndex:(int)index {
    currentIndex = index;
    NSMutableArray *specifiers = [NSMutableArray array];
    
    switch (index) {
        case 0:
            specifiers = [self preferencesForManage];
            [specifiers addObjectsFromArray:[self loadSpecifiersFromPlistName:@"Manage" target:self]];
            break;
        case 1:
            specifiers = [self loadSpecifiersFromPlistName:@"Advanced" target:self];
            break;
        case 2:
            specifiers = [self loadSpecifiersFromPlistName:@"Support" target:self];
            break;
    }
    
    specifiers = (NSMutableArray*)[self localizedSpecifiersForSpecifiers:specifiers];
    
    return specifiers;
}

- (UITableViewCell*)tableView:(UITableView*)arg1 cellForRowAtIndexPath:(NSIndexPath*)arg2 {
    UITableViewCell *cell = [super tableView:arg1 cellForRowAtIndexPath:arg2];
    
    if (arg2.section > 1 || currentIndex != 0) {
        return cell;
    }
    
    NSString *bundleIdentifier;
    
    if (arg2.section == 0) {
        bundleIdentifier = dataSourceSystem.allKeys[arg2.row];
    } else if (arg2.section == 1) {
        bundleIdentifier = dataSourceUser.allKeys[arg2.row];
    }
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        UIImage *img = [[ALApplicationList sharedApplicationList] iconOfSize:ALApplicationIconSizeSmall forDisplayIdentifier:bundleIdentifier];
        dispatch_async(dispatch_get_main_queue(), ^(void){
            cell.imageView.image = img;
            [cell setNeedsLayout];
        });
    });
    return cell;
}

-(NSMutableArray*)preferencesForManage {
    NSMutableArray *specifiers = [NSMutableArray array];
    
    if (!strings)
        strings = [[NSBundle alloc] initWithPath:@"/Library/PreferenceBundles/Convergance-Prefs.bundle"];
    
    NSPredicate *pred = [NSPredicate predicateWithFormat:@"isSystemApplication = TRUE"];
    dataSourceSystem = (OrderedDictionary*)[[ALApplicationList sharedApplicationList] applicationsFilteredUsingPredicate:pred];
    dataSourceSystem = (OrderedDictionary*)[self trimDataSource:dataSourceSystem];
    dataSourceSystem = [self sortedDictionary:dataSourceSystem];
    
    NSPredicate *predi = [NSPredicate predicateWithFormat:@"isSystemApplication = FALSE"];
    dataSourceUser = (OrderedDictionary*)[[ALApplicationList sharedApplicationList] applicationsFilteredUsingPredicate:predi];
    dataSourceUser = (OrderedDictionary*)[self trimDataSource:dataSourceUser];
    dataSourceUser = [self sortedDictionary:dataSourceUser];
    
    // Begin generating specifiers.
    
    PSSpecifier* groupSpecifier = [PSSpecifier groupSpecifierWithName:[strings localizedStringForKey:@"System Applications:" value:@"System Applications:" table:@"Root"]];
    [specifiers addObject:groupSpecifier];
    
    for (NSString *bundleIdentifier in dataSourceSystem.allKeys) {
        NSString *displayName = dataSourceSystem[bundleIdentifier];
        
        PSSpecifier *spe = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:@selector(getIsWidgetSetForSpecifier:) detail:[IBKWidgetSettingsController class] cell:PSLinkListCell edit:nil];
        [spe setProperty:@"IBKWidgetSettingsController" forKey:@"detail"];
        [spe setProperty:[NSNumber numberWithBool:YES] forKey:@"isController"];
        [spe setProperty:[NSNumber numberWithBool:YES] forKey:@"enabled"];
        [spe setProperty:bundleIdentifier forKey:@"bundleIdentifier"];
        //[spe setProperty:@"Advanced.png" forKey:@"icon"];
        //[spe setupIconImageWithBundle:strings];
        
        [specifiers addObject:spe];
    }
    
    PSSpecifier* groupSpecifier2 = [PSSpecifier groupSpecifierWithName:[strings localizedStringForKey:@"User Applications:" value:@"User Applications:" table:@"Root"]];
    [specifiers addObject:groupSpecifier2];
    
    for (NSString *bundleIdentifier in dataSourceUser.allKeys) {
        NSString *displayName = dataSourceUser[bundleIdentifier];
        
        PSSpecifier *spe = [PSSpecifier preferenceSpecifierNamed:displayName target:self set:nil get:@selector(getIsWidgetSetForSpecifier:) detail:[IBKWidgetSettingsController class] cell:PSLinkListCell edit:nil];
        [spe setProperty:@"IBKWidgetSettingsController" forKey:@"detail"];
        [spe setProperty:[NSNumber numberWithBool:YES] forKey:@"isController"];
        [spe setProperty:[NSNumber numberWithBool:YES] forKey:@"enabled"];
        [spe setProperty:bundleIdentifier forKey:@"bundleIdentifier"];
        //[spe setProperty:@"Advanced.png" forKey:@"icon"];
        //[spe setupIconImageWithBundle:strings];
        
        [specifiers addObject:spe];
    }
    
    return specifiers;
}

-(NSString*)getIsWidgetSetForSpecifier:(PSSpecifier*)spec {
    NSString *bundleIdentifier = [spec propertyForKey:@"bundleIdentifier"];
    
    NSString *path = [NSString stringWithFormat:@"/var/mobile/Library/Curago/Widgets/%@", [self getRedirectedIdentifierIfNeeded:bundleIdentifier]];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return @"";
    } else {
        return @"Set widget";
    }
}

-(NSString*)getRedirectedIdentifierIfNeeded:(NSString*)identifier {
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.matchstic.curago.plist"];
    
    NSDictionary *dict = settings[@"redirectedIdentifiers"];
    
    if (dict && [dict objectForKey:identifier])
        return [dict objectForKey:identifier];
    else
        return identifier;
}

-(void)loadInPrefsForIndex:(int)index animated:(BOOL)animated {
    NSArray *specifiers = [self getPrefsForIndex:index];
    
    for (int i = (int)[self.specifiers count] - 1; i > -1; i--) {
        [self removeSpecifier:[_specifiers objectAtIndex:i] animated:animated];
    }
    
    [self insertContiguousSpecifiers:specifiers atIndex:0 animated:animated];
}

-(NSDictionary*)trimDataSource:(NSDictionary*)dataSource {
    NSMutableDictionary *mutable = [dataSource mutableCopy];
    
    NSArray *bannedIdentifiers = [[NSArray alloc] initWithObjects:
                                  @"com.apple.AdSheet",
                                  @"com.apple.AdSheetPhone",
                                  @"com.apple.AdSheetPad",
                                  @"com.apple.DataActivation",
                                  @"com.apple.DemoApp",
                                  @"com.apple.fieldtest",
                                  @"com.apple.iosdiagnostics",
                                  @"com.apple.iphoneos.iPodOut",
                                  @"com.apple.TrustMe",
                                  @"com.apple.WebSheet",
                                  @"com.apple.springboard",
                                  @"com.apple.purplebuddy",
                                  @"com.apple.datadetectors.DDActionsService",
                                  @"com.apple.FacebookAccountMigrationDialog",
                                  @"com.apple.iad.iAdOptOut",
                                  @"com.apple.ios.StoreKitUIService",
                                  @"com.apple.TextInput.kbd",
                                  @"com.apple.MailCompositionService",
                                  @"com.apple.mobilesms.compose",
                                  @"com.apple.quicklook.quicklookd",
                                  @"com.apple.ShoeboxUIService",
                                  @"com.apple.social.remoteui.SocialUIService",
                                  @"com.apple.WebViewService",
                                  @"com.apple.gamecenter.GameCenterUIService",
                                  @"com.apple.appleaccount.AACredentialRecoveryDialog",
                                  @"com.apple.CompassCalibrationViewService",
                                  @"com.apple.WebContentFilter.remoteUI.WebContentAnalysisUI",
                                  @"com.apple.PassbookUIService",
                                  @"com.apple.uikit.PrintStatus",
                                  @"com.apple.Copilot",
                                  @"com.apple.MusicUIService",
                                  @"com.apple.AccountAuthenticationDialog",
                                  @"com.apple.MobileReplayer",
                                  @"com.apple.SiriViewService",
                                  @"com.apple.TencentWeiboAccountMigrationDialog",
                                  @"com.apple.AskPermissionUI",
                                  @"com.apple.Diagnostics",
                                  @"com.apple.GameController",
                                  @"com.apple.HealthPrivacyService",
                                  @"com.apple.InCallService",
                                  @"com.apple.mobilesms.notification",
                                  @"com.apple.PhotosViewService",
                                  @"com.apple.PreBoard",
                                  @"com.apple.PrintKit.Print-Center",
                                  @"com.apple.SharedWebCredentialViewService",
                                  @"com.apple.share",
                                  @"com.apple.CoreAuthUI",
                                  @"com.apple.webapp",
                                  @"com.apple.webapp1",
                                  @"com.apple.family",
                                  nil];
    for (NSString *key in bannedIdentifiers) {
        [mutable removeObjectForKey:key];
    }
    
    return mutable;
}

-(OrderedDictionary*)sortedDictionary:(OrderedDictionary*)dict {
    NSArray *sortedValues;
    OrderedDictionary *mutable = [OrderedDictionary dictionary];
    
    sortedValues = [[dict allValues] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    for (NSString *value in sortedValues) {
        // Get key for value.
        NSString *key = [[dict allKeysForObject:value] objectAtIndex:0];
        
        [mutable setObject:value forKey:key];
    }
    
    return mutable;
}

-(void)composeSupportEmail:(id)sender {
    struct utsname systemInfo;
    uname(&systemInfo);
    
    NSString *machineName = [NSString stringWithCString:systemInfo.machine
                                               encoding:NSUTF8StringEncoding];
    
    NSString *emailTitle = @"iOS Blocks Feedback";
    
    NSString *messageBody = [NSString stringWithFormat:@"%@ %@ : %@", machineName, [[UIDevice currentDevice] systemVersion], (NSString*)CFBridgingRelease(MGCopyAnswer(kMGUniqueDeviceID))];
    NSArray *toRecipents = [NSArray arrayWithObject:@"matt@incendo.ws"];
    
    MFMailComposeViewController *mc = [[MFMailComposeViewController alloc] init];
    mc.mailComposeDelegate = self;
    [mc setSubject:emailTitle];
    [mc setMessageBody:messageBody isHTML:NO];
    [mc setToRecipients:toRecipents];
    
    [mc addAttachmentData:[NSData dataWithContentsOfFile:@"/var/mobile/Library/Preferences/com.matchstic.curago.plist"] mimeType:@"application/xml" fileName:@"Preferences.plist"];
    
    // We also want the dpkg log
    system("/usr/bin/dpkg -l >/tmp/dpkgl.log");
    [mc addAttachmentData:[NSData dataWithContentsOfFile:@"/tmp/dpkgl.log"] mimeType:@"text/plain" fileName:@"dpkgl.txt"];
    
    // Present mail view controller on screen
    [self.parentController presentModalViewController:mc animated:YES];
}

-(void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [self.parentController dismissModalViewControllerAnimated:YES];
}

-(void)openHelpCenter:(id)sender {

}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    
    if (!parent) {
        currentIndex = 0;
    }
}

-(id)readPreferenceValue:(PSSpecifier*)specifier {
	NSDictionary *exampleTweakSettings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.matchstic.curago.plist"];
	if (!exampleTweakSettings[specifier.properties[@"key"]]) {
		return specifier.properties[@"default"];
	}
	return exampleTweakSettings[specifier.properties[@"key"]];
}

-(void)setPreferenceValue:(id)value specifier:(PSSpecifier*)specifier {
	NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
	[defaults addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.matchstic.curago.plist"]];
	[defaults setObject:value forKey:specifier.properties[@"key"]];
	[defaults writeToFile:@"/var/mobile/Library/Preferences/com.matchstic.curago.plist" atomically:YES];
	CFStringRef toPost = (__bridge CFStringRef)specifier.properties[@"PostNotification"];
	if(toPost) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), toPost, NULL, NULL, YES);
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    [self.headerview beginAnimations];
}

-(void)viewWillAppear:(BOOL)view {
    self.headerview.frame = CGRectMake(0, 0, self.table.frame.size.width, 345);
    [self.table setTableHeaderView:self.headerview];
    
    // Set title!
    
    if ([self respondsToSelector:@selector(navigationItem)]) {
        [[self navigationItem] setTitle:@"iOS Blocks"];
    }
    
    [super viewWillAppear:view];
}

@end