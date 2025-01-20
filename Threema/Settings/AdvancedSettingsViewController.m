//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2013-2025 Threema GmbH
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

#import "AdvancedSettingsViewController.h"
#import "UserSettings.h"
#import "ValidationLogger.h"
#import "NSString+Hex.h"
#import "AppDelegate.h"
#import "AppGroup.h"
#import "ServerConnector.h"
#import "BundleUtil.h"
#import "ThreemaFramework/ThreemaFramework-swift.h"
#import "ActivityUtil.h"
#import "ThreemaUtilityObjC.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "Threema-Swift.h"
#import "ThreemaFramework/ThreemaFramework-swift.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
static const DDLogLevel ddLogLevel = DDLogLevelNotice;
#endif

@implementation AdvancedSettingsViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.validationLoggingSwitch.on = [UserSettings sharedUserSettings].validationLogging;
    self.enableIPv6Switch.on = [UserSettings sharedUserSettings].enableIPv6;
    self.proximityMonitoringSwitch.on = ![UserSettings sharedUserSettings].disableProximityMonitoring;
    
    // Do not use Sentry for onprem
    // OnPrem target has a macro with DISABLE_SENTRY
#ifndef DISABLE_SENTRY
    self.sentryAppDeviceLabel.text = [UserSettings sharedUserSettings].sentryAppDevice != nil ? [UserSettings sharedUserSettings].sentryAppDevice : @"-";
#endif
    
    self.orphanedFilesCleanupLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_orphaned_files_cleanup"];

    self.contactsCleanupLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_contacts_cleanup"];

    self.reregisterPushNotificationsLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_reregister_notifications_label"];
    
    self.resetFSDBLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_reset_fs_db_label"];
    
    self.resetUnreadCountLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_reset_unread_count_label"];
    
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self updateLogSize];
    
    _flushMessageQueueCell.textLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_flush_message_queue"];
    
    EntityManager *entityManager = [[EntityManager alloc] init];
    DDLogNotice(@"There are %ld file messages with no MIME type", (long)[entityManager.entityFetcher countFileMessagesWithNoMIMEType]);

}

- (void)updateLogSize {
    self.logSizeLabel.text = [NSString stringWithFormat:@"%lld KB", ([LogManager logFileSize:[LogManager debugLogFile]] + 1023) / 1024];
}

