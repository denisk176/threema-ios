//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2018-2022 Threema GmbH
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

import Foundation
import PromiseKit
@testable import ThreemaFramework

class MultiDeviceManagerMock: MultiDeviceManagerProtocol {
    var maximumNumberOfDeviceSlots: Int? {
        nil
    }
    
    var thisDevice: DeviceInfo {
        DeviceInfo(
            deviceID: 0,
            label: "Unit test devie name",
            lastLoginAt: Date(),
            badge: "badge",
            platform: .ios,
            platformDetails: "iOS platform details"
        )
    }
    
    func sortedOtherDevices() async throws -> [ThreemaFramework.DeviceInfo] {
        []
    }

    func otherDevices() -> Promise<[DeviceInfo]> {
        Promise { seal in seal.fulfill([]) }
    }
    
    func drop(device: DeviceInfo) async throws {
        // no-op
    }

    func drop(device: DeviceInfo) -> Promise<Void> {
        Promise()
    }
    
    func disableMultiDevice() async throws {
        // no-op
    }
}
