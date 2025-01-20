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

#import "BallotChoice.h"
#import "Ballot.h"
#import "MyIdentityStore.h"
#import "ContactEntity.h"
#import "ThreemaFramework/ThreemaFramework-Swift.h"

@class BallotResultEntity;

@implementation BallotChoice

@dynamic createDate;
@dynamic id;
@dynamic modifyDate;
@dynamic name;
@dynamic orderPosition;
@dynamic ballot;
@dynamic result;
@dynamic totalVotes;

- (BallotResultEntity *)getOwnResult {
    NSString *myId = [MyIdentityStore sharedMyIdentityStore].identity;
    return [self getResultForId: myId];
}

- (BallotResultEntity *)getResultForId:(NSString *)contactId {
    for (BallotResultEntity *result in self.result) {
        if ([result.participantId isEqualToString: contactId]) {
            return result;
        }
    }
    
    return nil;
}

- (void)removeResultForContact:(NSString *)contactId {
    NSMutableSet *matchingResults = [NSMutableSet set];
    for (BallotResultEntity *result in self.result) {
        if ([result.participantId isEqualToString: contactId]) {
            [matchingResults addObject: result];
        }
    }

    for (BallotResultEntity *result in matchingResults) {
        [self removeResultObject:result];
        [self.managedObjectContext deleteObject:result];
    }
}

- (NSInteger)totalCountOfResultsTrue {
    NSInteger count = 0;
    for (BallotResultEntity *result in self.result) {
        if (result.boolValue && [self isParticipantGroupMember:result.participantId]) {
            count++;
        }
    }
    
    return count;
}

- (NSSet*)participantIdsForResultsTrue {
    NSMutableSet *set = [NSMutableSet set];
    for (BallotResultEntity *result in self.result) {
        if (result.boolValue && [self isParticipantGroupMember:result.participantId]) {
            [set addObject:result.participantId];
        }
    }
    
    return set;
}

- (NSSet *)getAllParticipantIds {
    NSMutableSet *set = [NSMutableSet set];
    for (BallotResultEntity *result in self.result) {
        if ([self isParticipantGroupMember:result.participantId]) {
            [set addObject:result.participantId];
        }
    }
    
    return set;
}

- (BOOL)isParticipantGroupMember:(NSString *)participantId {
    NSString *myId = [MyIdentityStore sharedMyIdentityStore].identity;
    if ([myId isEqualToString:participantId]) {
        return YES;
    }
    
    for (ContactEntity *contact in self.ballot.conversation.participants) {
        if ([contact.identity isEqualToString:participantId]) {
            return YES;
        }
    }

    return NO;
}

@end
