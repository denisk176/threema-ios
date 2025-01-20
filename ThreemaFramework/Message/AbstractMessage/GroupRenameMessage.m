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

#import "GroupRenameMessage.h"
#import "ProtocolDefines.h"

@implementation GroupRenameMessage

@synthesize name;

- (uint8_t)type {
    return MSGTYPE_GROUP_RENAME;
}

- (NSData *)body {
    NSMutableData *body = [NSMutableData dataWithData:self.groupId];
    [body appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
    
    return body;
}

- (BOOL)flagShouldPush {
    return NO;
}

- (BOOL)isContentValid {
    return YES;
}

- (BOOL)allowSendingProfile {
    return YES;
}

- (BOOL)canShowUserNotification {
    return NO;
}

- (BOOL)isGroupControlMessage {
    return true;
}

- (BOOL)canUnarchiveConversation {
    return NO;
}

- (ObjcCspE2eFs_Version)minimumRequiredForwardSecurityVersion {
    return kV12;
}

#pragma mark - NSSecureCoding

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super initWithCoder:decoder]) {
        self.name = [decoder decodeObjectOfClass:[NSString class] forKey:@"name"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [super encodeWithCoder:encoder];
    [encoder encodeObject:self.name forKey:@"name"];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
