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

#import "ValidationLogger.h"
#import "BoxedMessage.h"
#import "AbstractMessage.h"
#import "NSString+Hex.h"
#import "ContactStore.h"
#import "BoxVoIPCallOfferMessage.h"
#import "BoxVoIPCallAnswerMessage.h"
#import "BoxVoIPCallIceCandidatesMessage.h"
#import "DeliveryReceiptMessage.h"
#import "UserSettings.h"

#import "ThreemaFramework/ThreemaFramework-swift.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
static const DDLogLevel ddLogLevel = DDLogLevelNotice;
#endif

@implementation ValidationLogger

+ (ValidationLogger*)sharedValidationLogger {
    static ValidationLogger *instance;
	
	@synchronized (self) {
		if (!instance)
			instance = [ValidationLogger alloc];
	}
	
	return instance;
}

- (void)logBoxedMessage:(BoxedMessage*)boxedMessage isIncoming:(BOOL)incoming description:(NSString *)description {
    if (![UserSettings sharedUserSettings].validationLogging)
        return;

    DDLogNotice(@"%@ message ID %@ from %@ to %@:\nDate: %@\nDescription: %@",
                incoming ? @"Incoming" : @"Outgoing",
                [NSString stringWithHexData:boxedMessage.messageId],
                boxedMessage.fromIdentity,
                boxedMessage.toIdentity,
                [DateFormatter shortStyleDateTimeSeconds:boxedMessage.date],
                description ? description : @"");
}

