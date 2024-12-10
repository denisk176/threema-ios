//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2023 Threema GmbH
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

#import "GroupTableDataSource.h"
#import "EntityCreator.h"
#import "EntityFetcher.h"
#import "ErrorHandler.h"
#import "ContactStore.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelInfo;
#else
static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif

@interface GroupTableDataSource () <NSFetchedResultsControllerDelegate>

@property NSArray *filteredGroups;
@property NSFetchedResultsController *fetchedResultsController;

@property (nonatomic) NSMutableSet *selectedGroups;

@property EntityManager *entityManager;
@property id<NSFetchedResultsControllerDelegate> fetchedResultsControllerDelegate;
@property MessagePermission *messagePermission;

@property BOOL ignoreUpdates;

@end

@implementation GroupTableDataSource {
    GroupManager *groupManager;
}

+ (instancetype)groupTableDataSource {
    return [[GroupTableDataSource alloc] initWithFetchedResultsControllerDelegate:nil];
}

+ (instancetype)groupTableDataSourceWithFetchedResultsControllerDelegate:(id<NSFetchedResultsControllerDelegate>)delegate {
    return [[GroupTableDataSource alloc] initWithFetchedResultsControllerDelegate:delegate];
}

- (void)dealloc {
    _fetchedResultsController.delegate = nil;
    _fetchedResultsControllerDelegate = nil;
}

- (instancetype)initWithFetchedResultsControllerDelegate:(id<NSFetchedResultsControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        BusinessInjector *businessInjector = [[BusinessInjector alloc] init];
        _messagePermission = [[MessagePermission alloc] initWithMyIdentityStore:businessInjector.myIdentityStore userSettings:businessInjector.userSettings groupManager:businessInjector.groupManagerObjC entityManager:businessInjector.entityManager];
        _entityManager = businessInjector.entityManager;
        _selectedGroups = [NSMutableSet set];

        self->groupManager = businessInjector.groupManagerObjC;

        if (delegate) {
            _fetchedResultsControllerDelegate = delegate;
            delegate = self;
        }
        
        [self setupFetchedResultsControllerWithDelegate:delegate];
    }
    
    return self;
}

- (void)setupFetchedResultsControllerWithDelegate:(id<NSFetchedResultsControllerDelegate>)delegate {
    NSFetchedResultsController *fetchedResultsController = [_entityManager.entityFetcher fetchedResultsControllerForGroups];
    fetchedResultsController.delegate = delegate;
    _fetchedResultsController = fetchedResultsController;
    
    NSError *error = nil;
    if (![_fetchedResultsController performFetch:&error]) {
        DDLogError(@"Unresolved error %@, %@", error, [error userInfo]);
        [ErrorHandler abortWithError: error];
    }
}

-(void)filterByWords:(NSArray *)words {
    if (words) {
        _filteredGroups = [_entityManager.entityFetcher groupConversationsFilteredByWords:words];
    } else {
        _filteredGroups= nil;
    }
}

- (NSSet *)selectedConversations {
    NSMutableSet *conversations = [NSMutableSet setWithCapacity:[_selectedGroups count]];
    for (Group *group in _selectedGroups) {
        ConversationEntity *conversationEntity = [[_entityManager entityFetcher] conversationEntityForGroupId:group.groupID creator:group.groupCreatorIdentity];
        [conversations addObject:conversationEntity];
    }
    return conversations;
}

- (NSArray *)groupsForConversations:(NSArray *)conversations {
    
    NSMutableArray *groups = [NSMutableArray arrayWithCapacity: [conversations count]];
    
    for (ConversationEntity *conversation in conversations) {
        Group *grp = [groupManager getGroupWithConversation:conversation];
        if ([grp didLeave] == NO) {
            [groups addObject:grp];
        }
    }
    
    return groups;
}

- (void)setIgnoreFRCUpdates:(BOOL)ignoreFRCUpdates {
    _ignoreUpdates = ignoreFRCUpdates;
}

- (BOOL)ignoreFRCUpdates {
    return _ignoreUpdates;
}

- (BOOL)isFiltered {
    return (_filteredGroups != nil);
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_filteredGroups) {
        return [_filteredGroups count];
    }
    
    id <NSFetchedResultsSectionInfo> sectionInfo = [[_fetchedResultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Group *group = [self groupAtIndexPath:indexPath];
    
    GroupCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GroupCell"];
    cell.group = group;
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return nil;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return nil;
}

- (BOOL)canSelectCellAtIndexPath:(NSIndexPath *)indexPath {
    return true;
}

- (void)selectedCellAtIndexPath:(NSIndexPath *)indexPath selected:(BOOL)selected {
    Group *group = [self groupAtIndexPath:indexPath];
    
    if (selected && group) {
        if (![_selectedGroups containsObject:group]) {
            [_selectedGroups addObject:group];
        }
    } else {
        [_selectedGroups enumerateObjectsUsingBlock:^(Group *tmpGroup, BOOL * _Nonnull stop) {
            if ([group.groupID isEqualToData:tmpGroup.groupID]) {
                [_selectedGroups removeObject:tmpGroup];
                *stop = YES;
            }
        }];
    }
}

- (Group *)groupAtIndexPath:(NSIndexPath *)indexPath {
    ConversationEntity *conversation;
    if (_filteredGroups) {
        conversation = [_filteredGroups objectAtIndex:indexPath.row];
    } else {
        conversation = [_fetchedResultsController objectAtIndexPath:indexPath];
    }
    
    return [groupManager getGroupWithConversation:conversation];
}

- (NSIndexPath *)indexPathForObject:(id)object {
    Group *group = (Group *)object;
    return [_fetchedResultsController indexPathForObject:group.conversation];
}

#pragma mark - Fetched results controller

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    if (_ignoreUpdates || _filteredGroups != nil) {
        return;
    }
    
    [_fetchedResultsControllerDelegate controllerWillChangeContent:controller];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type
{
    if (_ignoreUpdates || _filteredGroups != nil) {
        return;
    }
    
    [_fetchedResultsControllerDelegate controller:controller didChangeSection:sectionInfo atIndex:sectionIndex forChangeType:type];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    if (_ignoreUpdates || _filteredGroups != nil) {
        return;
    }
    
    if ([anObject isKindOfClass:[ConversationEntity class]]) {
        anObject = [groupManager getGroupWithConversation:(ConversationEntity*)anObject];
    }

    [_fetchedResultsControllerDelegate controller:controller didChangeObject:anObject atIndexPath:indexPath forChangeType:type newIndexPath:newIndexPath];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    if (_ignoreUpdates || _filteredGroups != nil) {
        return;
    }
    
    [_fetchedResultsControllerDelegate controllerDidChangeContent:controller];
}

@end
