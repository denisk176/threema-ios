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

import Foundation
import ThreemaEssentials
import ThreemaProtocols

/// Protocol that allows delegation from the `GroupCallManager` to the `GlobalGroupCallManagerSingleton`
public protocol GroupCallManagerSingletonDelegate: AnyObject {
    /// Tries to present the given `GroupCallViewController`
    /// - Parameter viewController: `GroupCallViewController` to be shown
    nonisolated func showGroupCallViewController(viewController: GroupCallViewController)
    
    /// Used to provide `GroupCallBannerButtonUpdate`s to the UI-elements
    /// - Parameter groupCallBannerButtonUpdate: `GroupCallBannerButtonUpdate` containing the update info
    nonisolated func updateGroupCallButtonsAndBanners(groupCallBannerButtonUpdate: GroupCallBannerButtonUpdate)
    
    func sendStartCallMessage(_ wrappedMessage: WrappedGroupCallStartMessage) async throws
    
    /// Used to show a notification for the new incoming group call
    /// - Parameters:
    ///   - groupModel: GroupCallThreemaGroupModel
    ///   - senderThreemaID: The threema id of the sender
    nonisolated func showIncomingGroupCallNotification(
        groupModel: GroupCallThreemaGroupModel,
        senderThreemaID: ThreemaIdentity
    )
    
    /// Shows an alert that the group call is currently full
    /// - Parameter maxParticipants: Optional maximal participant count
    /// - Parameter onOK: Block to be executed when `OK` is pressed
    nonisolated func showGroupCallFullAlert(maxParticipants: Int?, onOK: @escaping () -> Void)
}
