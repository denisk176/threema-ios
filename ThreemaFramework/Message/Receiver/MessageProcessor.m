//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2023 Threema GmbH
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

#import <CoreData/CoreData.h>
#import "MessageProcessor.h"
#import "MessageDecoder.h"
#import "BoxTextMessage.h"
#import "BoxImageMessage.h"
#import "BoxVideoMessage.h"
#import "BoxLocationMessage.h"
#import "BoxAudioMessage.h"
#import "BoxedMessage.h"
#import "BoxVoIPCallOfferMessage.h"
#import "BoxVoIPCallAnswerMessage.h"
#import "DeliveryReceiptMessage.h"
#import "TypingIndicatorMessage.h"
#import "GroupCreateMessage.h"
#import "GroupLeaveMessage.h"
#import "GroupRenameMessage.h"
#import "GroupTextMessage.h"
#import "GroupLocationMessage.h"
#import "GroupVideoMessage.h"
#import "GroupImageMessage.h"
#import "GroupAudioMessage.h"
#import "GroupSetPhotoMessage.h"
#import "BoxFileMessage.h"
#import "GroupFileMessage.h"
#import "ContactSetPhotoMessage.h"
#import "ContactDeletePhotoMessage.h"
#import "ContactRequestPhotoMessage.h"
#import "GroupDeletePhotoMessage.h"
#import "UnknownTypeMessage.h"
#import "ContactEntity.h"
#import "ContactStore.h"
#import "ThreemaUtilityObjC.h"
#import "ProtocolDefines.h"
#import "UserSettings.h"
#import "MyIdentityStore.h"
#import "ValidationLogger.h"
#import "BallotMessageDecoder.h"
#import "GroupMessageProcessor.h"
#import "ThreemaError.h"
#import "DatabaseManager.h"
#import "FileMessageDecoder.h"
#import "UTIConverter.h"
#import "BoxVoIPCallIceCandidatesMessage.h"
#import "BoxVoIPCallHangupMessage.h"
#import "BoxVoIPCallRingingMessage.h"
#import "NonceHasher.h"
#import "ServerConnector.h"
#import "ThreemaFramework/ThreemaFramework-Swift.h"
#import "NSString+Hex.h"
#import "NaClCrypto.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelNotice;
#endif

@implementation MessageProcessor {
    id<MessageProcessorDelegate> messageProcessorDelegate;
    int maxBytesToDecrypt;
    int timeoutDownloadThumbnail;
    GroupManager *groupManager;
    EntityManager *entityManager;
    ForwardSecurityMessageProcessor *fsmp;
    id<NonceGuardProtocolObjc> nonceGuard;
}

- (instancetype)initWith:(id<MessageProcessorDelegate>)messageProcessorDelegate groupManager:(NSObject *)groupManagerObject entityManager:(NSObject *)entityManagerObject fsmp:(NSObject*)fsmp nonceGuard:(NSObject*)nonceGuardObject {
    NSAssert([groupManagerObject isKindOfClass:[GroupManager class]], @"Object must be type of GroupManager");
    NSAssert([entityManagerObject isKindOfClass:[EntityManager class]], @"Object must be type of EntityManager");
    NSAssert([fsmp isKindOfClass:[ForwardSecurityMessageProcessor class]], @"Object must be type of ForwardSecurityMessageProcessor");
    NSAssert([nonceGuardObject conformsToProtocol:@protocol(NonceGuardProtocolObjc)], @"Object must implement NonceGuardProtocolObjc");

    self = [super init];
    if (self) {
        self->messageProcessorDelegate = messageProcessorDelegate;
        self->maxBytesToDecrypt = 0;
        self->timeoutDownloadThumbnail = 0;
        self->groupManager = (GroupManager*)groupManagerObject;
        self->entityManager = (EntityManager*)entityManagerObject;
        self->fsmp = (ForwardSecurityMessageProcessor*)fsmp;
        self->nonceGuard = (id<NonceGuardProtocolObjc>)nonceGuardObject;
    }
    return self;
}

- (void)processIncomingBoxedMessage:(BoxedMessage*)boxedMessage receivedAfterInitialQueueSend:(BOOL)receivedAfterInitialQueueSend maxBytesToDecrypt:(int)maxBytesToDecrypt timeoutDownloadThumbnail:(int)timeoutDownloadThumbnail onCompletion:(nonnull void (^)(AbstractMessage * _Nullable message, id _Nullable fsMessageInfo))onCompletion onError:(nonnull void (^)(NSError * _Nonnull error, id _Nullable fsMessageInfo))onError {

    self->maxBytesToDecrypt = maxBytesToDecrypt;
    self->timeoutDownloadThumbnail = timeoutDownloadThumbnail;

    [messageProcessorDelegate beforeDecode];

    ContactAcquaintanceLevel acquaintanceLevel = boxedMessage.flags & MESSAGE_FLAG_GROUP ? ContactAcquaintanceLevelGroupOrDeleted : ContactAcquaintanceLevelDirect;

    [[ContactStore sharedContactStore] fetchPublicKeyForIdentity:boxedMessage.fromIdentity acquaintanceLevel:acquaintanceLevel entityManager:entityManager ignoreBlockUnknown:false onCompletion:^(NSData *publicKey) {
        NSAssert(!([NSThread isMainThread] == YES), @"Should not running in main thread");

        [entityManager performBlock:^{
            AbstractMessage *amsg = [MessageDecoder decodeFromBoxed:boxedMessage withPublicKey:publicKey];
            if (amsg == nil) {
                // Can't process message at this time, try it later
                [messageProcessorDelegate incomingMessageFailed:boxedMessage];
                
                onError([ThreemaError threemaError:[NSString stringWithFormat:@"Bad message format or decryption error (ID: %@)", amsg.messageId] withCode:ThreemaProtocolErrorBadMessage], nil);
                return;
            }

            if ([amsg isKindOfClass: [UnknownTypeMessage class]]) {
                // Can't process message at this time, try it later
                // Note: We don't get here for `UnknownTypeMessage`s encapsulated in an FS message
                [messageProcessorDelegate incomingMessageFailed:boxedMessage];
                onError([ThreemaError threemaError:[NSString stringWithFormat:@"Unknown message type (ID: %@)", amsg.messageId] withCode:ThreemaProtocolErrorUnknownMessageType], nil);
                return;
            }

            /* blacklisted? */
            if ([self isBlacklisted:amsg]) {
                DDLogWarn(@"Ignoring message from blocked ID %@", boxedMessage.fromIdentity);

                // Do not process message, send server ack
                [messageProcessorDelegate incomingMessageFailed:boxedMessage];
                onCompletion(nil, nil);
                return;
            }

            // Validation logging
            if ([amsg isContentValid] == NO) {
                NSString *errorDescription = @"Ignore invalid content";
                if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                    [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxedMessage isIncoming:YES description:errorDescription];
                } else {
                    [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:errorDescription];
                }

                // Do not process message, send server ack
                [messageProcessorDelegate incomingMessageFailed:boxedMessage];
                onCompletion(nil, nil);
                return;
            } else {
                if ([nonceGuard isProcessedWithMessage:amsg]) {
                    NSString *errorDescription = @"Nonce already in database";
                    if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                        [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxedMessage isIncoming:YES description:errorDescription];
                    } else {
                        [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:errorDescription];
                    }

                    // Do not process message, send server ack
                    [messageProcessorDelegate incomingMessageFailed:boxedMessage];
                    onCompletion(nil, nil);
                    return;
                } else {
                    if ([amsg isKindOfClass:[BoxTextMessage class]] || [amsg isKindOfClass:[GroupTextMessage class]]) {
                        [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxedMessage isIncoming:YES description:nil];
                    } else {
                        [[ValidationLogger sharedValidationLogger] logSimpleMessage:amsg isIncoming:YES description:nil];
                    }
                }
            }

            amsg.receivedAfterInitialQueueSend = receivedAfterInitialQueueSend;

            [self processIncomingAbstractMessage:amsg onCompletion:^(AbstractMessage *processedMsg, id fsMessageInfo) {
                // Message successfully processed
                onCompletion(processedMsg, fsMessageInfo);
            } onError:^(NSError * _Nullable error,  id _Nullable fsMessageInfo) {
                if (error) {
                    onError(error, fsMessageInfo);
                }
                else {
                    onCompletion(nil, nil);
                }
            }];
        }];
    } onError:^(NSError *error) {
        [[ValidationLogger sharedValidationLogger] logBoxedMessage:boxedMessage isIncoming:YES description:@"PublicKey from Threema-ID not found"];
        // Failed to process message, try it later
        onError(error, nil);
    }];
}

