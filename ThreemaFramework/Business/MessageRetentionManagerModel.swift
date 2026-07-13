import Foundation

/// Handles the logic of message retention
///  - Delete old messages based on user settings or mdm values (MDM overwrites user settings)
///  - Filter affected conversations based on Policy (currently only to filter out Note Groups)
public final class MessageRetentionManagerModel: MessageRetentionManagerModelProtocol & ObservableObject {
  
    @Published public var selection: Int = MessageRetentionManagerModel.defaultValue
    
    private let userSettings: UserSettingsProtocol
    private let unreadMessages: UnreadMessagesProtocol
    private let groupManager: GroupManagerProtocol
    private let entityManager: EntityManager
    
    private static let defaultValue = -1
    
    private let mdm = MDMSetup()
    
    public var isMDM: Bool {
        (mdm?.keepMessagesDays() as? Int) != nil
    }
    
    private var keepMessagesDays: Int {
        // Custom days are only valid between 7 and 3650, values <= 0 should be excluded
        let checkDays: (Int) -> Int = { days in
            switch days {
            case 1..<7:
                7
            case 3650...:
                3650
            default:
                days
            }
        }
        
        guard let keepMessagesDays = mdm?.keepMessagesDays() as? Int else {
            // Take UserSettings if the MDM values are not set
            return checkDays(userSettings.keepMessagesDays)
        }
        
        return checkDays(keepMessagesDays)
    }
    
    init(
        userSettings: UserSettingsProtocol,
        unreadMessages: UnreadMessagesProtocol,
        groupManager: GroupManagerProtocol,
        entityManager: EntityManager
    ) {
        self.userSettings = userSettings
        self.unreadMessages = unreadMessages
        self.groupManager = groupManager
        self.entityManager = entityManager

        self.selection = keepMessagesDays
    }
    
    /// Deletes all messages according to the current setting. MDMs or userSettings `keepMessagesDays` are used to
    /// calculate the date after which messages should be deleted.
    public func deleteOldMessages() {
        guard keepMessagesDays > 0, let deletionDate = deletionDate(keepMessagesDays) else {
            return
        }
        DDLogNotice("[Message Retention] Deleting messages older than \(deletionDate)")
        
        entityManager.performAndWait {
            self.entityManager.entityDestroyer.deleteMessagesForMessageRetention(
                olderThan: deletionDate,
                for: self.conversations().map(\.objectID)
            )
            
            // Recompute unread
            if let conversations = self.entityManager.entityFetcher
                .notArchivedConversationEntities() {
                self.unreadMessages.totalCount(
                    doCalcUnreadMessagesCountOf: Set(conversations),
                    withPerformBlockAndWait: false
                )
            }
        }
    }
    
    /// Fetches the count of messages to be deleted.
    /// - Parameter retentionDays: The amount of days from now affected messages. Must be higher than `0` as `-1`
    /// accounts
    /// for `never`
    /// - Returns: number of messages to be deleted
    public func numberOfMessagesToDelete(for retentionDays: Int?) -> Int {
        guard let retentionDays, retentionDays > 0, let deletionDate = deletionDate(retentionDays) else {
            return 0
        }
        
        return entityManager.entityDestroyer.messagesToBeDeleted(
            olderThan: deletionDate,
            for: conversations().map(\.objectID)
        )
    }
    
    /// Update the current timeframe for  keeping Messages to the amount of `days` provided
    ///
    /// After setting the new value, we will trigger the deletion of old messages according to the new setting
    /// This function does nothing if the MDM setting is turned on
    ///
    /// - Parameter days: how many days in the past we will delete
    public func set(_ days: Int) {
        guard selection != days, keepMessagesDays != days, !isMDM else {
            return
        }
        
        selection = days
        userSettings.keepMessagesDays = days
            
        // Trigger Deletion
        self.deleteOldMessages()
    }
    
    /// Fetches the Conversations to be affected by the deletion
    private func conversations() -> [ConversationEntity] {
        let allConversationEntities = entityManager.entityFetcher.conversationEntities() ?? []
        return allConversationEntities.filter {
            // Note groups are excluded
            !(groupManager.getGroup(conversation: $0)?.isNoteGroup ?? false)
        }
    }
}
