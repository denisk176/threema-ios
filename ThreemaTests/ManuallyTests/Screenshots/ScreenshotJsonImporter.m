//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2025 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#import <XCTest/XCTest.h>
#import <ThreemaFramework/MyIdentityStore.h>
#import "ScreenshotJsonParser.h"
#import "UserSettings.h"
#import "AppGroup.h"
#import "LicenseStore.h"
#import "BundleUtil.h"
#import <Photos/Photos.h>
#import <ThreemaFramework/ThreemaFramework-Swift.h>

@import CocoaLumberjack;

static const DDLogLevel ddLogLevel = DDLogLevelVerbose;

#define FULLDATE_COMPONENTS NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth |  NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond

@interface ScreenshotJsonImporter : XCTestCase

@property NSURL *buildURL;
@property (nonatomic, strong) NSString *language;

@end

@implementation ScreenshotJsonImporter

- (void)setUp {
    [super setUp];
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    
    // get the path from where the tests were started
    NSString *frameworkPaths = environment[@"DYLD_FRAMEWORK_PATH"];
    NSString *buildPath = [frameworkPaths componentsSeparatedByString:@":"][0];
    _buildURL = [[NSURL URLWithString:buildPath] URLByDeletingLastPathComponent];
    
    NSString *prefix = [self pathPrefix];
    NSString *path = [prefix stringByAppendingPathComponent:@"language.txt"];
    NSCharacterSet *trimCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    _language = [[NSLocale preferredLanguages] firstObject];
    if([_language isEqualToString:@"tr"]) {
        _language = @"tr-TR";
    }
    else if([_language isEqualToString:@"ja"]) {
        _language = @"ja-JP";
    }
}

- (void)testLoadJsonFile {
    ScreenshotJsonParser *parser = [ScreenshotJsonParser new];
    
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        
    }];

    NSString *resetDevice = [self getResetCommand];
    if (resetDevice) {
        DDLogInfo(@"ScreenshotJsonImporter: resetting device");
        [[MyIdentityStore sharedMyIdentityStore] destroy];
        
        if ([LicenseStore requiresLicenseKey]) {
            [[LicenseStore sharedLicenseStore] deleteLicense];
        }
    }
    
    NSString *srcroot = [[[NSProcessInfo processInfo] environment] objectForKey:@"SRCROOT"];
    NSString *appPath = nil;
    switch ([ThreemaAppObjc current]) {
        case ThreemaAppThreema:
            appPath = @"consumer";
            break;
        case ThreemaAppWork:
            appPath = @"work";
            break;
        case ThreemaAppOnPrem:
            appPath = @"onprem";
            break;
        default:
            appPath = @"consumer";
            break;
    }
    NSString *screenshotProject = [NSString stringWithFormat:@"screenshot/chat_data/%@", appPath                                                                  ];
    NSURL *screenShotDataURL = [NSURL URLWithString:[srcroot stringByReplacingOccurrencesOfString:@"ios-client" withString:screenshotProject]];

        
    if (_language == nil) {
        XCTFail(@"no language code %@, probably not started from screenshot environment", _language);
        return;
    }

    parser.languageCode = _language;
    

    parser.referenceDate = [self referenceDateForHour:9];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    BOOL isDir;
    if ([fileManager fileExistsAtPath:screenShotDataURL.path isDirectory:&isDir] && isDir) {
        [self setupUserSettings];
        
        [parser clearAll];
        
        [parser loadDataFromDirectory:screenShotDataURL.path];
    } else {
        XCTFail(@"json import data not found at: %@", screenShotDataURL.path);
        return;
    }
}

- (NSString *)pathPrefix {
    NSString *path = [[[NSProcessInfo processInfo] environment] objectForKey:@"SIMULATOR_HOST_HOME"];
    if (path)
        return [path stringByAppendingPathComponent:@"Library/Caches/tools.fastlane"];
    return nil;
}

- (NSString *)getColorTheme {
    return [self getCommandFromFile:@"colorTheme.txt"];
}

- (NSString *)getResetCommand {
    return [self getCommandFromFile:@"resetDeviceCommand.txt"];
}

- (NSString *)getCommandFromFile:(NSString *)fileName {
    NSURL *fileURL = [_buildURL URLByAppendingPathComponent:fileName];
    NSString *command = [NSString stringWithContentsOfFile:fileURL.path usedEncoding:nil error:nil];
    command = [command stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    return command;
}

- (void)setupUserSettings {
    UserSettings *settings = [UserSettings sharedUserSettings];
    settings.syncContacts = YES;
    [settings setSortOrderFirstName:NO displayOrderFirstName:YES];
    
    // set some flags to avoid reminder popups    
    [[AppGroup userDefaults] setObject:[NSDate date] forKey:@"PushReminderShowDate"];
    [[AppGroup userDefaults] setBool:YES forKey:@"LinkReminderShown"];
    [[AppGroup userDefaults] setBool:YES forKey:@"PublicNicknameReminderShown"];

}

- (NSDate *)referenceDateForHour:(NSInteger)hour {
    NSCalendar *calendar = [NSCalendar autoupdatingCurrentCalendar];
    NSDate *now = [NSDate date];
    
    NSDateComponents *dateComponents = [calendar components:FULLDATE_COMPONENTS fromDate:now];
    dateComponents.second = 0;
    dateComponents.minute = 0;
    dateComponents.hour = 0;
    NSDate *beginningOfDay = [calendar dateFromComponents:dateComponents];
    
    return [beginningOfDay dateByAddingTimeInterval:(hour * 60 * 60)];
}

@end