- (void)processIncomingAbstractMessage:(AbstractMessage*)amsg onCompletion:(void(^)(AbstractMessage * _Nullable message, id _Nullable fsMessageInfo))onCompletion onError:(void(^)(NSError * _Nullable error, id _Nullable fsMessageInfo))onError {
    
    if ([amsg isContentValid] == NO) {
        DDLogInfo(@"Ignore invalid content, message ID %@ from %@", amsg.messageId, amsg.fromIdentity);
        onCompletion(nil, nil);
        return;
    }
    
    if ([nonceGuard isProcessedWithMessage:amsg]) {
        DDLogWarn(@"Nonce of message %@ already processed", amsg.loggingDescription);
        onCompletion(nil, nil);
        return;
    }
    
    /* Find contact for message */
    __block NSData *senderPublicKey;
    __block NSError *fetchContactError;
    [entityManager performBlockAndWait:^{
        ContactEntity *contact = [entityManager.entityFetcher contactForId: amsg.fromIdentity];
        if (contact) {
            senderPublicKey = contact.publicKey;
        }
        else {
            /* This should never happen, as without an entry in the contacts database, we wouldn't have
             been able to decrypt this message in the first place (no sender public key) */
            DDLogWarn(@"Identity %@ not in local contacts database - cannot process message", amsg.fromIdentity);
            fetchContactError = [ThreemaError threemaError:[NSString stringWithFormat:@"Identity %@ not in local contacts database - cannot process message", amsg.fromIdentity]];
        }
    }];

    if (fetchContactError) {
        onError(fetchContactError, nil);
        return;
    }

    // Note: This is an variable holding a block called after the PFS envelope is removed if there is any
    void(^processAbstractMessageBlock)(AbstractMessage *, id) = ^void(AbstractMessage *amsg, id fsMessageInfo) {
        [messageProcessorDelegate incomingMessageStarted:amsg];
        DDLogVerbose(@"Process incoming message: %@", amsg);

        /* Update public nickname in contact, if necessary */
        if (amsg.allowSendingProfile == YES) {
            [[ContactStore sharedContactStore] updateNickname:amsg.fromIdentity nickname:amsg.pushFromName];
        }
        
        // Process Group Messages
        if ([amsg isKindOfClass:[AbstractGroupMessage class]]) {
            [self processIncomingGroupMessage:(AbstractGroupMessage *)amsg onCompletion:^{
                if (![amsg isKindOfClass:[ForwardSecurityEnvelopeMessage class]]) {
                    if (amsg.forwardSecurityMode == kForwardSecurityModeNone) {
                        ForwardSecurityContact *fsContact = [[ForwardSecurityContact alloc] initWithIdentity:amsg.fromIdentity publicKey:senderPublicKey];
                        // Only warns if FS is required for this message
                        [fsmp warnIfMessageWithoutForwardSecurityReceivedFor:amsg from:fsContact];
                    }
                }
                
                [messageProcessorDelegate incomingMessageFinished:amsg];
                onCompletion(amsg, fsMessageInfo);
            } onError:^(NSError *error) {
                [messageProcessorDelegate incomingMessageFinished:amsg];
                onError(error, fsMessageInfo);
            }];
        // Process Non-Group Messages
        } else {
            [self processIncomingMessage:(AbstractMessage *)amsg onCompletion:^(id<MessageProcessorDelegate> _Nullable delegate) {
                if (![amsg isKindOfClass:[ForwardSecurityEnvelopeMessage class]]) {
                    if (amsg.forwardSecurityMode == kForwardSecurityModeNone) {
                        ForwardSecurityContact *fsContact = [[ForwardSecurityContact alloc] initWithIdentity:amsg.fromIdentity publicKey:senderPublicKey];
                        // Only warns if FS is required for this message
                        [fsmp warnIfMessageWithoutForwardSecurityReceivedFor:amsg from:fsContact];
                    }
                }
                
                if (delegate) {
                    [delegate incomingMessageFinished:amsg];
                }
                else {
                    [messageProcessorDelegate incomingMessageFinished:amsg];
                }
                onCompletion(amsg, fsMessageInfo);
            } onError:^(NSError *error) {
                [messageProcessorDelegate incomingMessageFinished:amsg];
                onError(error, fsMessageInfo);
            }];
        }
    };
    
    @try {
        if ([amsg isKindOfClass:[ForwardSecurityEnvelopeMessage class]]) {
            if ([ThreemaEnvironment supportsForwardSecurity]) {
                [self processIncomingForwardSecurityMessage:(ForwardSecurityEnvelopeMessage*)amsg senderPublicKey:senderPublicKey onCompletion:^(AbstractMessage *unwrappedMessage, id fsMessageInfo) {

                    if (unwrappedMessage != nil) {
                        // Don't allow double encapsulated forward security messages
                        // This is also checked when decoding messages in MessageDecoder+Swift.swift lines 41ff
                        if ([unwrappedMessage isKindOfClass:[ForwardSecurityEnvelopeMessage class]]) {
                            [messageProcessorDelegate incomingAbstractMessageFailed:amsg]; // Remove notification
                            onError(nil, fsMessageInfo);
                        } else {
                            // Happy path for normal messages
                            processAbstractMessageBlock(unwrappedMessage, fsMessageInfo);
                        }
                    } else {
                        // An auxiliary FS message was successfully processed or a message was rejected
                        // Mark contact and conversation as dirty & remove notification
                        [messageProcessorDelegate incomingForwardSecurityMessageWithNoResultFinished:amsg];
                        onError(nil, fsMessageInfo); // Drop message
                    }
                } onError:^(NSError *error) {
                    if ([error.userInfo objectForKey:@"ShouldRetry"]) {
                        [messageProcessorDelegate incomingMessageFinished:amsg];
                        onError(error, nil);
                    } else {
                        [messageProcessorDelegate incomingAbstractMessageFailed:amsg]; // Remove notification
                        onError(nil, nil); // drop message
                    }
                }];
            } else {
                // No FS support - reject message
                ForwardSecurityContact *fsContact = [[ForwardSecurityContact alloc] initWithIdentity:amsg.fromIdentity publicKey:senderPublicKey];
                [fsmp rejectEnvelopeMessageWithSender:fsContact envelopeMessage:(ForwardSecurityEnvelopeMessage*)amsg];
                [messageProcessorDelegate incomingAbstractMessageFailed:amsg]; // Remove notification
                onError(nil, nil); // drop message
            }
        } else  {
            processAbstractMessageBlock(amsg, nil);
        }
    } @catch (NSException *exception) {
        NSError *error = [ThreemaError threemaError:exception.description withCode:ThreemaProtocolErrorMessageProcessingFailed];
        onError(error, nil);
    } @catch (NSError *error) {
        onError(error, nil);
    }
}

