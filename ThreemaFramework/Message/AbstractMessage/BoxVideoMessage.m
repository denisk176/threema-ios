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

#import "BoxVideoMessage.h"
#import "ProtocolDefines.h"

@implementation BoxVideoMessage

@synthesize duration;
@synthesize videoBlobId;
@synthesize videoSize;
@synthesize thumbnailBlobId;
@synthesize thumbnailSize;
@synthesize encryptionKey;

- (uint8_t)type {
    return MSGTYPE_VIDEO;
}

- (NSData *)body {
    NSMutableData *body = [NSMutableData data];
    
    [body appendBytes:&duration length:sizeof(uint16_t)];
    [body appendData:videoBlobId];
    [body appendBytes:&videoSize length:sizeof(uint32_t)];
    [body appendData:thumbnailBlobId];
    [body appendBytes:&thumbnailSize length:sizeof(uint32_t)];
    [body appendData:encryptionKey];
    
    return body;
}

- (BOOL)flagShouldPush {
    return YES;
}

-(BOOL)isContentValid {
    if (videoSize == 0 || thumbnailSize == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)allowSendingProfile {
    return YES;
}

- (BOOL)supportsForwardSecurity {
    return YES;
}

- (ObjcCspE2eFs_Version)minimumRequiredForwardSecurityVersion {
    return kUnspecified;
}

#pragma mark - NSSecureCoding

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super initWithCoder:decoder]) {
        self.duration = (uint16_t)[decoder decodeIntegerForKey:@"duration"];
        self.videoBlobId = [decoder decodeObjectOfClass:[NSData class] forKey:@"videoBlobId"];
        self.videoSize = (uint32_t)[decoder decodeIntegerForKey:@"videoSize"];
        self.thumbnailBlobId = [decoder decodeObjectOfClass:[NSData class] forKey:@"thumbnailBlobId"];
        self.thumbnailSize = (uint32_t)[decoder decodeIntegerForKey:@"thumbnailSize"];
        self.encryptionKey = [decoder decodeObjectOfClass:[NSData class] forKey:@"encryptionKey"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [super encodeWithCoder:encoder];
    [encoder encodeInt:self.duration forKey:@"duration"];
    [encoder encodeObject:self.videoBlobId forKey:@"videoBlobId"];
    [encoder encodeInt:self.videoSize forKey:@"videoSize"];
    [encoder encodeObject:self.thumbnailBlobId forKey:@"thumbnailBlobId"];
    [encoder encodeInt:self.thumbnailSize forKey:@"thumbnailSize"];
    [encoder encodeObject:self.encryptionKey forKey:@"encryptionKey"];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
