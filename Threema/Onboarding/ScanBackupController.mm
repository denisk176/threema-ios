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

#import <UniformTypeIdentifiers/UTCoreTypes.h>
#import "BundleUtil.h"
#import "ScanBackupController.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "PortraitNavigationController.h"
#import "UIDefines.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif
@implementation ScanBackupController

+ (BOOL)canScan {
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        NSArray *mediaTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
        return [mediaTypes containsObject:(NSString *)UTTypeMovie.identifier];
    }
    return NO;
}

- (void)startScan {
    [MBProgressHUD hideHUDForView:self.containingViewController.view animated:NO];
    
    if (self.containingViewController.view != nil) {
        [MBProgressHUD showHUDAddedTo:self.containingViewController.view animated:YES];
    }
    
    QRScannerViewController *qrController = [[QRScannerViewController alloc] init];
    
    qrController.delegate = self;
    qrController.title = [BundleUtil localizedStringForKey:@"scan_backup"];
    
    UINavigationController *nav = [[PortraitNavigationController alloc] initWithRootViewController:qrController];
    nav.navigationBar.barStyle = UIBarStyleBlackTranslucent;
    nav.navigationBar.tintColor = Colors.primaryWizard;
    nav.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    
    [self.containingViewController presentViewController:nav animated:YES completion:nil];
}

#pragma mark - QRScannerViewControllerDelegate

- (void)qrScannerViewController:(QRScannerViewController *)controller didScanResult:(NSString *)result {
    DDLogVerbose(@"Scanned data: %@", result);
    [MBProgressHUD hideHUDForView:self.containingViewController.view animated:NO];
    [self.delegate didScanBackup:result];
    [controller dismissViewControllerAnimated:YES completion:nil];
}

- (void)qrScannerViewController:(QRScannerViewController *)controller didCancelAndWillDismissItself:(BOOL)willDismissItself {
    DDLogVerbose(@"Scan cancelled");
    [MBProgressHUD hideHUDForView:self.containingViewController.view animated:NO];
    if (!willDismissItself) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
