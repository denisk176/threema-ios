//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2018-2024 Threema GmbH
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
import ThreemaMacros

class ThreemaWebSettingCell: UITableViewCell {
    @IBOutlet var titleLabel: UILabel?
    @IBOutlet var webClientSwitch: UISwitch?

    func setupCell() {
        titleLabel?.text = #localize("webClientSession_title")
        
        let mdmSetup = MDMSetup(setup: false)!
        if mdmSetup.existsMdmKey(MDM_KEY_DISABLE_WEB) {
            titleLabel?.isEnabled = !mdmSetup.disableWeb()
            webClientSwitch?.isEnabled = !mdmSetup.disableWeb()
            webClientSwitch?.isOn = !mdmSetup.disableWeb()
        }
        else {
            titleLabel?.isEnabled = true
            webClientSwitch?.isEnabled = true
            webClientSwitch?.isOn = UserSettings.shared().threemaWeb
        }
    }
}
