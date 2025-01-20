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

public final class SettingsBundleHelper: NSObject {
    fileprivate enum Keys {
        case safeMode
        case disableSentry
        
        var string: String {
            switch self {
            case .safeMode:
                "safe_mode_switch"
            case .disableSentry:
                "sentry_switch"
            }
        }
    }
    
    @objc public static var safeMode: Bool {
        UserDefaults.standard.bool(forKey: Keys.safeMode.string)
    }
    
    @objc public static var disableSentry: Bool {
        UserDefaults.standard.bool(forKey: Keys.disableSentry.string)
    }
    
    @objc public static func resetSafeMode() {
        UserDefaults.standard.set(false, forKey: Keys.safeMode.string)
    }
}
