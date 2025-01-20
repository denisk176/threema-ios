//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2025 Threema GmbH
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
import Combine
import Foundation
import PromiseKit
import ThreemaFramework

protocol UnreadMessagesStateManagerDelegate: AnyObject {
    /// Should unread messages be marked as read?
    var shouldMarkMessagesAsRead: Bool { get }
}

/// Manages the unread message state for a conversation in an instance of `ChatViewController`
final class UnreadMessagesStateManager {
    private typealias Config = ChatViewConfiguration.UnreadMessageLine

    // MARK: - Nested Types

    struct UnreadMessagesState: Hashable {
        /// The message above which an unread message line should be shown
        /// Nothing will be shown if it is nil
        var oldestConsecutiveUnreadMessage: NSManagedObjectID?
        /// The number of unread messages the current conversations
        var numberOfUnreadMessages = 0
    }
    
    // MARK: - Internal Published Properties

    /// The current unread message state
    @Published var unreadMessagesState: UnreadMessagesState? {
        didSet {
            if let unreadMessagesState {
                DDLogVerbose("New unread message count \(unreadMessagesState.numberOfUnreadMessages)")
            }
        }
    }
    
    /// True if the user is at the bottom of the `tableView` in ChatViewController
    @Published var userIsAtBottomOfTableView = true
    
    // MARK: - Private Properties

    private let businessInjector: BusinessInjectorProtocol
    private let messageFetcher: MessageFetcher
    private let conversation: ConversationEntity
    private let notificationManager: NotificationManagerProtocol
    private weak var delegate: UnreadMessagesStateManagerDelegate?
    
    private var firstRoundCompleted = false
    
    private var currentUnreadDBState: (
        unreadMessageObjectIDs: [NSManagedObjectID],
        newestUnreadMessageObjectID: NSManagedObjectID?
    ) {
        var unreadMessageObjectIDs = [NSManagedObjectID]()
        var newestUnreadMessageObjectID: NSManagedObjectID?
        
        businessInjector.entityManager.performAndWaitSave {
            let count = self.businessInjector.unreadMessages.count(
                for: self.conversation,
                withPerformBlockAndWait: false
            )
            if count > 0 {
                // swiftformat:disable:next all
                unreadMessageObjectIDs = self.messageFetcher.unreadMessages(limit: count).compactMap({$0.objectID})
                newestUnreadMessageObjectID = unreadMessageObjectIDs.last
            }
        }
        
        return (unreadMessageObjectIDs, newestUnreadMessageObjectID)
    }
    
    private let updateQueue = DispatchQueue(
        label: "ch.threema.chatView.unreadMessagesSnapshotQueue",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .inherit,
        target: nil
    )
    
    private var threadSafeDelegateShouldMarkMessagesAsRead: Bool {
        var shouldMarkMessagesAsRead = false
        
        if Thread.isMainThread {
            if ChatViewConfiguration.strictMode {
                fatalError("Don't call this on the main thread or you will deadlock")
            }
            else {
                resetState()
                return false
            }
        }
        
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        
        DispatchQueue.main.async {
            shouldMarkMessagesAsRead = self.delegate?.shouldMarkMessagesAsRead ?? false
            dispatchGroup.leave()
        }
        
        dispatchGroup.wait()
        
        return shouldMarkMessagesAsRead
    }
    
    // MARK: - Lifecycle

    init(
        conversation: ConversationEntity,
        businessInjector: BusinessInjectorProtocol,
        notificationManager: NotificationManagerProtocol = NotificationManager(),
        unreadMessagesStateManagerDelegate: UnreadMessagesStateManagerDelegate
    ) {
        self.messageFetcher = MessageFetcher(for: conversation, with: businessInjector.entityManager)
        self.businessInjector = businessInjector
        self.conversation = conversation
        self.notificationManager = notificationManager
        self.delegate = unreadMessagesStateManagerDelegate
        
        let dbState = currentUnreadDBState
        self.unreadMessagesState = UnreadMessagesState(
            oldestConsecutiveUnreadMessage: dbState.newestUnreadMessageObjectID,
            numberOfUnreadMessages: dbState.unreadMessageObjectIDs.count
        )
    }
    
    // MARK: - Configuration Functions

    /// Synchronously resets the unread message state to the current state in the DB
    func synchronousReconfiguration() {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let endTime = CFAbsoluteTimeGetCurrent()
            DDLogVerbose("Duration of \(#function) \(endTime - startTime) s")
        }
        
        if Thread.isMainThread {
            if ChatViewConfiguration.strictMode {
                fatalError("Don't call this on the main thread or you will deadlock")
            }
            else {
                resetState()
                return
            }
        }
        
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        _ = tick(willStayAtBottomOfView: false, isSetup: true).ensure {
            dispatchGroup.leave()
        }
        