/**
Process incoming message.

@param amsg: Incoming Abstract Message
@param onCompletion: Completion handler with MessageProcessorDelegate, use it when calling MessageProcessorDelegate in completion block of processVoIPCall, to prevent blocking of dispatch queue 'ServerConnector.registerMessageProcessorDelegateQueue')
@param onError: Error handler
*/
- (void)processIncomingMessage:(AbstractMessage*)amsg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError *err))onError {

    ContactEntity *sender;
    ContactEntity *receiver;
    __block ConversationEntity *conversation = [entityManager existingConversationSenderReceiverFor:amsg sender:&sender receiver:&receiver];

    if (sender == nil) {
        onError([ThreemaError threemaError:@"Sender not found as contact"]);
        return;
    }

    if (conversation == nil) {
        [entityManager performSyncBlockAndSafe:^{
            conversation = [entityManager conversationForContact:sender createIfNotExisting:[amsg canCreateConversation]];
        }];
    }
    
    // Set the contact to active if we received a message
    // Automatic sync is only once a day
    [entityManager performBlockAndWait:^{
        if (sender.state.intValue == kStateInactive) {
            [[ContactStore sharedContactStore] updateStateToActiveFor:sender entityManager:entityManager];
        }
    }];

    if ([amsg needsConversation] && conversation == nil) {
        onCompletion(nil);
        return;
    }

    if ([amsg isKindOfClass:[BoxTextMessage class]]) {
        [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxImageMessage class]]) {
        [self processIncomingImageMessage:(BoxImageMessage *)amsg sender:sender conversation:conversation onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxVideoMessage class]]) {
        [self processIncomingVideoMessage:(BoxVideoMessage*)amsg sender:sender conversation:conversation onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxLocationMessage class]]) {
        [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
            LocationMessageEntity *locationMessage = (LocationMessageEntity *)message;
            [self finalizeMessage:locationMessage inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                [self resolveAddressFor:locationMessage onCompletion:^{
                    onCompletion(nil);
                }];
            }];
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxAudioMessage class]]) {
        [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        } onError:onError];
    } else if ([amsg isKindOfClass:[DeliveryReceiptMessage class]]) {
        [self processIncomingDeliveryReceipt:(DeliveryReceiptMessage*)amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[TypingIndicatorMessage class]]) {
        [self processIncomingTypingIndicator:(TypingIndicatorMessage*)amsg];
        onCompletion(nil);
    } else if ([amsg isKindOfClass:[BoxBallotCreateMessage class]]) {
        BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
        [decoder decodeCreateBallotFromBox:(BoxBallotCreateMessage *)amsg sender:sender conversation:conversation onCompletion:^(BallotMessage *message) {
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        } onError:^(NSError *error) {
            onError(error);
        }];
    } else if ([amsg isKindOfClass:[BoxBallotVoteMessage class]]) {
        // TODO: This could be generate duplicate system messages, if message will processed multiple (race condition)
        [self processIncomingBallotVoteMessage:(BoxBallotVoteMessage*)amsg onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[BoxFileMessage class]]) {
        [FileMessageDecoder decodeMessageFromBox:(BoxFileMessage *)amsg sender:sender conversation:conversation isReflectedMessage:NO timeoutDownloadThumbnail:timeoutDownloadThumbnail entityManager:entityManager onCompletion:^(BaseMessage *message) {
            // Do not download blob when message will processed via Notification Extension,
            // to keep notifications fast and because option automatically save to photos gallery
            // doesn't work from Notification Extension
            if ([AppGroup getCurrentType] != AppGroupTypeNotificationExtension) {
                [self conditionallyStartLoadingFileFromMessage:(FileMessageEntity *)message];
            }
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        } onError:onError];
    } else if ([amsg isKindOfClass:[ContactSetPhotoMessage class]]) {
        [self processIncomingContactSetPhotoMessage:(ContactSetPhotoMessage *)amsg onCompletion:^{
            onCompletion(nil);
        } onError:onError];
    } else if ([amsg isKindOfClass:[ContactDeletePhotoMessage class]]) {
        [self processIncomingContactDeletePhotoMessage:(ContactDeletePhotoMessage *)amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[ContactRequestPhotoMessage class]]) {
        [self processIncomingContactRequestPhotoMessage:(ContactRequestPhotoMessage *)amsg onCompletion:^{
            onCompletion(nil);
        }];
    } else if ([amsg isKindOfClass:[BoxVoIPCallOfferMessage class]]) {
        [self processIncomingVoIPCallOfferMessage:(BoxVoIPCallOfferMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallAnswerMessage class]]) {
        [self processIncomingVoIPCallAnswerMessage:(BoxVoIPCallAnswerMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallIceCandidatesMessage class]]) {
        [self processIncomingVoIPCallIceCandidatesMessage:(BoxVoIPCallIceCandidatesMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallHangupMessage class]]) {
        [self processIncomingVoIPCallHangupMessage:(BoxVoIPCallHangupMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxVoIPCallRingingMessage class]]) {
        [self processIncomingVoipCallRingingMessage:(BoxVoIPCallRingingMessage *)amsg onCompletion:onCompletion onError:onError];
    } else if ([amsg isKindOfClass:[BoxEmptyMessage class]]) {
        // Noting todo. Just move on...
        // Android basically handles it the same way as an `UnknownTypeMessage`. On iOS this is too complicated for now.
        onCompletion(nil);
    } else if ([amsg isKindOfClass:[UnknownTypeMessage class]]) {
        onError([ThreemaError threemaError:[NSString stringWithFormat:@"Unknown message type (ID: %@)", amsg.messageId] withCode:ThreemaProtocolErrorUnknownMessageType]);
    } else if ([amsg isKindOfClass:[DeleteMessage class]]) {
        // On error case `onError` will be called and message is `nil`
        BaseMessage *message = [entityManager deleteMessageFor:amsg conversation:conversation onError:onError];
        if (message) {
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        }
    } else if ([amsg isKindOfClass:[EditMessage class]]) {
        // On error case `onError` will be called and message is `nil`
        BaseMessage *message = [entityManager editMessageFor:amsg conversation:conversation onError:onError];
        if (message) {
            [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:^{
                onCompletion(nil);
            }];
        }
    }
    else {
        // Do not Ack message, try process this message later because of protocol changes
        onError([ThreemaError threemaError:@"Invalid message class"]);
    }
}

