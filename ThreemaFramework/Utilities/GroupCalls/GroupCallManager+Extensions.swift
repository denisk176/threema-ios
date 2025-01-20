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

import CocoaLumberjackSwift
import Foundation
import GroupCalls
import ThreemaEssentials

extension GroupCallManager {
    public func getGroupModel(for groupConversationManagedObjectID: NSManagedObjectID) async
        -> GroupCallThreemaGroupModel? {
        guard UserSettings.shared().enableThreemaGroupCalls else {
            DDLogVerbose("[GroupCall] GroupCalls are not enabled. Skip.")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let businessInjector = BusinessInjector()
            
            businessInjector.entityManager.performAndWait {
                guard let conversation = businessInjector.entityManager.entityFetcher
                    .getManagedObject(by: groupConversationManagedObjectID) as? ConversationEntity else {
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let group = businessInjector.groupManager.getGroup(conversation: conversation) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let groupIdentity = group.groupIdentity
                
                let groupModel = GroupCallThreemaGroupModel(
                    groupIdentity: groupIdentity,
                    groupName: group.name ?? ""
                )
                
                continuation.resume(returning: groupModel)
            }
        }
    }
}