        if dispatchGroup.wait(timeout: .now() + .seconds(15)) == .timedOut {
            DDLogError("\(#function) timed out even though it shouldn't. This is most likely an error.")
        }
    }
    
    // MARK: - Update Functions

    /// Updates the unread message state by adding the newly received messages to the state or keeping the state at zero
    /// - Parameter willStayAtBottomOfView: whether to _keep_ the unread messages state at no unread messages
    /// - Parameter isSetup: Is true on first run
    /// - Returns: Fulfills if the messages have been marked as read or the mark as read has failed
    @discardableResult
    func tick(willStayAtBottomOfView: Bool, isSetup: Bool = false) -> Promise<Void> {
        Promise { seal in
            updateQueue.async { [self] in
                let shouldMarkAsRead = threadSafeDelegateShouldMarkMessagesAsRead

                let (unreadMessageObjectIDs, newestUnreadMessageObjectID) = currentUnreadDBState

                if !unreadMessageObjectIDs.isEmpty, newestUnreadMessageObjectID == nil {
                    fatalError("Illegal unread message state")
                }
                if let firstUnreadMessageObjectID = unreadMessageObjectIDs.last, let newestUnreadMessageObjectID,
                   firstUnreadMessageObjectID != newestUnreadMessageObjectID {
                    fatalError("Illegal unread message state")
                }

                let previousCount: Int
                let oldestConsecutiveUnreadMessage: NSManagedObjectID?

                if let unreadMessagesState, unreadMessagesState.numberOfUnreadMessages > 0 {
                    previousCount = unreadMessagesState.numberOfUnreadMessages
                    oldestConsecutiveUnreadMessage = unreadMessagesState.oldestConsecutiveUnreadMessage
                }
                else {
                    previousCount = 0
                    oldestConsecutiveUnreadMessage = newestUnreadMessageObjectID
                }

                let newState: UnreadMessagesState

                let numberOfMessagesMarkedAsRead: Int =
                    if shouldMarkAsRead {
                        markAsReadAndWait(unreadMessageObjectIDs)
                    }
                    else {
                        0
                    }

                if willStayAtBottomOfView,
                   let unreadMessagesState,
                   unreadMessagesState.numberOfUnreadMessages == 0,
                   unreadMessagesState.oldestConsecutiveUnreadMessage == nil {

                    DDLogVerbose("Keep at zero because it was zero before and we're at the bottom of the view")
                    newState = UnreadMessagesState(
                        oldestConsecutiveUnreadMessage: nil,
                        numberOfUnreadMessages: 0
                    )
                }
                else if !shouldMarkAsRead {
                    DDLogVerbose(
                        "Setting unread count to current CD unread state \(unreadMessageObjectIDs.count)"
                    )
                    newState = UnreadMessagesState(
                        oldestConsecutiveUnreadMessage: oldestConsecutiveUnreadMessage,
                        numberOfUnreadMessages: unreadMessageObjectIDs.count
                    )
                }
                else if firstRoundCompleted {
                    // Regular case
                    DDLogVerbose(
                        "Setting unread count to \(previousCount) + \(numberOfMessagesMarkedAsRead) = \(previousCount + numberOfMessagesMarkedAsRead)"
                    )
                    newState = UnreadMessagesState(
                        oldestConsecutiveUnreadMessage: oldestConsecutiveUnreadMessage,
                        numberOfUnreadMessages: previousCount + numberOfMessagesMarkedAsRead
                    )
                }
                else {
                    DDLogVerbose("First run")
                    // The state is initialized with the current unread count when opening the chat
                    // without marking any messages as read for performance reasons.
                    // Thus we don't add the unread messages in the first iteration.
                    newState = UnreadMessagesState(
                        oldestConsecutiveUnreadMessage: oldestConsecutiveUnreadMessage,
                        numberOfUnreadMessages: numberOfMessagesMarkedAsRead
                    )
                    firstRoundCompleted = true
                }

                maybeUpdate(to: newState)

                seal.fulfill_()
            }
        }
    }
    
    /// Resets state to no unread messages
    func resetState() {
        DDLogVerbose("\(#function)")
        updateQueue.async { [self] in
            let newState = UnreadMessagesState(
                oldestConsecutiveUnreadMessage: nil,
                numberOfUnreadMessages: 0
            )
            
            maybeUpdate(to: newState)
        }
    }
    
    // MARK: - Private Helper Functions

    private func markAsReadAndWait(_ unreadMessageObjectIDs: [NSManagedObjectID]) -> Int {
        DDLogVerbose("\(#function)")
        
        if Thread.isMainThread {
            if ChatViewConfiguration.strictMode {
                fatalError("Don't call this on the main thread or you will deadlock")
            }
            else {
                resetState()
                return 0
            }
        }
        
        let shouldMarkMessagesAsRead = threadSafeDelegateShouldMarkMessagesAsRead

        guard shouldMarkMessagesAsRead else {
            return 0
        }

        return ConversationActions(businessInjector: businessInjector)
            .read(conversation.objectID, messageObjectIDs: unreadMessageObjectIDs)
    }
    
    @discardableResult
    private func maybeUpdate(to newState: UnreadMessagesState) -> Bool {
        DDLogVerbose("\(#function)")
        if unreadMessagesState != newState {
            unreadMessagesState = newState
            return true
        }
        return false
    }
}