- (void)processIncomingGroupMessage:(AbstractGroupMessage * _Nonnull)amsg onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    
    GroupMessageProcessor *groupProcessor = [[GroupMessageProcessor alloc] initWithMessage:amsg myIdentityStore:[MyIdentityStore sharedMyIdentityStore] userSettings:[UserSettings sharedUserSettings] groupManager:groupManager entityManager:entityManager nonceGuard:(NSObject*)nonceGuard];
    [groupProcessor handleMessageOnCompletion:^(BOOL didHandleMessage) {
        if (didHandleMessage) {
            onCompletion();
            return;
        }

        // messages not handled by GroupProcessor, e.g. messages that can be processed after delayed group create
        ContactEntity *sender;
        ContactEntity *receiver;
        ConversationEntity *conversation = [entityManager existingConversationSenderReceiverFor:amsg sender:&sender receiver:&receiver];

        if (sender == nil) {
            onError([ThreemaError threemaError:@"Sender not found as contact"]);
            return;
        }

        // Conversation must be there at this time, should be created with creation of the group
        if (conversation == nil) {
            onCompletion();
            return;
        }
        
        // Set the contact to active if we received a message
        // Automatic sync is only once a day
        [entityManager performBlockAndWait:^{
            if (sender.state.intValue == kStateInactive) {
                [[ContactStore sharedContactStore] updateStateToActiveFor:sender entityManager:entityManager];
            }
        }];

        if ([amsg isKindOfClass:[GroupRenameMessage class]]) {
            [groupManager setNameObjcWithGroupID:amsg.groupId creator:amsg.groupCreator name:((GroupRenameMessage *)amsg).name systemMessageDate:amsg.date send:YES completionHandler:^(NSError * _Nullable error) {
                if (error == nil) {
                    [self changedConversationAndGroupEntityWithGroupID:amsg.groupId groupCreatorIdentity:amsg.groupCreator];
                    onCompletion();
                }
                else {
                    onError(error);
                }
            }];
        } else if ([amsg isKindOfClass:[GroupSetPhotoMessage class]]) {
            [self processIncomingGroupSetPhotoMessage:(GroupSetPhotoMessage*)amsg onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupDeletePhotoMessage class]]) {
            [groupManager deletePhotoObjcWithGroupID:amsg.groupId creator:amsg.groupCreator sentDate:[amsg date] send:NO completionHandler:^(NSError * _Nullable error) {
                if (error == nil) {
                    [self changedConversationAndGroupEntityWithGroupID:amsg.groupId groupCreatorIdentity:amsg.groupCreator];
                    onCompletion();
                }
                else {
                    onError(error);
                }
            }];
        } else if ([amsg isKindOfClass:[GroupTextMessage class]]) {
            BOOL isMessageAlreadyProcessed = NO;
            [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
                [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
            } onError:onError];
        } else if ([amsg isKindOfClass:[GroupLocationMessage class]]) {
            [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
                [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:^{
                    [self resolveAddressFor:(LocationMessageEntity*)message onCompletion:onCompletion];
                }];
            } onError:onError];
        } else if ([amsg isKindOfClass:[GroupImageMessage class]]) {
            [self processIncomingImageMessage:(GroupImageMessage *)amsg sender:sender conversation:conversation onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupVideoMessage class]]) {
            [self processIncomingVideoMessage:(GroupVideoMessage*)amsg sender:sender conversation:conversation onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupAudioMessage class]]) {
            [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
                [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
            } onError:onError];
        } else if ([amsg isKindOfClass:[GroupBallotCreateMessage class]]) {
            BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
            [decoder decodeCreateBallotFromGroupBox:(GroupBallotCreateMessage *)amsg sender:sender conversation:conversation onCompletion:^(BallotMessage *message) {
                [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
            } onError:^(NSError *error) {
                onError(error);
            }];
        } else if ([amsg isKindOfClass:[GroupBallotVoteMessage class]]) {
            // TODO: This could be generate duplicate system messages, if message will processed multiple (race condition)
            [self processIncomingGroupBallotVoteMessage:(GroupBallotVoteMessage*)amsg onCompletion:onCompletion onError:onError];
        } else if ([amsg isKindOfClass:[GroupFileMessage class]]) {
            [FileMessageDecoder decodeGroupMessageFromBox:(GroupFileMessage *)amsg sender:sender conversation:conversation isReflectedMessage:NO timeoutDownloadThumbnail:timeoutDownloadThumbnail entityManager:entityManager onCompletion:^(BaseMessage *message) {
                [self finalizeGroupMessage:message inConversation:conversation fromBoxMessage:amsg sender:sender onCompletion:onCompletion];
            } onError:^(NSError *error) {
                onError(error);
            }];
        } else if ([amsg isKindOfClass:[GroupDeliveryReceiptMessage class]]) {
            [self processIncomingGroupDeliveryReceipt:(GroupDeliveryReceiptMessage*)amsg onCompletion:onCompletion];
        } else if ([amsg isKindOfClass:[GroupCallStartMessage class]]) {
            GroupCallStartMessage *newMsg = (GroupCallStartMessage *) amsg;
            [[GlobalGroupCallManagerSingleton shared] handleMessageWithRawMessage:newMsg.decodedObj from:newMsg.fromIdentity in:conversation.objectID receiveDate:newMsg.date completionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    DDLogNotice(@"[GroupCall] [DB] Completion handler called");
                    onCompletion();
                });
            }];
        } else if ([amsg isKindOfClass:[DeleteGroupMessage class]]) {
            // On error case `onError` will be called and message is `nil`
            BaseMessage *message = [entityManager deleteMessageFor:amsg conversation:conversation onError:onError];
            if (message) {
                [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:onCompletion];
            }
        } else if ([amsg isKindOfClass:[EditGroupMessage class]]) {
            // On error case `onError` will be called and message is `nil`
            BaseMessage *message = [entityManager editMessageFor:amsg conversation:conversation onError:onError];
            if (message) {
                [self finalizeMessage:message inConversation:conversation fromBoxMessage:amsg onCompletion:onCompletion];
            }
        } else {
            onError([ThreemaError threemaError:@"Invalid message class"]);
        }
    } onError:^(NSError *error) {
        onError(error);
    }];
}

