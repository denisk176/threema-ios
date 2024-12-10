//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2023 Threema GmbH
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

#import <ThreemaFramework/TMAManagedObject.h>

@class Ballot, BallotResultEntity;

@interface BallotChoice : TMAManagedObject

// Attributes
@property (nonatomic, retain) NSDate * createDate;
@property (nonatomic, retain) NSNumber * id;
@property (nonatomic, retain) NSDate * modifyDate;
@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSNumber * orderPosition;
@property (nonatomic, retain) NSNumber *totalVotes;

// Relationships
@property (nonatomic, retain) Ballot *ballot;
@property (nonatomic, retain) NSSet *result;
@end

@interface BallotChoice (CoreDataGeneratedAccessors)

- (void)addResultObject:(BallotResultEntity *)value;
- (void)removeResultObject:(BallotResultEntity *)value;
- (void)addResult:(NSSet *)values;
- (void)removeResult:(NSSet *)values;

#pragma mark - Own methods

- (nullable BallotResultEntity *)getOwnResult;

- (nullable BallotResultEntity *)getResultForId:(nonnull NSString *)contactId NS_SWIFT_NAME(getResult(for:));

- (void)removeResultForContact:(nonnull NSString *)contactId;

- (NSInteger)totalCountOfResultsTrue;

- (nullable NSSet *)participantIdsForResultsTrue NS_SWIFT_NAME(participantIDsForResultsTrue());

- (nullable NSSet *)getAllParticipantIds NS_SWIFT_NAME(getAllParticipantIDs());

@end
