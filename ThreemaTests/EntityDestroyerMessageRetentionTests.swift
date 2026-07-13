import CoreData
import Testing
@testable import Threema
@testable import ThreemaFramework

/// The suite is serialized because it mutates the global `Date.currentDate`.
@Suite("Message Retention Tests", .serialized)
final class EntityDestroyerMessageRetentionTests {

    private typealias Option = StorageManagementConversationView.OlderThanOption

    private let testDatabase: TestDatabase

    /// Fixed date to use in tests to avoid flakiness
    private let referenceDate = Date(timeIntervalSince1970: 1_000_000_000)

    init() {
        AppGroup.setGroupID("group.ch.threema")
        Date.currentDate = referenceDate
        testDatabase = TestDatabase()
    }

    // MARK: - Tests
    
    @Test("Deletes messages older than the cut-off, keeps the message at the cut-off and newer ones")
    func deletesOlderThanCutoffKeepsCutoffAndNewer() async throws {
        for option in Option.commonCases {
            let cutoff = try #require(option.date, "\(option) must define a cut-off date")
            let (contact, conversation) = makeConversation()

            let older = addText(conversation, sender: contact, date: days(-2, from: cutoff))
            let atCutoff = addText(conversation, sender: contact, date: cutoff)
            let newer = addText(conversation, sender: contact, date: days(2, from: cutoff))

            runRetention(olderThan: cutoff, conversations: [conversation])

            let remaining = remainingMessageIDs(in: conversation)
            #expect(!remaining.contains(older.id), "\(option): older message should be deleted")
            #expect(
                remaining == [atCutoff.id, newer.id],
                "\(option): message at cut-off and newer message must be kept"
            )
        }
    }

    // MARK: Poll messages
    
    @Test("Open ballot messages survive retention")
    func keepsOpenBallotMessage() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()

        let openBallot = addBallotMessage(conversation, sender: contact, date: days(-5, from: cutoff), closed: false)
        let text = addText(conversation, sender: contact, date: days(-5, from: cutoff))

        runRetention(olderThan: cutoff, conversations: [conversation])

        let remaining = remainingMessageIDs(in: conversation)
        #expect(remaining == [openBallot.id], "Open ballot must survive, the plain text must be deleted")
        #expect(!remaining.contains(text.id))
    }

    @Test("Closed ballot messages are deleted")
    func deletesClosedBallotMessage() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()

        _ = addBallotMessage(conversation, sender: contact, date: days(-5, from: cutoff), closed: true)

        runRetention(olderThan: cutoff, conversations: [conversation])

        #expect(remainingMessageIDs(in: conversation).isEmpty, "closed ballot must be deleted")
    }

    // MARK: Starred messages

    @Test("Starred messages survive retention")
    func keepsStarredMessage() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()

        let starred = addText(conversation, sender: contact, date: days(-5, from: cutoff), starred: true)
        let unstarred = addText(conversation, sender: contact, date: days(-5, from: cutoff))

        runRetention(olderThan: cutoff, conversations: [conversation])

        let remaining = remainingMessageIDs(in: conversation)
        #expect(remaining == [starred.id], "starred message must survive, the unstarred one must be deleted")
        #expect(!remaining.contains(unstarred.id))
    }

    // MARK: Other types

    @Test("Text, image, video, file, system, audio and location messages are all deleted")
    func deletesAllNonExcludedMessageTypes() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()
        let oldDate = days(-5, from: cutoff)
        let preparer = testDatabase.preparer

        preparer.save {
            _ = preparer.createTextMessage(
                conversation: conversation, date: oldDate, isOwn: false, sender: contact, remoteSentDate: oldDate
            )
            _ = preparer.createImageMessageEntity(
                conversation: conversation, image: nil, thumbnail: nil, date: oldDate, isOwn: false,
                sender: contact, remoteSentDate: oldDate
            )
            _ = preparer.createVideoMessageEntity(
                conversation: conversation, video: nil, duration: 1, thumbnail: nil, date: oldDate, isOwn: false,
                sender: contact, remoteSentDate: oldDate
            )
            _ = preparer.createFileMessageEntity(conversation: conversation, date: oldDate)
            _ = preparer.createSystemMessage(conversation: conversation, type: .fsDebugMessage, date: oldDate)

            // Audio and location messages set their date internally, so override it afterwards.
            let audio = preparer.createAudioMessageEntity(conversation: conversation, duration: 1) { $0.date = oldDate }
            audio.date = oldDate
            let location = preparer.createLocationMessage(
                conversation: conversation, accuracy: 1, latitude: 1, longitude: 1, poiName: "Test", isOwn: false,
                sender: contact
            )
            location.date = oldDate
        }

        runRetention(olderThan: cutoff, conversations: [conversation])

        #expect(
            remainingMessageIDs(in: conversation).isEmpty,
            "text, image, video, file, system, audio and location messages should all be deleted"
        )
    }

    // MARK: Test last message

    @Test("Conversation.lastMessage is nullified when the referenced message is deleted")
    func nullifiesLastMessageWhenItIsDeleted() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()

        let preparer = testDatabase.preparer
        let lastMessage = preparer.save { () -> TextMessageEntity in
            let message = preparer.createTextMessage(
                conversation: conversation, date: days(-5, from: cutoff), isOwn: false, sender: contact,
                remoteSentDate: days(-5, from: cutoff)
            )
            conversation.lastMessage = message
            return message
        }
        #expect(conversation.lastMessage?.id == lastMessage.id)

        runRetention(olderThan: cutoff, conversations: [conversation])

        testDatabase.context.main.refresh(conversation, mergeChanges: true)
        #expect(conversation.lastMessage == nil, "lastMessage must be nullified once the message is deleted")
        #expect(remainingMessageIDs(in: conversation).isEmpty)
    }

    // MARK: No messages to delete

    @Test("Deleting in an empty conversation is a no-op")
    func emptyConversationIsNoOp() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (_, conversation) = makeConversation()

        runRetention(olderThan: cutoff, conversations: [conversation])

        #expect(remainingMessageIDs(in: conversation).isEmpty)
    }

    @Test("Nothing is deleted when all messages are newer than the cut-off")
    func keepsEverythingWhenAllMessagesAreNewerThanCutoff() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()

        let a = addText(conversation, sender: contact, date: days(2, from: cutoff))
        let b = addText(conversation, sender: contact, date: days(5, from: cutoff))

        runRetention(olderThan: cutoff, conversations: [conversation])

        #expect(remainingMessageIDs(in: conversation) == [a.id, b.id], "no message older than the cut-off exists")
    }

    // MARK: - Message to delete count
    
    @Test("messagesToBeDeleted matches the number of messages actually deleted")
    func messagesToBeDeletedMatchesActualDeletion() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()
        let oldDate = days(-5, from: cutoff)

        let plainA = addText(conversation, sender: contact, date: oldDate)
        let plainB = addText(conversation, sender: contact, date: oldDate)
        let starred = addText(conversation, sender: contact, date: oldDate, starred: true)
        _ = addBallotMessage(conversation, sender: contact, date: oldDate, closed: true)
        let openBallot = addBallotMessage(conversation, sender: contact, date: oldDate, closed: false)
        let newer = addText(conversation, sender: contact, date: days(2, from: cutoff))

        let beforeCount = remainingMessageIDs(in: conversation).count // 6

        // Deletable old messages = plainA + plainB + closed ballot = 3 (open ballot and starred are excluded).
        let toBeDeleted = testDatabase.entityManager.entityDestroyer.messagesToBeDeleted(
            olderThan: cutoff, for: [conversation.objectID]
        )
        #expect(toBeDeleted == 3, "open ballots and starred messages are excluded from the count")

        runRetention(olderThan: cutoff, conversations: [conversation])

        let remaining = remainingMessageIDs(in: conversation)
        #expect(remaining == [starred.id, openBallot.id, newer.id])
        #expect(!remaining.contains(plainA.id))
        #expect(!remaining.contains(plainB.id))
        // The predicted count equals what was actually removed.
        #expect(beforeCount - remaining.count == toBeDeleted)
    }

    // MARK: - Custom MDM value
    
    @Test("`.custom` retention deletes messages older than the custom number of days")
    func customRetentionDeletesOlderThanCustomDays() async throws {
        let customDays = 30
        let cutoff = try #require(Option.custom(customDays).date)
        let (contact, conversation) = makeConversation()

        let older = addText(conversation, sender: contact, date: days(-2, from: cutoff))
        let newer = addText(conversation, sender: contact, date: days(2, from: cutoff))

        makeRetentionManager(keepMessagesDays: customDays).deleteOldMessages()

        let remaining = remainingMessageIDs(in: conversation)
        #expect(remaining == [newer.id], "only messages older than \(customDays) days are deleted")
        #expect(!remaining.contains(older.id))
    }

    @Test("`.forever` retention keeps all messages")
    func foreverRetentionKeepsAllMessages() async throws {
        let foreverDays = try #require(Option.forever.days) // -1
        let (contact, conversation) = makeConversation()

        let veryOld = addText(conversation, sender: contact, date: days(-3650, from: referenceDate))
        let old = addText(conversation, sender: contact, date: days(-30, from: referenceDate))

        makeRetentionManager(keepMessagesDays: foreverDays).deleteOldMessages()

        #expect(
            remainingMessageIDs(in: conversation) == [veryOld.id, old.id],
            ".forever (keepMessagesDays = \(foreverDays)) must not delete anything"
        )
    }

    // MARK: - Mixed realistic chat
    @Test("Realistic mixed conversation is pruned correctly and leaves the context in a savable state")
    func realLifeMixedConversationDeletion() async throws {
        let cutoff = try #require(Option.oneMonth.date)
        let (contact, conversation) = makeConversation()
        let oldDate = days(-10, from: cutoff)
        let newDate = days(10, from: cutoff)
        let preparer = testDatabase.preparer

        // Messages that must be deleted
        var deletedIDs = Set<Data>()
        // Messages that must survive
        var survivingIDs = Set<Data>()

        preparer.save {
            // Old, deletable
            deletedIDs.insert(preparer.createTextMessage(
                conversation: conversation, text: "old 1", date: oldDate, isOwn: false, sender: contact,
                remoteSentDate: oldDate
            ).id)
            let oldLast = preparer.createTextMessage(
                conversation: conversation, text: "old 2", date: oldDate, isOwn: true, sender: contact,
                remoteSentDate: nil
            )
            deletedIDs.insert(oldLast.id)
            deletedIDs.insert(preparer.createSystemMessage(
                conversation: conversation, type: .fsDebugMessage, date: oldDate
            ).id)
            deletedIDs.insert(preparer.createSystemMessage(
                conversation: conversation, type: .fsDebugMessage, date: oldDate
            ).id)
            let oldClosedBallot = preparer.createBallot(conversation: conversation)
            oldClosedBallot.state = NSNumber(value: BallotEntity.BallotState.closed.rawValue)
            deletedIDs.insert(
                preparer.createBallotMessage(
                    conversation: conversation,
                    ballot: oldClosedBallot,
                    ballotState: BallotEntity.BallotState.closed.rawValue,
                    date: oldDate,
                    isOwn: false,
                    sender: contact,
                    remoteSentDate: oldDate
                ).id
            )

            // Old, but excluded from deletion
            let oldOpenBallot = preparer.createBallot(conversation: conversation)
            oldOpenBallot.state = NSNumber(value: BallotEntity.BallotState.open.rawValue)
            survivingIDs.insert(
                preparer.createBallotMessage(
                    conversation: conversation,
                    ballot: oldOpenBallot,
                    ballotState: BallotEntity.BallotState.open.rawValue,
                    date: oldDate,
                    isOwn: false,
                    sender: contact,
                    remoteSentDate: oldDate
                ).id
            )
            let oldStarred = preparer.createTextMessage(
                conversation: conversation, text: "old starred", date: oldDate, isOwn: false, sender: contact,
                remoteSentDate: oldDate
            )
            _ = MessageMarkersEntity(context: self.testDatabase.context.main, star: true, message: oldStarred)
            survivingIDs.insert(oldStarred.id)

            // New, kept
            survivingIDs.insert(preparer.createTextMessage(
                conversation: conversation, text: "new 1", date: newDate, isOwn: false, sender: contact,
                remoteSentDate: newDate
            ).id)
            survivingIDs.insert(preparer.createTextMessage(
                conversation: conversation, text: "new 2", date: newDate, isOwn: false, sender: contact,
                remoteSentDate: newDate
            ).id)
            survivingIDs.insert(preparer.createSystemMessage(
                conversation: conversation, type: .fsDebugMessage, date: newDate
            ).id)

            // The conversation's last message points at a to-be-deleted message
            conversation.lastMessage = oldLast
        }

        runRetention(olderThan: cutoff, conversations: [conversation])

        let remaining = remainingMessageIDs(in: conversation)
        #expect(remaining == survivingIDs, "only newer + open ballot + starred survive")
        #expect(remaining.isDisjoint(with: deletedIDs))

        testDatabase.context.main.refresh(conversation, mergeChanges: true)
        #expect(conversation.lastMessage == nil, "dangling lastMessage must have been nullified")

        // Regression: a subsequent save on the shared main context must not fail validation. The block performs a throwing store access so the throwing `performAndWaitSave`
        // overload is selected and a save validation error would propagate (and fail this `throws` test).
        try testDatabase.entityManager.performAndWaitSave {
            conversation.lastUpdate = self.referenceDate
            _ = try self.testDatabase.context.main
                .count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Message"))
        }
    }

    // MARK: - Helpers

    private func makeConversation() -> (ContactEntity, ConversationEntity) {
        let preparer = testDatabase.preparer
        var contact: ContactEntity!
        var conversation: ConversationEntity!
        preparer.save {
            contact = preparer.createContact(identity: "ECHOECHO")
            conversation = preparer.createConversation(contactEntity: contact)
        }
        return (contact, conversation)
    }

    private func makeRetentionManager(keepMessagesDays: Int) -> MessageRetentionManagerModel {
        let userSettings = UserSettingsMock()
        userSettings.keepMessagesDays = keepMessagesDays
        return MessageRetentionManagerModel(
            userSettings: userSettings,
            unreadMessages: UnreadMessagesMock(),
            groupManager: GroupManagerMock(),
            entityManager: testDatabase.entityManager
        )
    }

    @discardableResult
    private func addText(
        _ conversation: ConversationEntity,
        sender: ContactEntity,
        date: Date,
        starred: Bool = false
    ) -> TextMessageEntity {
        let preparer = testDatabase.preparer
        return preparer.save { () -> TextMessageEntity in
            let message = preparer.createTextMessage(
                conversation: conversation, date: date, isOwn: false, sender: sender, remoteSentDate: date
            )
            if starred {
                _ = MessageMarkersEntity(context: self.testDatabase.context.main, star: true, message: message)
            }
            return message
        }
    }

    @discardableResult
    private func addBallotMessage(
        _ conversation: ConversationEntity,
        sender: ContactEntity,
        date: Date,
        closed: Bool
    ) -> BallotMessageEntity {
        let preparer = testDatabase.preparer
        let state = closed ? BallotEntity.BallotState.closed.rawValue : BallotEntity.BallotState.open.rawValue
        return preparer.save { () -> BallotMessageEntity in
            let ballot = preparer.createBallot(conversation: conversation)
            ballot.state = NSNumber(value: state)
            return preparer.createBallotMessage(
                conversation: conversation, ballot: ballot, ballotState: state, date: date, isOwn: false,
                sender: sender, remoteSentDate: date
            )
        }
    }

    private func runRetention(olderThan: Date, conversations: [ConversationEntity]) {
        testDatabase.entityManager.entityDestroyer.deleteMessagesForMessageRetention(
            olderThan: olderThan,
            for: conversations.map(\.objectID)
        )
    }

    private func remainingMessageIDs(in conversation: ConversationEntity) -> Set<Data> {
        var ids = Set<Data>()
        let context = testDatabase.context.main
        context.performAndWait {
            let request = NSFetchRequest<BaseMessageEntity>(entityName: "Message")
            request.predicate = NSPredicate(format: "conversation == %@", conversation)
            ids = Set((try? context.fetch(request))?.map(\.id) ?? [])
        }
        return ids
    }

    private func days(_ value: Int, from base: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: value, to: base)!
    }
}