- (void)processIncomingForwardSecurityMessage:(ForwardSecurityEnvelopeMessage * _Nonnull)amsg senderPublicKey:(NSData*)senderPublicKey onCompletion:(void(^ _Nonnull)(AbstractMessage *unwrappedMessage, id fsMessageInfo))onCompletion onError:(void(^ _Nonnull)(NSError * error))onError {
    ForwardSecurityContact *fsContact = [[ForwardSecurityContact alloc] initWithIdentity:amsg.fromIdentity publicKey:senderPublicKey];

    [fsmp processEnvelopeMessageObjCWithSender:fsContact envelopeMessage:amsg completionHandler:^(AbstractMessageAndFSMessageInfo * _Nullable unwrappedMessageAndFSMessageInfo, NSError * _Nullable error) {
        
        if (error != nil) {
            DDLogError(@"Processing forward security message failed: %@", error);
            onError(error);
            return;
        }
        
        onCompletion(unwrappedMessageAndFSMessageInfo.message, unwrappedMessageAndFSMessageInfo.fsMessageInfo);
    }];
}

- (void)finalizeMessage:(BaseMessage*)message inConversation:(ConversationEntity*)conversation fromBoxMessage:(AbstractMessage*)boxMessage onCompletion:(void(^_Nonnull)(void))onCompletion {
    [messageProcessorDelegate incomingMessageChanged:boxMessage baseMessage:message];
    onCompletion();
}

- (void)finalizeGroupMessage:(BaseMessage*)message inConversation:(ConversationEntity*)conversation fromBoxMessage:(AbstractGroupMessage*)boxMessage sender:(ContactEntity *)sender onCompletion:(void(^_Nonnull)(void))onCompletion {
    [messageProcessorDelegate incomingMessageChanged:boxMessage baseMessage:message];
    onCompletion();
}

- (void)conditionallyStartLoadingFileFromMessage:(FileMessageEntity*)message {
    BlobManagerObjcWrapper *manager = [[BlobManagerObjcWrapper alloc] init];
    [manager autoSyncBlobsFor:message.objectID];
}

- (void)processIncomingImageMessage:(nonnull AbstractMessage *)amsg sender:(nonnull ContactEntity *)sender conversation:(nonnull ConversationEntity *)conversation onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    
    NSAssert([amsg isKindOfClass:[BoxImageMessage class]] || [amsg isKindOfClass:[GroupImageMessage class]], @"Abstract message type should be BoxImageMessage or GroupImageMessage");
    
    if ([amsg isKindOfClass:[BoxImageMessage class]] == NO && [amsg isKindOfClass:[GroupImageMessage class]] == NO) {
        onError([ThreemaError threemaError:@"Wrong message type, must be BoxImageMessage or GroupImageMessage"]);
        return;
    }

    BOOL isGroupMessage = [amsg isKindOfClass:[GroupImageMessage class]];
    [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:nil onCompletion:^(BaseMessage *message) {
        ImageMessageEntity *imageMessageEntity = (ImageMessageEntity*)message;

        [messageProcessorDelegate incomingMessageChanged:amsg baseMessage:imageMessageEntity];

        dispatch_queue_t downloadQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        // An ImageMessage never has a local blob because all note group cabable devices send everything as FileMessage
        BlobURL *blobUrl = [[BlobURL alloc] initWithServerConnector:[ServerConnector sharedServerConnector] userSettings:[UserSettings sharedUserSettings] queue:downloadQueue];
        BlobDownloader *blobDownloader = [[BlobDownloader alloc] initWithBlobURL:blobUrl queue:downloadQueue];
        ImageMessageProcessor *processor = [[ImageMessageProcessor alloc] initWithBlobDownloader:blobDownloader myIdentityStore:[MyIdentityStore sharedMyIdentityStore] userSettings:[UserSettings sharedUserSettings] entityManager:entityManager];
        [processor downloadImageWithImageMessageID:imageMessageEntity.id in:conversation.objectID imageBlobID:imageMessageEntity.imageBlobId origin:BlobOriginPublic imageBlobEncryptionKey:imageMessageEntity.encryptionKey imageBlobNonce:imageMessageEntity.imageNonce senderPublicKey:sender.publicKey maxBytesToDecrypt:self->maxBytesToDecrypt timeoutDownloadThumbnail:timeoutDownloadThumbnail completion:^(NSError *error) {

            if (error != nil) {
                DDLogError(@"Could not process image message %@", error);
            }

            if (isGroupMessage == NO) {
                [self finalizeMessage:imageMessageEntity inConversation:conversation fromBoxMessage:amsg onCompletion:onCompletion];
            }
            else {
                [self finalizeGroupMessage:imageMessageEntity inConversation:conversation fromBoxMessage:(AbstractGroupMessage *)amsg sender:sender onCompletion:onCompletion];
            }
        }];
    } onError:onError];
}