- (void)logSimpleMessage:(AbstractMessage*)message isIncoming:(BOOL)incoming description:(NSString *)description {
    if (![UserSettings sharedUserSettings].validationLogging)
        return;
    
    if (message.type == MSGTYPE_TYPING_INDICATOR)
        return;
    
    NSString *logmsg = @"";
    NSError *error;
    NSDictionary *json;
    NSArray *receiptMessageIds;
    __block NSMutableString *messageIds = [NSMutableString new];
    
    NSString *typeText = @"Unknown";
    switch (message.type) {
        case MSGTYPE_TEXT:
            typeText = @"TEXT";
            break;
        case MSGTYPE_IMAGE:
            typeText = @"IMAGE";
            break;
        case MSGTYPE_LOCATION:
            typeText = @"LOCATION";
            break;
        case MSGTYPE_VIDEO:
            typeText = @"VIDEO";
            break;
        case MSGTYPE_AUDIO:
            typeText = @"AUDIO";
            break;
        case MSGTYPE_BALLOT_CREATE:
            typeText = @"BALLOT_CREATE";
            break;
        case MSGTYPE_BALLOT_VOTE:
            typeText = @"BALLOT_VOTE";
            break;
        case MSGTYPE_CONTACT_SET_PHOTO:
            typeText = @"SET_PHOTO";
            break;
        case MSGTYPE_CONTACT_DELETE_PHOTO:
            typeText = @"DELETE_PHOTO";
            break;
        case MSGTYPE_CONTACT_REQUEST_PHOTO:
            typeText = @"REQUEST_PHOTO";
            break;
        case MSGTYPE_FILE:
            typeText = @"FILE";
            break;
        case MSGTYPE_GROUP_TEXT:
            typeText = @"GROUP_TEXT";
            break;
        case MSGTYPE_GROUP_LOCATION:
            typeText = @"GROUP_LOCATION";
            break;
        case MSGTYPE_GROUP_IMAGE:
            typeText = @"GROUP_IMAGE";
            break;
        case MSGTYPE_GROUP_VIDEO:
            typeText = @"GROUP_VIDEO";
            break;
        case MSGTYPE_GROUP_AUDIO:
            typeText = @"GROUP_AUDIO";
            break;
        case MSGTYPE_GROUP_FILE:
            typeText = @"GROUP_FILE";
            break;
        case MSGTYPE_GROUP_CREATE:
            typeText = @"GROUP_CREATE";
            break;
        case MSGTYPE_GROUP_RENAME:
            typeText = @"GROUP_RENAME";
            break;
        case MSGTYPE_GROUP_LEAVE:
            typeText = @"GROUP_LEAVE";
            break;
        case MSGTYPE_GROUP_SET_PHOTO:
            typeText = @"GROUP_SET_PHOTO";
            break;
        case MSGTYPE_GROUP_DELETE_PHOTO:
            typeText = @"GROUP_DELETE_PHOTO";
            break;
        case MSGTYPE_GROUP_REQUEST_SYNC:
            typeText = @"GROUP_REQUEST_SYNC";
            break;
        case MSGTYPE_GROUP_BALLOT_CREATE:
            typeText = @"GROUP_BALLOT_CREATE";
            break;
        case MSGTYPE_GROUP_BALLOT_VOTE:
            typeText = @"GROUP_BALLOT_VOTE";
            break;
        case MSGTYPE_VOIP_CALL_OFFER:
            typeText = @"CALL_OFFER";
            json = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:((BoxVoIPCallOfferMessage *)message).jsonData options:0 error:&error];
            if (json == nil) {
                return;
            }
            logmsg = [NSString stringWithFormat:@"Offer:\n%@\nDescription: %@",
                      json,
                      description];
            break;
        case MSGTYPE_VOIP_CALL_ANSWER:
            typeText = @"CALL_ANSWER";
            json = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:((BoxVoIPCallAnswerMessage *)message).jsonData options:0 error:&error];
            if (json == nil) {
                return;
            }
            logmsg = [NSString stringWithFormat:@"Answer:\n%@\nDescription: %@",
                      json,
                      description];
            break;
        case MSGTYPE_VOIP_CALL_ICECANDIDATE:
            typeText = @"CALL_ICECANDIDATE";
            json = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:((BoxVoIPCallIceCandidatesMessage *)message).jsonData options:0 error:&error];
            if (json == nil) {
                return;
            }
            logmsg = [NSString stringWithFormat:@"Candidates:\n%@\nDescription: %@",
                      json,
                      description];
            break;
        case MSGTYPE_VOIP_CALL_HANGUP:
            typeText = @"CALL_HANGUP";
            break;
        case MSGTYPE_VOIP_CALL_RINGING:
            typeText = @"CALL_RINGING";
            break;
        case MSGTYPE_DELIVERY_RECEIPT:
            typeText = @"DELIVERY_RECEIPT";
            receiptMessageIds = ((DeliveryReceiptMessage *)message).receiptMessageIds;
            [receiptMessageIds enumerateObjectsUsingBlock:^(NSData *messageId, NSUInteger idx, BOOL * _Nonnull stop) {
                if (messageIds.length > 0) {
                    [messageIds appendString:@", "];
                }
                [messageIds appendString:[NSString stringWithHexData:messageId]];
            }];
            
            logmsg = [NSString stringWithFormat:@"ReceiptMessageIds: %@",
                      messageIds
                      ];
            break;
        case MSGTYPE_TYPING_INDICATOR:
            typeText = @"TYPING_INDICATOR";
            break;
        case MSGTYPE_FORWARD_SECURITY:
            typeText = @"FORWARD_SECURITY";
            break;
        case MSGTYPE_AUTH_TOKEN:
            typeText = @"AUTH_TOKEN:";
            break;
        case MSGTYPE_GROUP_CALL_START:
            typeText = @"GROUP_CALL_START:";
            break;
        case MSGTYPE_EDIT:
            typeText = @"MSGTYPE_EDIT:";
            break;
        case MSGTYPE_GROUP_EDIT:
            typeText = @"MSGTYPE_GROUP_EDIT:";
            break;
        case MSGTYPE_DELETE:
            typeText = @"MSGTYPE_DELETE:";
            break;
        case MSGTYPE_GROUP_DELETE:
            typeText = @"MSGTYPE_GROUP_DELETE:";
            break;
        case MSGTYPE_REACTION:
            typeText = @"MSGTYPE_REACTION:";
            break;
        case MSGTYPE_GROUP_REACTION:
            typeText = @"MSGTYPE_GROUP_REACTION:";
            break;
        default:
            break;
    }
    
    // Prepend generic message header information
    DDLogNotice(@"%@ %@ message ID %@ from %@ to %@\nDate: %@%@%@",
              incoming ? @"Incoming" : @"Outgoing",
              typeText,
              [NSString stringWithHexData:message.messageId],
              message.fromIdentity,
              message.toIdentity,
              [DateFormatter shortStyleDateTimeSeconds:message.date],
              logmsg.length > 0 ? @"\n" : @"",
              logmsg);
}

- (void)logString:(NSString *)logMessage {
    if ([UserSettings sharedUserSettings].validationLogging) {
        DDLogNotice(@"%@", logMessage);
    }
}

@end
