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

enum SingleDetails {
    
    enum State {
        case contactDetails(contact: ContactEntity)
        case conversationDetails(contact: ContactEntity, conversation: ConversationEntity)
    }
    
    enum Section {
        case contentActions
        case contactInfo
        case groups
        case notifications
        case shareAction
        case contactActions
        case privacySettings
        case wallpaper
        case fsActions
        case debugInfo
    }
    
    enum Row: Hashable {
        
        // General
        case action(_ action: Details.Action)
        case booleanAction(_ action: Details.BooleanAction)
        case value(label: String, value: String)
        
        // Contact info
        case verificationLevel(contact: ContactEntity)
        case publicKey
        
        case linkedContact(_ linkedContactManager: LinkedContactManager)
        
        // Groups
        case group(_ group: Group)
        
        // Notifications
        case doNotDisturb(action: Details.Action, contact: ContactEntity)
        
        // Privacy Settings
        case privacySettings(action: Details.Action, contact: ContactEntity)
        
        // Wallpaper
        case wallpaper(action: Details.Action, isDefault: Bool)
        
        // Debug
        case coreDataDebugInfo(contact: ContactEntity)
        case fsDebugInfo(sessionInfo: String)
    }
}
