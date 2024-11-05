//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2023 Threema GmbH
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

import CocoaLumberjackSwift
import Foundation
import PromiseKit
import ThreemaEssentials

public protocol UnreadMessagesProtocol: UnreadMessagesProtocolObjc {
    func read(for conversation: ConversationEntity, isAppInBackground: Bool) -> Int
    func read(for messages: [BaseMessage], in conversation: ConversationEntity, isAppInBackground: Bool) -> Int
}

@objc public protocol UnreadMessagesProtocolObjc {
    @discardableResult
    func count(for conversation: ConversationEntity, withPerformBlockAndWait: Bool) -> Int
    @discardableResult
    func totalCount() -> Int
    @discardableResult
    func totalCount(doCalcUnreadMessagesCountOf: Set<ConversationEntity>, withPerformBlockAndWait: Bool) -> Int
}

extension UnreadMessagesProtocolObjc {
    @discardableResult
    public func count(for conversation: ConversationEntity, withPerformBlockAndWait: Bool = true) -> Int {
        count(for: conversation, withPerformBlockAndWait: withPerformBlockAndWait)
    }
    
    @discardableResult
    public func totalCount(
        doCalcUnreadMessagesCountOf: Set<ConversationEntity>,
        withPerformBlockAndWait: Bool = true
    ) -> Int {
        totalCount(
            doCalcUnreadMessagesCountOf: doCalcUnreadMessagesCountOf,
            withPerformBlockAndWait: withPerformBlockAndWait
        )
    }
}

@objc public class UnreadMessages: NSObject, UnreadMessagesProtocol {
    private let messageSender: MessageSenderProtocol
    private let entityManager: EntityManager
    
    required init(messageSender: MessageSenderProtocol, entityManager: EntityManager) {
        self.messageSender = messageSender
        self.entityManager = entityManager
    }

    convenience init(entityManager: EntityManager, taskManager: TaskManagerProtocol) {
        self.init(
            messageSender: MessageSender(entityManager: entityManager, taskManager: taskManager),
            entityManager: entityManager
        )
    }

    /// Unread messages count of conversation and recalculate `Conversation.unreadMessageCount`.
    /// - Parameter conversation: Conversation to counting und recalculating unread messages count
    /// - Returns: Unread messages count for this conversation
    @discardableResult
    public func count(for conversation: ConversationEntity, withPerformBlockAndWait: Bool = true) -> Int {
        var unreadMessagesCount = 0
        if withPerformBlockAndWait {
            entityManager.performAndWaitSave {
                unreadMessagesCount = self.count(
                    conversations: [conversation],
                    doCalcUnreadMessagesCountOf: [conversation]
                )
            }
        }
        else {
            unreadMessagesCount = count(conversations: [conversation], doCalcUnreadMessagesCountOf: [conversation])
        }

        return unreadMessagesCount
    }

    /// Unread messages count of all conversations (count only cached `Conversation.unreadMessageCount`).
    /// - Returns: Unread messages count of all conversations
    @discardableResult
    public func totalCount() -> Int {
        totalCount(doCalcUnreadMessagesCountOf: Set<ConversationEntity>())
    }

    /// Unread messages count of all conversations, and recalculate `Conversation.unreadMessageCount` for given
    /// conversations.
    /// - Parameter doCalcUnreadMessagesCountOf: Recalculate unread messages count for this conversations
    /// - Returns: Unread messages count of all conversations
    @discardableResult
    public func totalCount(
        doCalcUnreadMessagesCountOf: Set<ConversationEntity>,
        withPerformBlockAndWait: Bool = true
    ) -> Int {
        let block = {
            var unreadMessagesCount = 0
            var conversations = [ConversationEntity]()

            for conversation in self.entityManager.entityFetcher.allConversations() {
                if let conversation = conversation as? ConversationEntity {
                    conversations.append(conversation)
                }
            }

            if !conversations.isEmpty {
                unreadMessagesCount = self.count(
                    conversations: conversations,
                    doCalcUnreadMessagesCountOf: doCalcUnreadMessagesCountOf
                )
            }

            return unreadMessagesCount
        }
        
        if withPerformBlockAndWait {
            return entityManager.performAndWaitSave(block)
        }
        else {
            return block()
        }
    }
    
