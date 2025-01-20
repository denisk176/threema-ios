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

import SwiftProtobuf
import ThreemaProtocols
import XCTest
@testable import ThreemaFramework

class MediatorReflectedMessageEncoderDecoderTests: XCTestCase {

    private var frameworkInjectorMock: FrameworkInjectorProtocol!
    private var mediatorMessageProtocol: MediatorMessageProtocolProtocol!

    override func setUpWithError() throws {
        // Necessary for ValidationLogger
        AppGroup.setGroupID("group.ch.threema") // THREEMA_GROUP_IDENTIFIER @"group.ch.threema"

        frameworkInjectorMock = BusinessInjectorMock(
            entityManager: EntityManager()
        )

        mediatorMessageProtocol = MediatorMessageProtocol(deviceGroupKeys: MockData.deviceGroupKeys)
    }

    func testEncodeDecodeIncomingMessageAbstractText() throws {
        let expectedMessage = BoxTextMessage()
        expectedMessage.fromIdentity = "ECHOECHO"
        expectedMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.text = "Test text message"
        expectedMessage.nonce = MockData.generateMessageNonce()

        let testEnvelope = try getEnvelopeForIncomingMessage(abstractMessage: expectedMessage)

        let decoder = MediatorReflectedMessageDecoder(frameworkBusinessInjector: frameworkInjectorMock)
        let result = try? decoder.decode(
            incomingMessage: testEnvelope.incomingMessage,
            receivedAfterInitialQueueSend: true
        )

        let resultMessage = try XCTUnwrap(result as? BoxTextMessage)
        XCTAssertEqual(expectedMessage.type(), resultMessage.type())
        XCTAssertEqual(expectedMessage.messageID, resultMessage.messageID)
        XCTAssertEqual(expectedMessage.fromIdentity, resultMessage.fromIdentity)
        XCTAssertEqual(expectedMessage.toIdentity, resultMessage.toIdentity)
        XCTAssertEqual(expectedMessage.text, resultMessage.text)
        XCTAssertEqual(expectedMessage.nonce, resultMessage.nonce)
        XCTAssertTrue(resultMessage.receivedAfterInitialQueueSend)
    }

    func testEncodeDecodeIncomingMessageAbstractGroupCreate() throws {
        let expectedMessage = GroupCreateMessage()
        expectedMessage.fromIdentity = "MEMBER01"
        expectedMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        expectedMessage.groupCreator = "MEMBER01"
        expectedMessage.groupMembers = ["MEMBER01", "MEMBER02"]
        expectedMessage.nonce = MockData.generateMessageNonce()

        let testEnvelope = try getEnvelopeForIncomingMessage(abstractMessage: expectedMessage)

        let decoder = MediatorReflectedMessageDecoder(frameworkBusinessInjector: frameworkInjectorMock)
        let result = try? decoder.decode(
            incomingMessage: testEnvelope.incomingMessage,
            receivedAfterInitialQueueSend: false
        )

        let resultMessage = try XCTUnwrap(result as? GroupCreateMessage)
        XCTAssertEqual(expectedMessage.type(), resultMessage.type())
        XCTAssertEqual(expectedMessage.messageID, resultMessage.messageID)
        XCTAssertEqual(expectedMessage.fromIdentity, resultMessage.fromIdentity)
        XCTAssertEqual(expectedMessage.toIdentity, resultMessage.toIdentity)
        XCTAssertEqual(expectedMessage.groupID, resultMessage.groupID)
        XCTAssertEqual(expectedMessage.groupCreator, resultMessage.groupCreator)
        XCTAssertTrue(expectedMessage.groupMembers.elementsEqual(resultMessage.groupMembers, by: { e1, e2 in
            guard let e1 = e1 as? String, let e2 = e2 as? String else {
                return false
            }
            return e1 == e2
        }))
        XCTAssertEqual(expectedMessage.nonce, resultMessage.nonce)
        XCTAssertFalse(resultMessage.receivedAfterInitialQueueSend)
    }

    func testEncodeDecodeIncomingMessageAbstractGroupRequestSync() throws {
        let expectedMessage = GroupRequestSyncMessage()
        expectedMessage.fromIdentity = "MEMBER01"
        expectedMessage.toIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        expectedMessage.nonce = MockData.generateMessageNonce()

        let testEnvelope = try getEnvelopeForIncomingMessage(abstractMessage: expectedMessage)

        let decoder = MediatorReflectedMessageDecoder(frameworkBusinessInjector: frameworkInjectorMock)
        let result = try? decoder.decode(
            incomingMessage: testEnvelope.incomingMessage,
            receivedAfterInitialQueueSend: true
        )

        let resultMessage = try XCTUnwrap(result as? GroupRequestSyncMessage)
        XCTAssertEqual(expectedMessage.type(), resultMessage.type())
        XCTAssertEqual(expectedMessage.messageID, resultMessage.messageID)
        XCTAssertEqual(expectedMessage.fromIdentity, resultMessage.fromIdentity)
        XCTAssertEqual(expectedMessage.toIdentity, resultMessage.toIdentity)
        XCTAssertEqual(expectedMessage.groupID, resultMessage.groupID)
        XCTAssertEqual(frameworkInjectorMock.myIdentityStore.identity, resultMessage.groupCreator)
        XCTAssertEqual(expectedMessage.nonce, resultMessage.nonce)
        XCTAssertTrue(resultMessage.receivedAfterInitialQueueSend)
    }

