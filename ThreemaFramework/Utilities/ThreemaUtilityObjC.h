//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2025 Threema GmbH
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

#import <Foundation/Foundation.h>
#import "ContactEntity.h"

__deprecated_msg("Use ThreemaUtility instead")
@interface ThreemaUtilityObjC : NSObject

+ (void)reverseGeocodeNearLatitude:(double)latitude longitude:(double)longitude accuracy:(double)accuracy completion:(void (^)(NSString *label))completion onError:(void(^)(NSError *error))onError __deprecated_msg("Use fetchAddress() instead");

+ (time_t)systemUptime;

+ (NSString *)timeStringForSeconds: (NSInteger) totalSeconds;
+ (NSString *)accessibilityTimeStringForSeconds: (NSInteger) totalSeconds;
+ (NSString *)accessibilityStringAtTime:(NSTimeInterval)timeInterval withPrefix:(NSString *)prefixKey;

+ (NSDate*)parseISO8601DateString:(NSString*)dateString;

+ (NSString *)formatDataLength:(CGFloat)numBytes;

+ (BOOL)isValidEmail:(NSString *)email;

+ (UIViewAnimationOptions)animationOptionsFor:(NSNotification *)notification animationDuration:(NSTimeInterval*)animationDuration;

+ (UIImage *)makeThumbWithOverlayFor:(UIImage *)image;

+ (NSData*)truncatedUTF8String:(NSString*)str maxLength:(NSUInteger)maxLength;

+ (void)sendErrorLocalNotification:(NSString *)title body:(NSString *)body userInfo:(NSDictionary *)userInfo;

+ (void)sendErrorLocalNotification:(NSString *)title body:(NSString *)body userInfo:(NSDictionary *)userInfo onCompletion:(void(^)(void))onCompletion;

+ (void)waitForSeconds:(int)count finish:(void(^)(void))finish;

@end
