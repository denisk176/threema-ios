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

import ThreemaProtocols
import XCTest
@testable import ThreemaFramework

class MessageReceiverTests: XCTestCase {

    var deviceGroupKeys: DeviceGroupKeys!
    var deviceID: Data!

    var mediatorMessageProtocol: MediatorMessageProtocolProtocol!

    override func setUpWithError() throws {
        deviceGroupKeys = MockData.deviceGroupKeys
        deviceID = MockData.deviceID

        mediatorMessageProtocol = MediatorMessageProtocol(deviceGroupKeys: deviceGroupKeys)
    }

    func testRequestDevicesInfoMultiDeviceNotActivated() throws {
        let expec = expectation(description: "request devices info")

        var resultError: Error?

        let messageReceiver = MessageReceiver(
            serverConnector: ServerConnectorMock(),
            userSettings: UserSettingsMock(),
            mediatorMessageProtocol: mediatorMessageProtocol
        )
        messageReceiver.requestDevicesInfo(thisDeviceID: Data())
            .catch { error in
                resultError = error
                expec.fulfill()
            }

        wait(for: [expec], timeout: 6)

        let result = try XCTUnwrap(resultError as? MultiDeviceManagerError)
        XCTAssertTrue(result == .multiDeviceNotActivated)
    }

    func testRequestDevicesInfo() throws {
        let expectedOtherDeviceID: UInt64 = try MockData.deviceID.littleEndian()
        let expectedDeviceLabel = "Test-Device"
        let expectedAppVersion = "0.1"

        var expectedDeviceInfo = D2d_DeviceInfo()
        expectedDeviceInfo.label = expectedDeviceLabel
        expectedDeviceInfo.appVersion = expectedAppVersion

        var expectedAugmentedDeviceInfo = D2m_DevicesInfo.AugmentedDeviceInfo()
        expectedAugmentedDeviceInfo.deviceSlotExpirationPolicy = .persistent
        if let data = try? expectedDeviceInfo.serializedData(),
           let encryptedData = mediatorMessageProtocol.encryptByte(data: data, key: deviceGroupKeys.dgdik) {
            expectedAugmentedDeviceInfo.encryptedDeviceInfo = encryptedData
        }

        let expectedDevicesInfoData = mediatorMessageProtocol
            .encodeDevicesInfo(augmentedDeviceInfo: [expectedOtherDeviceID: expectedAugmentedDeviceInfo])!

        let serverConnectorMock = ServerConnectorMock(
            connectionState: .loggedIn,
            deviceID: deviceID,
            deviceGroupKeys: deviceGroupKeys
        )
        serverConnectorMock.reflectMessageClosure = { _ in
            serverConnectorMock.messageListenerDelegate?.messageReceived(
                listener: serverConnectorMock.messageListenerDelegate!,
                type: MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_DEVICE_INFO,
                data: expectedDevicesInfoData
            )
            return nil
        }

        let userSettingsMock = UserSettingsMock()
        userSettingsMock.enableMultiDevice = true

        let expec = expectation(description: "request devices info")

        var resultError: Error?
        var resultDevices: [DeviceInfo]?

        let messageReceiver = MessageReceiver(
            serverConnector: serverConnectorMock,
            userSettings: userSettingsMock,
            mediatorMessageProtocol: mediatorMessageProtocol
        )
        messageReceiver.requestDevicesInfo(thisDeviceID: serverConnectorMock.deviceID!)
            .done { devices in
                resultDevices = devices
                expec.fulfill()
            }
            .catch { error in
                resultError = error
                expec.fulfill()
            }

        wait(for: [expec], timeout: 6)

        XCTAssertNil(resultError)

        let result = try XCTUnwrap(resultDevices)
        XCTAssertEqual(1, result.count)
        XCTAssertEqual(expectedDeviceLabel, result.first?.label)
        XCTAssertEqual("\(expectedAppVersion) • ", result.first?.platformDetails)
        XCTAssertEqual(.unspecified, result.first?.platform)
    }

    func testRequestDropDeviceMultiDeviceNotActivated() throws {
        let expec = expectation(description: "request drop device")

        var resultError: Error?

        let messageReceiver = MessageReceiver(
            serverConnector: ServerConnectorMock(),
            userSettings: UserSettingsMock(),
            mediatorMessageProtocol: mediatorMessageProtocol
        )
        messageReceiver.requestDropDevice(device: DeviceInfo(
            deviceID: 1,
            label: "Test-Device",
            lastLoginAt: Date(),
            badge: nil,
            platform: .unspecified,
            platformDetails: nil
        ))
        .catch { error in
            resultError = error
            expec.fulfill()
        }

        wait(for: [expec], timeout: 6)

        let result = try XCTUnwrap(resultError as? MultiDeviceManagerError)
        XCTAssertTrue(result == .multiDeviceNotActivated)
    }

    func testRequestDropDevice() throws {
        let expectedDropDeviceAck = Data(
            bytes: [MediatorMessageProtocol.MediatorMessageType.dropDeviceAck.rawValue, 0x00, 0x00, 0x00],
            count: 4
        )

        let serverConnectorMock = ServerConnectorMock(
            connectionState: .loggedIn,
            deviceID: deviceID,
            deviceGroupKeys: deviceGroupKeys
        )
        serverConnectorMock.reflectMessageClosure = { _ in
            serverConnectorMock.messageListenerDelegate?.messageReceived(
                listener: serverConnectorMock.messageListenerDelegate!,
                type: MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_DROP_DEVICE_ACK,
                data: expectedDropDeviceAck
            )
            return nil
        }
        
        let userSettingsMock = UserSettingsMock()
        userSettingsMock.enableMultiDevice = true

        let expec = expectation(description: "request drop device")

        var resultError: Error?

        let messageReceiver = MessageReceiver(
            serverConnector: serverConnectorMock,
            userSettings: userSettingsMock,
            mediatorMessageProtocol: mediatorMessageProtocol
        )
        messageReceiver.requestDropDevice(device: DeviceInfo(
            deviceID: 0,
            label: "Test-Device",
            lastLoginAt: Date(),
            badge: nil,
            platform: .unspecified,
            platformDetails: nil
        ))
        .done {
            expec.fulfill()
        }
        .catch { error in
            resultError = error
            expec.fulfill()
        }

        wait(for: [expec], timeout: 6)

        XCTAssertNil(resultError)
    }
}