- (void)processIncomingVideoMessage:(nonnull AbstractMessage *)amsg sender:(nonnull ContactEntity *)sender conversation:(nonnull ConversationEntity *)conversation onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    
    NSAssert([amsg isKindOfClass:[BoxVideoMessage class]] || [amsg isKindOfClass:[GroupVideoMessage class]], @"Abstract message type should be BoxVideoMessage or GroupVideoMessage");
    
    if ([amsg isKindOfClass:[BoxVideoMessage class]] == NO && [amsg isKindOfClass:[GroupVideoMessage class]] == NO) {
        onError([ThreemaError threemaError:@"Wrong message type, must be BoxVideoMessage or GroupVideoMessage"]);
        return;
    }

    [entityManager getOrCreateMessageFor:amsg sender:sender conversation:conversation thumbnail:[UIImage imageNamed:@"threema.video.fill"] onCompletion:^(BaseMessage *message) {
        VideoMessageEntity *videoMessageEntity = (VideoMessageEntity *)message;

        [messageProcessorDelegate incomingMessageChanged:amsg baseMessage:videoMessageEntity];

        BOOL isGroupMessage = [amsg isKindOfClass:[GroupVideoMessage class]];

        NSData *thumbnailBlobId;
        if (isGroupMessage == NO) {
            BoxVideoMessage *videoMessage = (BoxVideoMessage *)amsg;
            thumbnailBlobId = [videoMessage thumbnailBlobId];
        }
        else {
            GroupVideoMessage *videoMessage = (GroupVideoMessage *)amsg;
            thumbnailBlobId = [videoMessage thumbnailBlobId];
        }

        dispatch_queue_t downloadQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        // A VideoMessage never has a local blob because all note group capable devices send everything as FileMessage
        BlobURL *blobUrl = [[BlobURL alloc] initWithServerConnector:[ServerConnector sharedServerConnector] userSettings:[UserSettings sharedUserSettings] queue:downloadQueue];
        BlobDownloader *blobDownloader = [[BlobDownloader alloc] initWithBlobURL:blobUrl queue:downloadQueue];
        VideoMessageProcessor *processor = [[VideoMessageProcessor alloc] initWithBlobDownloader:blobDownloader userSettings:[UserSettings sharedUserSettings] entityManager:entityManager];
        [processor downloadVideoThumbnailWithVideoMessageID:videoMessageEntity.id in:conversation.objectID thumbnailBlobID:thumbnailBlobId origin:BlobOriginPublic maxBytesToDecrypt:self->maxBytesToDecrypt timeoutDownloadThumbnail:self->timeoutDownloadThumbnail completion:^(NSError *error) {

            if (error != nil) {
                DDLogError(@"Error while downloading video thumbnail: %@", error);
            }

            if (isGroupMessage == NO) {
                [self finalizeMessage:videoMessageEntity inConversation:conversation fromBoxMessage:amsg onCompletion:onCompletion];
            }
            else {
                [self finalizeGroupMessage:videoMessageEntity inConversation:conversation fromBoxMessage:(AbstractGroupMessage *)amsg sender:sender onCompletion:onCompletion];
            }
        }];
    } onError:onError];
}

- (void)resolveAddressFor:(LocationMessageEntity*)message onCompletion:(void(^ _Nonnull)(void))onCompletion {
    // Reverse geocoding (only necessary if there is no POI adress) /
    if (message.poiAddress != nil) {
        onCompletion();
        return;
    }

    // It should not result in a different address if we initialize the location with accuracies or not
    __block CLLocation *location = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(message.latitude.doubleValue, message.longitude.doubleValue) altitude:0 horizontalAccuracy:message.accuracy.doubleValue verticalAccuracy:-1 timestamp:[NSDate date]];

    [ThreemaUtility fetchAddressObjcFor:location completionHandler:^(NSString * _Nonnull address) {
        [entityManager performAsyncBlockAndSafe:^{
            if (![message wasDeleted]) {
                message.poiAddress = address;
            }
            
            onCompletion();
        }];
    }];
}

- (void)processIncomingDeliveryReceipt:(DeliveryReceiptMessage*)msg onCompletion:(void(^ _Nonnull)(void))onCompletion {
    [entityManager performAsyncBlockAndSafe:^{
        ConversationEntity *conversation = [[entityManager entityFetcher] conversationEntityForIdentity:[msg fromIdentity]];

        for (NSData *receiptMessageId in msg.receiptMessageIds) {
            if (conversation == nil) {
                DDLogWarn(@"Cannot find conversation for message ID %@ (delivery receipt from %@)", receiptMessageId, msg.fromIdentity);
                continue;
            }

            /* Fetch message from DB */
            BaseMessage *dbmsg = [entityManager.entityFetcher ownMessageWithId: receiptMessageId conversationEntity:conversation];
            if (dbmsg == nil) {
                /* This can happen if the user deletes the message before the receipt comes in */
                DDLogError(@"Cannot find message ID %@ (delivery receipt from %@)", receiptMessageId, msg.fromIdentity);
                continue;
            }
            
            if (msg.receiptType == ReceiptTypeReceived) {
                DDLogNotice(@"Message ID %@ has been received by recipient", [NSString stringWithHexData:receiptMessageId]);
                dbmsg.deliveryDate = msg.date;
                dbmsg.delivered = [NSNumber numberWithBool:YES];
            } else if (msg.receiptType == ReceiptTypeRead) {
                DDLogNotice(@"Message ID %@ has been read by recipient", [NSString stringWithHexData:receiptMessageId]);
                if (!dbmsg.delivered)
                    dbmsg.delivered = [NSNumber numberWithBool:YES];
                dbmsg.readDate = msg.date;
                dbmsg.read = [NSNumber numberWithBool:YES];
            } else if (msg.receiptType == ReceiptTypeAck && dbmsg.deletedAt == nil) {
                DDLogNotice(@"Message ID %@ has been user acknowledged by recipient", [NSString stringWithHexData:receiptMessageId]);
                dbmsg.userackDate = msg.date;
                dbmsg.userack = [NSNumber numberWithBool:YES];
            } else if (msg.receiptType == ReceiptTypeDecline && dbmsg.deletedAt == nil) {
                DDLogNotice(@"Message ID %@ has been user declined by recipient", [NSString stringWithHexData:receiptMessageId]);
                dbmsg.userackDate = msg.date;
                dbmsg.userack = [NSNumber numberWithBool:NO];
            } else {
                DDLogWarn(@"Unknown delivery receipt type %d with message ID %@", msg.receiptType, [NSString stringWithHexData:receiptMessageId]);
            }

            [messageProcessorDelegate changedManagedObjectID:dbmsg.objectID];
        }
        
        onCompletion();
    }];
}