    private func count(
        conversations: [ConversationEntity],
        doCalcUnreadMessagesCountOf: Set<ConversationEntity>
    ) -> Int {
        var totalCount = 0

        for conversation in conversations {
            var count = 0
            if doCalcUnreadMessagesCountOf.contains(where: { item in
                item.objectID == conversation.objectID
            }) {
                count = entityManager.entityFetcher.countUnreadMessages(for: conversation)
            }
            else {
                count = conversation.unreadMessageCount.intValue
            }
            
            // Check if conversation marked as unread
            if count == 0,
               conversation.unreadMessageCount == -1 {
                count = -1
            }

            if count != -1 {
                totalCount += count
            }
            else {
                totalCount += 1
            }

            guard conversation.unreadMessageCount.intValue != count else {
                if count != 0 {
                    DDLogVerbose(
                        "Unread message count unchanged (\(count)) for conversation \(conversation.displayName)"
                    )
                }
                continue
            }
            conversation.unreadMessageCount = NSNumber(integerLiteral: count)

            DDLogVerbose(
                "Unread message count updated (\(count)) for conversation \(conversation.displayName)"
            )
        }

        return totalCount
    }
    
    /// Sends read receipts for all unread messages in conversation, for group conversation just update message read.
    /// - Warning: Use this function within db context perform block
    /// - Parameters:
    ///   - conversation: Conversation to send receipts
    ///   - isAppInBackground: If App is in background
    /// - Returns: The number of messages that were marked as read or zero if none were marked as read
    public func read(for conversation: ConversationEntity, isAppInBackground: Bool) -> Int {

        // Only send receipt if not Group
        guard let messages = entityManager.entityFetcher.unreadMessages(for: conversation) as? [BaseMessage] else {
            return 0
        }

        return read(for: messages, in: conversation, isAppInBackground: isAppInBackground)
    }
    
    public func read(
        for messages: [BaseMessage],
        in conversation: ConversationEntity,
        isAppInBackground: Bool
    ) -> Int {
        // Only send receipt if not Group and App is in foreground
        guard !isAppInBackground else {
            DDLogVerbose("App is not in foreground do not mark as read.")
            return 0
        }

        // Unread messages are only incoming messages
        var unreadMessages = [BaseMessage]()

        for baseMessage in messages where !baseMessage.isOwnMessage {
            unreadMessages.append(baseMessage)
        }

        guard !unreadMessages.isEmpty else {
            return 0
        }

        // Update message read
        updateMessageRead(messages: unreadMessages)
        totalCount(doCalcUnreadMessagesCountOf: [conversation])

        if conversation.isGroup {
            // Reflect read receipts for group message
            if let groupEntity = entityManager.entityFetcher.groupEntity(for: conversation) {
                
                // swiftformat:disable: acronyms
                let groupIdentity = GroupIdentity(
                    id: groupEntity.groupId,
                    creator: ThreemaIdentity(groupEntity.groupCreator ?? MyIdentityStore.shared().identity)
                )
                // swiftformat:enable: acronyms

                // Send (reflect) read receipt
                let unreadMessagesLocal = unreadMessages
                Task {
                    await messageSender.sendReadReceipt(for: unreadMessagesLocal, toGroupIdentity: groupIdentity)
                }
            }
        }
        else if let identity = conversation.contact?.threemaIdentity {
            // Send read receipt
            let unreadMessagesLocal = unreadMessages
            Task {
                await messageSender.sendReadReceipt(
                    for: unreadMessagesLocal,
                    toIdentity: identity
                )
            }
        }
        
        return unreadMessages.count
    }

    private func updateMessageRead(messages: [BaseMessage]) {
        entityManager.performAndWaitSave {
            for message in messages {
                message.read = NSNumber(booleanLiteral: true)
                message.readDate = Date()
                DDLogVerbose("Message marked as read: \(message.id.hexString)")
            }
        }
    }
}
