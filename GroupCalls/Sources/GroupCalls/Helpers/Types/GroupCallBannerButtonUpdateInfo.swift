//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2023-2025 Threema GmbH
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

public struct GroupCallBannerButtonUpdate: Sendable {
    public let groupIdentity: GroupIdentity
    public let numberOfParticipants: Int
    // TODO: (IOS-4074) Make optional and possibly hide label in banner?
    public let startDate: Date
    public let joinState: GroupCallJoinState
    public let hideComponent: Bool
    
    init(actor: GroupCallActor, hideComponent: Bool) async {
        self.groupIdentity = actor.group.groupIdentity
        self.numberOfParticipants = await actor.numberOfJoinedParticipants()
        self.startDate = await actor.callStartDate()
        self.joinState = await actor.joinState()
        self.hideComponent = hideComponent
    }
}
