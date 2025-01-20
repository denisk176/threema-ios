//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2025 Threema GmbH
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

#import "AbstractMessage.h"

@interface MessageDecoder : NSObject

/**
 Decrypt and decode Boxed Message.
 
 @param boxmsg: Incoming Boxed Message
 @param publicKey: Public key of sender contact

 @return Decoded message
 */
+ (AbstractMessage*)decodeFromBoxed:(BoxedMessage*)boxmsg withPublicKey:(NSData*)publicKey;

/**
 Decode message depending on type
 
 @param type: Message Type (MSGTYPE_...), see in `ProtocolDefines.h`
 @param body: Decrypted message data
 
 @return Decoded message
 */
+ (AbstractMessage *)decode:(int)type body:(NSData *)body;

+ (AbstractMessage*)decodeRawBody:(NSData*)data realDataLength:(int)realDataLength; __deprecated_msg("Only to be used in MessageDecoder+Swift.swift.");

@end