    func testEncodeDecodeOutgoingMessageAbstractText() throws {
        let expectedMessage = BoxTextMessage()
        expectedMessage.fromIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.toIdentity = "ECHOECHO"
        expectedMessage.text = "Test text message"
        expectedMessage.nonce = MockData.generateMessageNonce()

        let testEnvelope = try getEnvelopeForOutgoingMessage(abstractMessage: expectedMessage)

        let decoder = MediatorReflectedMessageDecoder(frameworkBusinessInjector: frameworkInjectorMock)
        let result = try? decoder.decode(outgoingMessage: testEnvelope.outgoingMessage)

        let resultMessage = try XCTUnwrap(result as? BoxTextMessage)
        XCTAssertEqual(expectedMessage.type(), resultMessage.type())
        XCTAssertEqual(expectedMessage.messageID, resultMessage.messageID)
        XCTAssertEqual(expectedMessage.fromIdentity, resultMessage.fromIdentity)
        XCTAssertEqual(expectedMessage.toIdentity, resultMessage.toIdentity)
        XCTAssertEqual(expectedMessage.text, resultMessage.text)
    }

    func testEncodeDecodeOutgoingMessageAbstractGroupCreate() throws {
        let expectedMessage = GroupCreateMessage()
        expectedMessage.fromIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.toIdentity = "MEMBER01"
        expectedMessage.groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        expectedMessage.groupCreator = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.groupMembers = ["MEMBER01", "MEMBER02"]
        expectedMessage.nonce = MockData.generateMessageNonce()

        let testEnvelope = try getEnvelopeForOutgoingMessage(abstractMessage: expectedMessage)

        let decoder = MediatorReflectedMessageDecoder(frameworkBusinessInjector: frameworkInjectorMock)
        let result = try? decoder.decode(outgoingMessage: testEnvelope.outgoingMessage)

        let resultMessage = try XCTUnwrap(result as? GroupCreateMessage)
        XCTAssertEqual(expectedMessage.type(), resultMessage.type())
        XCTAssertEqual(expectedMessage.messageID, resultMessage.messageID)
        XCTAssertEqual(expectedMessage.fromIdentity, resultMessage.fromIdentity)
        XCTAssertEqual(expectedMessage.toIdentity, resultMessage.toIdentity)
        XCTAssertEqual(expectedMessage.groupID, resultMessage.groupID)
        XCTAssertEqual(expectedMessage.groupCreator, resultMessage.groupCreator)
        XCTAssertTrue(expectedMessage.groupMembers.elementsEqual(resultMessage.groupMembers, by: { e1, e2 in
            guard let e1 = e1 as? String, let e2 = e2 as? String else {
                return false
            }
            return e1 == e2
        }))
    }

    func testEncodeDecodeOutgoingMessageAbstractGroupRequestSync() throws {
        let expectedMessage = GroupRequestSyncMessage()
        expectedMessage.fromIdentity = frameworkInjectorMock.myIdentityStore.identity
        expectedMessage.toIdentity = "MEMBER01"
        expectedMessage.groupID = BytesUtility.generateRandomBytes(length: ThreemaProtocol.groupIDLength)!
        expectedMessage.nonce = MockData.generateMessageNonce()

        let testEnvelope = try getEnvelopeForOutgoingMessage(abstractMessage: expectedMessage)

        let decoder = MediatorReflectedMessageDecoder(frameworkBusinessInjector: frameworkInjectorMock)
        let result = try? decoder.decode(outgoingMessage: testEnvelope.outgoingMessage)

        let resultMessage = try XCTUnwrap(result as? GroupRequestSyncMessage)
        XCTAssertEqual(expectedMessage.type(), resultMessage.type())
        XCTAssertEqual(expectedMessage.messageID, resultMessage.messageID)
        XCTAssertEqual(expectedMessage.fromIdentity, resultMessage.fromIdentity)
        XCTAssertEqual(expectedMessage.toIdentity, resultMessage.toIdentity)
        XCTAssertEqual(expectedMessage.groupID, resultMessage.groupID)
        XCTAssertEqual("MEMBER01", resultMessage.groupCreator)
    }

    private func getEnvelopeForIncomingMessage(abstractMessage: AbstractMessage) throws -> D2d_Envelope {
        try mediatorMessageProtocol.getEnvelopeForIncomingMessage(
            type: Int32(abstractMessage.type()),
            body: abstractMessage.body(),
            messageID: abstractMessage.messageID.littleEndian(),
            senderIdentity: abstractMessage.fromIdentity,
            createdAt: abstractMessage.date,
            nonce: abstractMessage.nonce
        )
    }

    private func getEnvelopeForOutgoingMessage(abstractMessage: AbstractMessage) throws -> D2d_Envelope {
        try mediatorMessageProtocol.getEnvelopeForOutgoingMessage(
            type: Int32(abstractMessage.type()),
            body: abstractMessage.body(),
            messageID: abstractMessage.messageID.littleEndian(),
            receiverIdentity: abstractMessage.toIdentity,
            createdAt: abstractMessage.date,
            nonce: abstractMessage.nonce,
            deviceID: MockData.deviceID.paddedLittleEndian()
        )
    }
}
