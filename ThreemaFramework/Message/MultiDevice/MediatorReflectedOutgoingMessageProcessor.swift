//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2025 Threema GmbH
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
import ThreemaProtocols

class MediatorReflectedOutgoingMessageProcessor {

    private let frameworkInjector: FrameworkInjectorProtocol
    private let messageStore: MessageStoreProtocol
    private let messageProcessorDelegate: MessageProcessorDelegate
    private let reflectedAt: Date
    private let maxBytesToDecrypt: Int
    private let timeoutDownloadThumbnail: Int

    init(
        frameworkInjector: FrameworkInjectorProtocol,
        messageStore: MessageStoreProtocol,
        messageProcessorDelegate: MessageProcessorDelegate,
        reflectedAt: Date,
        maxBytesToDecrypt: Int,
        timeoutDownloadThumbnail: Int
    ) {
        self.frameworkInjector = frameworkInjector
        self.messageStore = messageStore
        self.messageProcessorDelegate = messageProcessorDelegate
        self.reflectedAt = reflectedAt
        self.maxBytesToDecrypt = maxBytesToDecrypt
        self.timeoutDownloadThumbnail = timeoutDownloadThumbnail
    }

    /// Process reflected outgoing messages. Validate receiver or group of message and determines
    /// message processor for saving into DB and download blob data.
    ///
    /// Note that following abstract message types deprecated and will not exists as outgoing
    /// message anymore: `BoxAudioMessage`, `BoxImageMessage`, `BoxVideoMessage`, `GroupAudioMessage`
    /// `GroupImageMessage` and `GroupVideoMessage`
    ///
    /// - Parameters:
    ///     - outgoingMessage: Reflected outgoing message from mediator
    ///     - abstractMessage: Outgoing abstract message (decoded from `D2d_OutgoingMessage.body`)
    /// - Throws: MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated
    func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        abstractMessage amsg: some AbstractMessage
    ) throws -> Promise<Void> {
        switch amsg.self {
        case is BoxAudioMessage:
            throw MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated(type: omsg.type)
        case is BoxBallotCreateMessage:
            return try process(outgoingMessage: omsg, ballotCreateMessage: amsg as! BoxBallotCreateMessage)
        case is BoxBallotVoteMessage:
            return try process(ballotVoteMessage: amsg as! BoxBallotVoteMessage)
        case is BoxFileMessage:
            return try process(outgoingMessage: omsg, fileMessage: amsg as! BoxFileMessage)
        case is BoxImageMessage:
            throw MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated(type: omsg.type)
        case is BoxLocationMessage:
            return try process(outgoingMessage: omsg, locationMessage: amsg as! BoxLocationMessage)
        case is BoxTextMessage:
            return try process(outgoingMessage: omsg, textMessage: amsg as! BoxTextMessage)
        case is BoxVideoMessage:
            throw MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated(type: omsg.type)
        case is ContactDeletePhotoMessage:
            return process(contactDeletePhotoMessage: amsg as! ContactDeletePhotoMessage)
        case is ContactRequestPhotoMessage:
            return process(contactRequestPhotoMessage: amsg as! ContactRequestPhotoMessage)
        case is ContactSetPhotoMessage:
            return process(outgoingMessage: omsg, contactSetPhotoMessage: amsg as! ContactSetPhotoMessage)
        case is DeliveryReceiptMessage:
            return try process(outgoingMessage: omsg, deliveryReceiptMessage: amsg as! DeliveryReceiptMessage)
        case is DeleteMessage:
            return try process(outgoingMessage: omsg, deleteMessage: amsg as! DeleteMessage)
        case is DeleteGroupMessage:
            return try process(outgoingMessage: omsg, deleteGroupMessage: amsg as! DeleteGroupMessage)
        case is EditMessage:
            return try process(outgoingMessage: omsg, editMessage: amsg as! EditMessage)
        case is EditGroupMessage:
            return try process(outgoingMessage: omsg, editGroupMessage: amsg as! EditGroupMessage)
        case is GroupCreateMessage:
            return try process(groupCreateMessage: amsg as! GroupCreateMessage)
        case is GroupDeletePhotoMessage:
            return try process(outgoingMessage: omsg, groupDeletePhotoMessage: amsg as! GroupDeletePhotoMessage)
        case is GroupRenameMessage:
            return try process(outgoingMessage: omsg, groupRenameMessage: amsg as! GroupRenameMessage)
        case is GroupSetPhotoMessage:
            return try process(outgoingMessage: omsg, groupSetPhotoMessage: amsg as! GroupSetPhotoMessage)
        case is GroupDeliveryReceiptMessage:
            return try process(outgoingMessage: omsg, groupDeliveryReceiptMessage: amsg as! GroupDeliveryReceiptMessage)
        case is GroupAudioMessage:
            throw MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated(type: omsg.type)
        case is GroupBallotCreateMessage:
            return try process(outgoingMessage: omsg, groupBallotCreateMessage: amsg as! GroupBallotCreateMessage)
        case is GroupBallotVoteMessage:
            return try process(outgoingMessage: omsg, groupBallotVoteMessage: amsg as! GroupBallotVoteMessage)
        case is GroupFileMessage:
            return try process(outgoingMessage: omsg, groupFileMessage: amsg as! GroupFileMessage)
        case is GroupImageMessage:
            throw MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated(type: omsg.type)
        case is GroupLeaveMessage:
            return process(groupLeaveMessage: amsg as! GroupLeaveMessage)
        case is GroupLocationMessage:
            return try process(outgoingMessage: omsg, groupLocationMessage: amsg as! GroupLocationMessage)
        case is GroupTextMessage:
            return try process(outgoingMessage: omsg, groupTextMessage: amsg as! GroupTextMessage)
        case is GroupVideoMessage:
            throw MediatorReflectedProcessorError.outgoingMessageTypeIsDeprecated(type: omsg.type)
        case is BoxVoIPCallOfferMessage:
            return try process(outgoingMessage: omsg, voipCallOfferMessage: amsg as! BoxVoIPCallOfferMessage)
        case is BoxVoIPCallAnswerMessage:
            return try process(outgoingMessage: omsg, voipCallAnswerMessage: amsg as! BoxVoIPCallAnswerMessage)
        case is BoxVoIPCallIceCandidatesMessage:
            return try process(
                outgoingMessage: omsg,
                voipCallIceCandidatesMessage: amsg as! BoxVoIPCallIceCandidatesMessage
            )
        case is BoxVoIPCallHangupMessage:
            return try process(outgoingMessage: omsg, voipCallHangupMessage: amsg as! BoxVoIPCallHangupMessage)
        case is BoxVoIPCallRingingMessage:
            return try process(outgoingMessage: omsg, voipCallRingingMessage: amsg as! BoxVoIPCallRingingMessage)
        case is GroupCallStartMessage:
            return try process(outgoingMessage: omsg, groupCallStartMessage: amsg as! GroupCallStartMessage)
        case is ReactionMessage:
            return try process(outgoingMessage: omsg, reactionMessage: amsg as! ReactionMessage)
        case is GroupReactionMessage:
            return try process(outgoingMessage: omsg, groupReactionMessage: amsg as! GroupReactionMessage)
        default:
            return Promise { $0.reject(MediatorReflectedProcessorError.messageWontProcessed(
                message: "Reflected outgoing message type \(omsg.loggingDescription) will be not processed"
            ))
            }
        }
    }

    // MARK: Process reflected outgoing 1:1 chat messages
    
    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        ballotCreateMessage amsg: BoxBallotCreateMessage
    ) throws -> Promise<Void> {
        // TODO: Because fromIdentity is missing of reflected messages
        amsg.fromIdentity = frameworkInjector.myIdentityStore.identity

        return try messageStore.save(
            ballotCreateMessage: amsg,
            conversationIdentity: getReceiverIdentity(for: omsg),
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
    }

    private func process(
        ballotVoteMessage amsg: BoxBallotVoteMessage
    ) throws -> Promise<Void> {
        // TODO: Because fromIdentity is missing of reflected messages
        amsg.fromIdentity = frameworkInjector.myIdentityStore.identity

        try messageStore.save(ballotVoteMessage: amsg)
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        fileMessage amsg: BoxFileMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            fileMessage: amsg,
            conversationIdentity: getReceiverIdentity(for: omsg),
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true,
            timeoutDownloadThumbnail: timeoutDownloadThumbnail
        )
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        locationMessage amsg: BoxLocationMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            locationMessage: amsg,
            conversationIdentity: getReceiverIdentity(for: omsg),
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        textMessage amsg: BoxTextMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            textMessage: amsg,
            conversationIdentity: getReceiverIdentity(for: omsg),
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
        return Promise()
    }

    // MARK: Process reflected outgoing contact photo message
    
    private func process(
        contactDeletePhotoMessage amsg: ContactDeletePhotoMessage
    ) -> Promise<Void> {
        messageStore.save(contactDeletePhotoMessage: amsg)
        return Promise()
    }

    private func process(
        contactRequestPhotoMessage amsg: ContactRequestPhotoMessage
    ) -> Promise<Void> {
        frameworkInjector.contactStore.removeProfilePictureFlag(for: amsg.toIdentity)
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        contactSetPhotoMessage amsg: ContactSetPhotoMessage
    ) -> Promise<Void> {
        frameworkInjector.entityManager.performAndWaitSave {
            let contact = self.frameworkInjector.entityManager.entityFetcher
                .contact(for: amsg.toIdentity)
            contact?.profilePictureBlobID = amsg.blobID.base64EncodedString(options: .endLineWithLineFeed)
            contact?.profilePictureUpload = Date(timeIntervalSince1970: TimeInterval(omsg.createdAt))
        }
        return Promise()
    }

    // MARK: Process reflected outgoing delivery receipts
    
    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        deliveryReceiptMessage amsg: DeliveryReceiptMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            deliveryReceiptMessage: amsg,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    // MARK: Process reflected outgoing delete / edit message

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        deleteMessage amsg: DeleteMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            deleteMessage: amsg,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        deleteGroupMessage amsg: DeleteGroupMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            deleteGroupMessage: amsg,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        editMessage amsg: EditMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            editMessage: amsg,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        editGroupMessage amsg: EditGroupMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            editGroupMessage: amsg,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    // MARK: Process reflected outgoing group control messages
    
    private func process(
        groupCreateMessage amsg: GroupCreateMessage
    ) throws -> Promise<Void> {
        try messageStore.save(groupCreateMessage: amsg)
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupDeletePhotoMessage amsg: GroupDeletePhotoMessage
    ) throws -> Promise<Void> {
        try getGroup(for: omsg)
        return messageStore.save(groupDeletePhotoMessage: amsg)
    }

    private func process(
        groupLeaveMessage amsg: GroupLeaveMessage
    ) -> Promise<Void> {
        messageStore.save(groupLeaveMessage: amsg)
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupRenameMessage amsg: GroupRenameMessage
    ) throws -> Promise<Void> {
        try getGroup(for: omsg)
        return messageStore.save(groupRenameMessage: amsg)
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupSetPhotoMessage amsg: GroupSetPhotoMessage
    ) throws -> Promise<Void> {
        try getGroup(for: omsg)
        return messageStore.save(groupSetPhotoMessage: amsg)
    }
    
    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupDeliveryReceiptMessage amsg: GroupDeliveryReceiptMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            groupDeliveryReceiptMessage: amsg,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    // MARK: Process reflected outgoing group message

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupBallotCreateMessage amsg: GroupBallotCreateMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            groupBallotCreateMessage: amsg,
            senderIdentity: frameworkInjector.myIdentityStore.identity,
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupBallotVoteMessage amsg: GroupBallotVoteMessage
    ) throws -> Promise<Void> {
        // TODO: Because fromIdentity is missing of reflected messages
        amsg.fromIdentity = frameworkInjector.myIdentityStore.identity

        try getGroup(for: omsg)
        try messageStore.save(groupBallotVoteMessage: amsg)
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupFileMessage amsg: GroupFileMessage
    ) throws -> Promise<Void> {
        messageStore.save(
            groupFileMessage: amsg,
            senderIdentity: frameworkInjector.myIdentityStore.identity,
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true,
            timeoutDownloadThumbnail: timeoutDownloadThumbnail
        )
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupLocationMessage amsg: GroupLocationMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            groupLocationMessage: amsg,
            senderIdentity: frameworkInjector.myIdentityStore.identity,
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupTextMessage amsg: GroupTextMessage
    ) throws -> Promise<Void> {
        try getGroup(for: omsg)
        try messageStore.save(
            groupTextMessage: amsg,
            senderIdentity: frameworkInjector.myIdentityStore.identity,
            messageID: omsg.messageID.littleEndianData,
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
        return Promise()
    }

    // MARK: Process reflected outgoing VoIPCall messages

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        voipCallOfferMessage amsg: BoxVoIPCallOfferMessage
    ) throws -> Promise<Void> {
        let receiverIdentity = try getReceiverIdentity(for: omsg)
        guard let msg = VoIPCallMessageDecoder.decodeVoIPCallOffer(from: amsg) else {
            throw MediatorReflectedProcessorError.messageNotProcessed(message: omsg.loggingDescription)
        }
        processVoIPCallMessage(
            abstractMessage: amsg,
            voipMessage: msg,
            identity: receiverIdentity,
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        voipCallAnswerMessage amsg: BoxVoIPCallAnswerMessage
    ) throws -> Promise<Void> {
        let receiverIdentity = try getReceiverIdentity(for: omsg)
        guard let msg = VoIPCallMessageDecoder.decodeVoIPCallAnswer(from: amsg) else {
            throw MediatorReflectedProcessorError.messageNotProcessed(message: omsg.loggingDescription)
        }
        processVoIPCallMessage(
            abstractMessage: amsg,
            voipMessage: msg,
            identity: receiverIdentity,
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        voipCallIceCandidatesMessage amsg: BoxVoIPCallIceCandidatesMessage
    ) throws -> Promise<Void> {
        let receiverIdentity = try getReceiverIdentity(for: omsg)
        guard let msg = VoIPCallMessageDecoder.decodeVoIPCallIceCandidates(from: amsg) else {
            throw MediatorReflectedProcessorError.messageNotProcessed(message: omsg.loggingDescription)
        }
        processVoIPCallMessage(
            abstractMessage: amsg,
            voipMessage: msg,
            identity: receiverIdentity,
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        voipCallHangupMessage amsg: BoxVoIPCallHangupMessage
    ) throws -> Promise<Void> {
        let receiverIdentity = try getReceiverIdentity(for: omsg)
        guard let msg = VoIPCallMessageDecoder.decodeVoIPCallHangup(from: amsg, contactIdentity: receiverIdentity)
        else {
            throw MediatorReflectedProcessorError.messageNotProcessed(message: omsg.loggingDescription)
        }
        processVoIPCallMessage(
            abstractMessage: amsg,
            voipMessage: msg,
            identity: receiverIdentity,
            isOutgoing: true
        )
        return Promise()
    }

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        voipCallRingingMessage amsg: BoxVoIPCallRingingMessage
    ) throws -> Promise<Void> {
        let receiverIdentity = try getReceiverIdentity(for: omsg)
        guard let msg = VoIPCallMessageDecoder.decodeVoIPCallRinging(from: amsg, contactIdentity: receiverIdentity)
        else {
            throw MediatorReflectedProcessorError.messageNotProcessed(message: omsg.loggingDescription)
        }
        
        return processVoIPCallMessage(
            abstractMessage: amsg,
            voipMessage: msg,
            identity: receiverIdentity,
            isOutgoing: true
        )
    }

    private func processVoIPCallMessage(
        abstractMessage amsg: AbstractMessage,
        voipMessage: VoIPCallMessageProtocol,
        identity: String,
        isOutgoing: Bool
    ) -> Promise<Void> {
        Promise { seal in
            if !isOutgoing {
                messageProcessorDelegate.incomingMessageStarted(amsg)
            }

            messageProcessorDelegate.processVoIPCall(voipMessage as! NSObject, identity: identity) { delegate in
                if !isOutgoing {
                    if let delegate {
                        delegate.incomingMessageFinished(amsg)
                    }
                    else {
                        self.messageProcessorDelegate.incomingMessageFinished(amsg)
                    }
                }
                seal.fulfill_()
            } onError: { error, _ in
                seal.reject(error)
            }
        }
    }
    
    // MARK: Process reflected outgoing GroupCallStart messages

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupCallStartMessage amsg: GroupCallStartMessage
    ) throws -> Promise<Void> {
        
        try messageStore.save(
            groupCallStartMessage: amsg,
            senderIdentity: frameworkInjector.myIdentityStore.identity,
            createdAt: getCreatedAt(for: omsg),
            reflectedAt: reflectedAt,
            isOutgoing: true
        )
    }
    
    // MARK: Process Incoming Reaction Messages

    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        reactionMessage amsg: ReactionMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            reactionMessage: amsg,
            conversationIdentity: getReceiverIdentity(for: omsg),
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }
    
    private func process(
        outgoingMessage omsg: D2d_OutgoingMessage,
        groupReactionMessage amsg: GroupReactionMessage
    ) throws -> Promise<Void> {
        try messageStore.save(
            groupReactionMessage: amsg,
            senderIdentity: frameworkInjector.myIdentityStore.identity,
            createdAt: getCreatedAt(for: omsg),
            isOutgoing: true
        )
        return Promise()
    }

    // MARK: Misc

    private func getReceiverIdentity(for omsg: D2d_OutgoingMessage) throws -> String {
        try frameworkInjector.entityManager.performAndWait {
            guard let receiverIdentity = self.frameworkInjector.entityManager.entityFetcher
                .contact(for: omsg.conversation.contact)?.identity else {
                throw MediatorReflectedProcessorError.outgoingMessageReceiverNotFound(message: omsg.loggingDescription)
            }
            
            return receiverIdentity
        }
    }

    @discardableResult
    private func getGroup(for omsg: D2d_OutgoingMessage) throws -> (groupID: Data, groupCreatorIdentity: String) {
        try frameworkInjector.entityManager.performAndWait {
            guard let group = self.frameworkInjector.groupManager.getGroup(
                omsg.conversation.group.groupID.littleEndianData,
                creator: omsg.conversation.group.creatorIdentity
            ) else {
                throw MediatorReflectedProcessorError.groupNotFound(message: omsg.loggingDescription)
            }

            return (group.groupID, group.groupCreatorIdentity)
        }
    }

    private func getCreatedAt(for omsg: D2d_OutgoingMessage) -> Date {
        omsg.createdAt.date ?? .now
    }
}