- (BOOL)shouldAutorotate {
    return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (SYSTEM_IS_IPAD) {
        return UIInterfaceOrientationMaskAll;
    }
    
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

- (IBAction)enableIPv6Changed:(id)sender {
    [UserSettings sharedUserSettings].enableIPv6 = self.enableIPv6Switch.on;
    [self.tableView reloadData];
    [[ServerConnector sharedServerConnector] reconnect];
}

- (IBAction)validationLoggingChanged:(id)sender {
    [UserSettings sharedUserSettings].validationLogging = self.validationLoggingSwitch.on;
    
    if ([UserSettings sharedUserSettings].validationLogging) {
        [LogManager addFileLogger:[LogManager debugLogFile]];
        
        DDLogNotice(@"Start logging %@", ThreemaUtility.clientVersionWithMDM);
    }
    else {
        [LogManager removeFileLogger:[LogManager debugLogFile]];
    }
}

- (IBAction)proximityMonitoringChanged:(id)sender {
    [UserSettings sharedUserSettings].disableProximityMonitoring = !self.proximityMonitoringSwitch.on;
    [self.tableView reloadData];
}

#pragma mark - UITableView

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
#ifdef DISABLE_SENTRY
    // Hide sentry if it's disabled
    if (section == 3) {
        return 0;
    }
#endif
    
    if (![SettingsBundleHelper safeMode]) {
        if (section == 7) {
            return 0.0;
        }
    }
    
    return [super tableView:tableView numberOfRowsInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
#ifdef DISABLE_SENTRY
    // Hide sentry if it's disabled
    if (indexPath.section == 3) {
        return 0.0;
    }
#endif
    
    if (![SettingsBundleHelper safeMode]) {
        if (indexPath.section == 7) {
            return 0.0;
        }
    }
    
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
#ifdef DISABLE_SENTRY
    // Hide sentry if it's disabled
    if (section == 3) {
        return 0.0;
    }
#endif
    
    if (![SettingsBundleHelper safeMode]) {
        if (section == 7) {
            return 0.0;
        }
    }
    
    return [super tableView:tableView heightForHeaderInSection:section];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
#ifdef DISABLE_SENTRY
    // Hide sentry if it's disabled
    if (section == 3) {
        return 0.0;
    }
#endif
    
    if (![SettingsBundleHelper safeMode]) {
        if (section == 7) {
            return 0.0;
        }
    }
    
    return [super tableView:tableView heightForFooterInSection:section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        if ([UserSettings sharedUserSettings].disableProximityMonitoring) {
            return [BundleUtil localizedStringForKey:@"settings_advanced_proximity_monitoring_section_footer_off"];
        } else {
            return [BundleUtil localizedStringForKey:@"settings_advanced_proximity_monitoring_section_footer_on"];
        }
    }
    
    if (section == 6) {
        return [BundleUtil localizedStringForKey:@"settings_advanced_reregister_push_notifications_footer_title"];
    }
    
    if (section == 7) {
        return [BundleUtil localizedStringForKey:@"settings_advanced_support_settings_footer_title"];
    }
    
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 6) {
        return [BundleUtil localizedStringForKey:@"settings_advanced_reregister_push_notifications_header_title"];
    } else if (section == 7) {
        return [BundleUtil localizedStringForKey:@"settings_advanced_support_settings_header_title"];
    } else {
        return [super tableView:tableView titleForHeaderInSection:section];
    }
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    
    _logSizeLabel.textColor = Colors.textLight;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (indexPath.section == 2 && indexPath.row == 2) {
        /* share log */
        if ([LogManager logFileSize:[LogManager debugLogFile]] > 0) {
            UIActivityViewController *activityViewController = [ActivityUtil activityViewControllerWithActivityItems:@[[LogManager debugLogFile]] applicationActivities:nil];

            if (SYSTEM_IS_IPAD == YES) {
                
                CGRect rect = [tableView rectForRowAtIndexPath:indexPath];
                activityViewController.popoverPresentationController.sourceRect = rect;
                activityViewController.popoverPresentationController.sourceView = self.view;
            }
            [self presentViewController:activityViewController animated:YES completion:nil];
        } else {
            [UIAlertTemplate showAlertWithOwner:self title:@"" message:[BundleUtil localizedStringForKey:@"log_empty_message"] actionOk:nil];
        }
    } else if (indexPath.section == 2 && indexPath.row == 3) {
        /* clear log */
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [actionSheet addAction:[UIAlertAction actionWithTitle:[BundleUtil localizedStringForKey:@"debug_log_clear"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction * action) {
            
            [LogManager deleteLogFile:[LogManager debugLogFile]];
            [LogManager deleteLogFile:[LogManager validationLogFile]];
            [self updateLogSize];
        }]];
        [actionSheet addAction:[UIAlertAction actionWithTitle:[BundleUtil localizedStringForKey:@"cancel"] style:UIAlertActionStyleCancel handler:nil]];
        
        if (!self.tabBarController) {
            CGRect cellRect = [tableView rectForRowAtIndexPath:indexPath];
            actionSheet.popoverPresentationController.sourceRect = cellRect;
            actionSheet.popoverPresentationController.sourceView = self.view;
        }
        
        [self presentViewController:actionSheet animated:YES completion:nil];
        
    }
    else if (indexPath.section == 3 && indexPath.row == 1) {
        DDLogWarn(@"Manually flushing outgoing task queue.");
        [TaskManager flushWithQueueType:TaskQueueTypeOutgoing];
        TaskManager *tm = [TaskManager new];
        [tm spool];
        [NotificationBannerHelper newSuccessToastWithTitle:[BundleUtil localizedStringForKey:@"settings_advanced_flush_message_queue"] body:[BundleUtil localizedStringForKey:@"ok"]];
    } else if (indexPath.section == 6 && indexPath.row == 0) {
        [self reregisterPushNotifications];
    } else if (indexPath.section == 7 && indexPath.row == 0) {
        [self resetUnreadCount];
    }
    else if (indexPath.section == 7 && indexPath.row == 1) {
        [self resetFSDB];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(void)reregisterPushNotifications {
    [UIApplication.sharedApplication unregisterForRemoteNotifications];
    DDLogInfo(@"Unregistered for remote notifications");
    [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:true];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        BOOL stillRegistered = [UIApplication.sharedApplication isRegisteredForRemoteNotifications];
        DDLogInfo(@"We are still registered for notifications %d", stillRegistered);
        [UIApplication.sharedApplication registerForRemoteNotifications];
        DDLogInfo(@"Reregistered for remote notifications");
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [MBProgressHUD hideHUDForView:self.navigationController.view animated:true];
        [NotificationBannerHelper newSuccessToastWithTitle:[BundleUtil localizedStringForKey:@"settings_advanced_reregister_notifications_label"] body:[BundleUtil localizedStringForKey:@"ok"]];
    });
}

