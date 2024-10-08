//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2013-2023 Threema GmbH
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
#import <CoreData/CoreData.h>
#import "BaseMessage.h"


enum {
    kSystemMessageRenameGroup = 1, // The admin has renamed the group
    kSystemMessageGroupMemberLeave = 2, // Another member has left the group
    kSystemMessageGroupMemberAdd = 3, // The admin has added a member to the group
    kSystemMessageGroupMemberForcedLeave = 4, // Another member was removed from the group
    kSystemMessageGroupSelfAdded = 5, // I was added to the group
    kSystemMessageGroupSelfRemoved = 6, // I was removed from the group
    kSystemMessageGroupSelfLeft = 16, // I have left the group
    kSystemMessageGroupCreatorLeft = 19, // Creator has left the group
    kSystemMessageStartNoteGroupInfo = 17, // This is a note group without members
    kSystemMessageEndNoteGroupInfo = 18, // This is no note group anymore
    kSystemMessageVote = 20,
    kSystemMessageVoteUpdated = 30,
    kSystemMessageCallMissed = 7,
    kSystemMessageCallRejected = 8,
    kSystemMessageCallRejectedBusy = 9,
    kSystemMessageCallRejectedTimeout = 10,
    kSystemMessageCallEnded = 11,
    kSystemMessageCallRejectedDisabled = 12,
    kSystemMessageCallRejectedUnknown = 13,
    kSystemMessageContactOtherAppInfo = 14,
    kSystemMessageCallRejectedOffHours = 15,
    kSystemMessageFsMessageWithoutForwardSecurity = 21,
    kSystemMessageFsSessionEstablished = 22,
    kSystemMessageFsSessionEstablishedRcvd = 23, // As of version 1.1. this status is not created anymore
    kSystemMessageFsMessagesSkipped = 24,
    kSystemMessageFsSessionReset = 25,
    kSystemMessageFsOutOfOrder = 26,
    kSystemMessageFsEnabledOutgoing = 27,
    kSystemMessageFsDisabledOutgoing = 28,
    kSystemMessageFsNotSupportedAnymore = 29,
    kSystemMessageUnsupportedType = 31,
    kSystemMessageGroupProfilePictureChanged = 32,
    kSystemMessageGroupCallStartedBy = 33,
    kSystemMessageGroupCallStarted = 34,
    kSystemMessageGroupCallEnded = 35,
    kFsDebugMessage = 36,
    kSystemMessageFsIllegalSessionState = 37,
};

@interface SystemMessage : BaseMessage

@property (nonatomic, retain) NSNumber * type DEPRECATED_MSG_ATTRIBUTE("Only use from Objective-C. Use systemMessageType otherwise.");
@property (nonatomic, retain) NSData * arg;

- (NSString*)format DEPRECATED_MSG_ATTRIBUTE("Only use from Objective-C. Use systemMessageType.text otherwise.");
- (NSString *)callDetail DEPRECATED_MSG_ATTRIBUTE("Only use from Objective-C. Use systemMessageType.duration otherwise.");
- (BOOL)isCallType DEPRECATED_MSG_ATTRIBUTE("Use systemMessageType instead.");
- (BOOL)haveCallTime;
- (NSString *)callTime;
- (NSString *)argAsUTF8String;
- (NSDictionary *)argAsDictionary;

@end