- (void)processIncomingGroupDeliveryReceipt:(GroupDeliveryReceiptMessage*)msg onCompletion:(void(^ _Nonnull)(void))onCompletion {
    [entityManager performAsyncBlockAndSafe:^{
        ConversationEntity *conversation = [entityManager.entityFetcher conversationEntityForGroupId:msg.groupId creator:msg.groupCreator];

        for (NSData *receiptMessageId in msg.receiptMessageIds) {
            if (conversation == nil) {
                DDLogWarn(@"Cannot find conversation for message ID %@ (group delivery receipt from %@)", receiptMessageId, msg.fromIdentity);
                continue;
            }

            /* Fetch message from DB */
            BaseMessage *dbmsg = [entityManager.entityFetcher messageWithId:receiptMessageId conversationEntity:conversation];
            if (dbmsg == nil) {
                /* This can happen if the user deletes the message before the receipt comes in */
                DDLogWarn(@"Cannot find message ID %@ (delivery receipt from %@)", receiptMessageId, msg.fromIdentity);
                continue;
            }
            
            if (msg.receiptType == ReceiptTypeAck) {
                GroupDeliveryReceipt *groupDeliveryReceipt = [[GroupDeliveryReceipt alloc] initWithIdentity:msg.fromIdentity deliveryReceiptType:DeliveryReceiptTypeAcknowledged date:msg.date];
                [dbmsg addWithGroupDeliveryReceipt:groupDeliveryReceipt];
                DDLogWarn(@"Message ID %@ has been user acknowledged by %@", [NSString stringWithHexData:receiptMessageId], msg.fromIdentity);
            }
            else if (msg.receiptType == ReceiptTypeDecline) {
                GroupDeliveryReceipt *groupDeliveryReceipt = [[GroupDeliveryReceipt alloc] initWithIdentity:msg.fromIdentity deliveryReceiptType:DeliveryReceiptTypeDeclined date:msg.date];
                [dbmsg addWithGroupDeliveryReceipt:groupDeliveryReceipt];
                DDLogWarn(@"Message ID %@ has been user declined by %@", [NSString stringWithHexData:receiptMessageId], msg.fromIdentity);
            }
            else {
                DDLogWarn(@"Unknown group delivery receipt type %d with message ID %@", msg.receiptType, [NSString stringWithHexData:receiptMessageId]);
            }
            
            [messageProcessorDelegate changedManagedObjectID:dbmsg.objectID];
        }
        
        onCompletion();
    }];
}

- (void)processIncomingTypingIndicator:(TypingIndicatorMessage*)msg {
    [messageProcessorDelegate processTypingIndicator:msg]; 
}

- (void)processIncomingGroupSetPhotoMessage:(GroupSetPhotoMessage*)msg onCompletion:(void(^)(void))onCompletion onError:(void(^)(NSError *err))onError {
    
    Group *group = [groupManager getGroup:msg.groupId creator:msg.groupCreator];
    if (group == nil) {
        DDLogInfo(@"Group ID %@ from %@ not found", msg.groupId, msg.groupCreator);
        onCompletion();
        return;
    }

    // Download profile picture blob
    [self syncLoadBlobID:msg.blobId encryptionKey:msg.encryptionKey origin:BlobOriginPublic onCompletion:^(NSData * _Nonnull imageData) {
        [groupManager setPhotoObjcWithGroupID:msg.groupId creator:msg.groupCreator imageData:imageData sentDate:msg.date send:NO completionHandler:^(NSError * _Nullable error) {
            if (error == nil) {
                [self changedConversationAndGroupEntityWithGroupID:msg.groupId groupCreatorIdentity:msg.groupCreator];
                onCompletion();
            }
            else {
                onError(error);
            }
        }];
    } onError:^(NSError *error) {
        if (error.code == 404) {
            onCompletion();
        }
        else {
            onError(error);
        }
    }];
}

- (void)processIncomingGroupBallotVoteMessage:(GroupBallotVoteMessage*)msg onCompletion:(void(^)(void))onCompletion onError:(void(^)(NSError *err))onError {
    // TODO: (IOS-4254) Remove once resolved
    DDLogInfo(@"[Ballot] Start Processing GroupBallotVoteMessage in ballot with ID: %@.", [NSString stringWithHexData:msg.ballotId]);
    /* Create Message in DB */
    BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
    
    [entityManager performAsyncBlockAndSafe:^{
        if ([decoder decodeVoteFromGroupBox: msg] == NO) {
            onError([ThreemaError threemaError:[NSString stringWithFormat: @"[Ballot] Error processing ballot vote in ballot with ID: %@.", [NSString stringWithHexData:msg.ballotId]]]);
            return;
        }

        [self changedBallotWithID:msg.ballotId];

        onCompletion();
    }];
}

- (void)processIncomingBallotVoteMessage:(BoxBallotVoteMessage*)msg onCompletion:(void(^)(void))onCompletion onError:(void(^)(NSError * _Nonnull))onError {
    // TODO: (IOS-4254) Remove once resolved
    DDLogInfo(@"[Ballot] Start Processing BoxBallotVoteMessage in ballot with ID %@.", [NSString stringWithHexData:msg.ballotId]);
    /* Create Message in DB */
    BallotMessageDecoder *decoder = [[BallotMessageDecoder alloc] initWith:entityManager];
    [entityManager performAsyncBlockAndSafe:^{
        
        if ([decoder decodeVoteFromBox: msg] == NO) {
            onError([ThreemaError threemaError:[NSString stringWithFormat: @"[Ballot] Error parsing json for ballot vote in ballot with ID: %@.", [NSString stringWithHexData:msg.ballotId]]]);
            return;
        }
                
        [self changedBallotWithID:msg.ballotId];
        
        onCompletion();
    }];
}

- (void)processIncomingContactSetPhotoMessage:(ContactSetPhotoMessage *)msg onCompletion:(void(^ _Nonnull)(void))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {

    // Download profile picture blob
    [self syncLoadBlobID:msg.blobId encryptionKey:msg.encryptionKey origin:BlobOriginPublic onCompletion:^(NSData *imageData) {
        // Update profile picture of contact
        NSError *updateProfilePictureError;
        [[ContactStore sharedContactStore] updateProfilePicture:msg.fromIdentity imageData:imageData shouldReflect:YES blobID:msg.blobId encryptionKey:msg.encryptionKey didFailWithError:&updateProfilePictureError];
        if (updateProfilePictureError) {
            onError(updateProfilePictureError);
            return;
        }

        [self changedContactWithIdentity:msg.fromIdentity];
        onCompletion();
    } onError:^(NSError *error) {
        if (error.code == 404) {
            onCompletion();
        }
        else {
            onError(error);
        }
    }];
}

- (void)processIncomingContactDeletePhotoMessage:(ContactDeletePhotoMessage *)msg onCompletion:(void(^ _Nonnull)(void))onCompletion {
    [[ContactStore sharedContactStore] deleteProfilePicture:msg.fromIdentity shouldReflect:YES];
    [self changedContactWithIdentity:msg.fromIdentity];
    onCompletion();
}