- (void)resetFSDB {
    [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:true];
    
    [SQLDHSessionStoreObjcHelper deleteSessionDB];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [MBProgressHUD hideHUDForView:self.navigationController.view animated:true];
        [NotificationBannerHelper newSuccessToastWithTitle:[BundleUtil localizedStringForKey:@"settings_advanced_successfully_deleted_fs_sessions_label"] body:[BundleUtil localizedStringForKey:@"ok"]];
        
        [SettingsBundleHelper resetSafeMode];
    
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sleep(2);
            exit(EXIT_SUCCESS);
        });
    });
}

- (void)resetUnreadCount {
    [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:true];
    
    __block BusinessInjector *businessInjector = [[BusinessInjector alloc] init];
    [businessInjector.backgroundEntityManager performSyncBlockAndSafe:^{
        UnreadMessages *unreadMessages = [[UnreadMessages alloc] initWithEntityManager:businessInjector.backgroundEntityManager];
       
        NSBatchUpdateRequest *batch = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Message"];
        batch.resultType = NSStatusOnlyResultType;
        batch.predicate = [NSPredicate predicateWithFormat:@"read == false && isOwn == false"];
        batch.propertiesToUpdate = @{@"read": @YES};
        NSBatchUpdateResult *batchResult = [businessInjector.backgroundEntityManager.entityFetcher executeBatchUpdateRequest:batch];
        if ([batchResult.result isKindOfClass:[NSNumber class]]){
            if ([batchResult.result boolValue] == true){
                DDLogNotice(@"[Advanced Support Mode] Succeeded to set all unread messages to read.");
            }
            else {
                DDLogError(@"[Advanced Support Mode] Failed to set all unread messages to read. ResultCount is 0");
            }
        }
        else {
            DDLogError(@"[Advanced Support Mode] Failed to set all unread messages to read. Result is nil.");
        }
        
        NSSet *allConversations = [NSSet setWithArray:businessInjector.backgroundEntityManager.entityFetcher.allConversations];
        [unreadMessages totalCountWithDoCalcUnreadMessagesCountOf:allConversations withPerformBlockAndWait:YES];
    }];
    
    NotificationManager *notificationManager = [[NotificationManager alloc] init];
    [notificationManager updateUnreadMessagesCount];
                    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [MBProgressHUD hideHUDForView:self.navigationController.view animated:true];
        [NotificationBannerHelper newSuccessToastWithTitle:[BundleUtil localizedStringForKey:@"settings_advanced_successfully_reset_unread_count_label"] body:[BundleUtil localizedStringForKey:@"ok"]];
        
        [SettingsBundleHelper resetSafeMode];
    
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            sleep(2);
            exit(EXIT_SUCCESS);
        });
    });
}

@end
