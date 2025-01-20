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

#import "GroupCreateMessage.h"
#import "ProtocolDefines.h"

@implementation GroupCreateMessage

@synthesize groupMembers;

- (uint8_t)type {
    return MSGTYPE_GROUP_CREATE;
}

- (NSData *)body {
    NSMutableData *body = [NSMutableData dataWithData:self.groupId];
    
    for (NSString *identity in groupMembers) {
        [body appendData:[identity dataUsingEncoding:NSASCIIStringEncoding]];
    }
    
    return body;
}

- (BOOL)flagShouldPush {
    return NO;
}

- (BOOL)isContentValid {
    return YES;
}

- (NSString *)description {
    NSString *result = [super description];
    return [result stringByAppendingFormat:@" group create - members: %@", groupMembers];
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
        self.groupMembers = [decoder decodeObjectOfClasses:[NSSet setWithArray:@[[NSArray class], [NSString class]]] forKey:@"groupMembers"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [super encodeWithCoder:encoder];
    [encoder encodeObject:self.groupMembers forKey:@"groupMembers"];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