- (void)processIncomingContactRequestPhotoMessage:(ContactRequestPhotoMessage *)msg onCompletion:(void(^ _Nonnull)(void))onCompletion {
    [[ContactStore sharedContactStore] removeProfilePictureFlagForIdentity:msg.fromIdentity];
    onCompletion();
}


- (void)processIncomingVoIPCallOfferMessage:(BoxVoIPCallOfferMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    VoIPCallOfferMessage *message = [VoIPCallMessageDecoder decodeVoIPCallOfferFrom:msg];
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for voip call offer"]);
        return;
    }
    
    [messageProcessorDelegate processVoIPCall:message identity:msg.fromIdentity onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    } onError:onError];
}

- (void)processIncomingVoIPCallAnswerMessage:(BoxVoIPCallAnswerMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    VoIPCallAnswerMessage *message = [VoIPCallMessageDecoder decodeVoIPCallAnswerFrom:msg];
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for ballot vote"]);
        return;
    }

    [messageProcessorDelegate processVoIPCall:message identity:msg.fromIdentity onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    } onError:onError];
}

- (void)processIncomingVoIPCallIceCandidatesMessage:(BoxVoIPCallIceCandidatesMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    VoIPCallIceCandidatesMessage *message = [VoIPCallMessageDecoder decodeVoIPCallIceCandidatesFrom:msg];
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for ice candidates"]);
        return;
    }

    [messageProcessorDelegate processVoIPCall:message identity:msg.fromIdentity onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    } onError:onError];
}

- (void)processIncomingVoIPCallHangupMessage:(BoxVoIPCallHangupMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    VoIPCallHangupMessage *message = [VoIPCallMessageDecoder decodeVoIPCallHangupFrom:msg contactIdentity:msg.fromIdentity];
    
    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for hangup"]);
        return;
    }
    
    [messageProcessorDelegate processVoIPCall:message identity:nil onCompletion:^(id<MessageProcessorDelegate>  _Nullable delegate) {
        onCompletion(delegate);
    } onError:onError];
}

- (void)processIncomingVoipCallRingingMessage:(BoxVoIPCallRingingMessage *)msg onCompletion:(void(^ _Nonnull)(id<MessageProcessorDelegate> _Nullable delegate))onCompletion onError:(void(^ _Nonnull)(NSError * _Nonnull))onError {
    VoIPCallRingingMessage *message = [VoIPCallMessageDecoder decodeVoIPCallRingingFrom:msg contactIdentity:msg.fromIdentity];

    if (message == nil) {
        onError([ThreemaError threemaError:@"Error parsing json for ringing"]);
        return;
    }
    
    [messageProcessorDelegate processVoIPCall:message identity:nil onCompletion:^(id<MessageProcessorDelegate>  _Nonnull delegate) {
        onCompletion(delegate);
    } onError:onError];
}


#pragma private methods

/// Check is the sender in the black list. If it's a group control message and the sender is on the black list, we will process the message if the group is still active on the receiver side
/// @param amsg Decoded abstract message
- (BOOL)isBlacklisted:(AbstractMessage *)amsg {
    if ([[UserSettings sharedUserSettings].blacklist containsObject:amsg.fromIdentity]) {
        if ([amsg isKindOfClass:[AbstractGroupMessage class]]) {
            AbstractGroupMessage *groupMessage = (AbstractGroupMessage *)amsg;
            Group *group = [groupManager getGroup:groupMessage.groupId creator:groupMessage.groupCreator];
            
            // If this group is active and the message is a group control message (create, leave, requestSync, Rename, SetPhoto, DeletePhoto)
            if (group.isSelfMember && [groupMessage isGroupControlMessage]) {
                    return false;
            }
        }
        
        return true;
    }
    return false;
}

- (void)syncLoadBlobID:(NSData *)blobID encryptionKey:(NSData *)encryptionKey origin:(BlobOrigin)origin onCompletion:(void(^ _Nonnull)(NSData * _Nonnull imageData))onCompletion onError:(void(^ _Nonnull)(NSError *error))onError {
    // Download blob image
    dispatch_queue_t downloadQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    BlobURL *blobUrl = [[BlobURL alloc] initWithServerConnector:[ServerConnector sharedServerConnector] userSettings:[UserSettings sharedUserSettings] queue:downloadQueue];
    BlobDownloader *blobDownloader = [[BlobDownloader alloc] initWithBlobURL:blobUrl queue:downloadQueue];
    [blobDownloader downloadWithBlobID:blobID origin:BlobOriginPublic completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        if (error) {
            onError(error);
            return;
        }

        // Decrypt blob data
        NSData *imageData = [[NaClCrypto sharedCrypto] symmetricDecryptData:data withKey:encryptionKey nonce:[NSData dataWithBytesNoCopy:kNonce_1 length:sizeof(kNonce_1) freeWhenDone:NO]];
        if (imageData == nil) {
            onError([ThreemaError threemaError:@"Image blob decryption failed" withCode:ThreemaProtocolErrorMessageBlobDecryptionFailed]);
            return;
        }

        if ([[UserSettings sharedUserSettings] enableMultiDevice]) {
            [blobDownloader markDownloadDoneFor:blobID origin:BlobOriginLocal];
        }

        onCompletion(imageData);
    }];
}

-  (void)changedBallotWithID:(NSData * _Nonnull)ID {
    [entityManager performBlockAndWait:^{
        Ballot *ballot = [[entityManager entityFetcher] ballotForBallotId:ID];
        if (ballot) {
            [messageProcessorDelegate changedManagedObjectID:ballot.objectID];
        }
    }];
}

- (void)changedContactWithIdentity:(NSString * _Nonnull)identity {
    [entityManager performBlockAndWait:^{
        ContactEntity *contact = [entityManager.entityFetcher contactForId:identity];
        if (contact) {
            [messageProcessorDelegate changedManagedObjectID:contact.objectID];
        }
    }];
}

- (void)changedConversationAndGroupEntityWithGroupID:(NSData * _Nonnull)groupID groupCreatorIdentity:(NSString * _Nonnull)groupCreatorIdentity {
    [entityManager performBlockAndWait:^{
        ConversationEntity *conversation = [entityManager.entityFetcher conversationEntityForGroupId:groupID creator:groupCreatorIdentity];
        if (conversation) {
            [messageProcessorDelegate changedManagedObjectID:conversation.objectID];

            GroupEntity *groupEntity = [[entityManager entityFetcher] groupEntityForConversationEntity:conversation];
            if (groupEntity) {
                [messageProcessorDelegate changedManagedObjectID:groupEntity.objectID];
            }
        }
    }];
}

@end
