//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2024-2025 Threema GmbH
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
import ThreemaProtocols

extension MDMSetup {

    /// MD sync of setting one to one and group call, if MDM parameter 'th_disable_calls' or 'th_disable_group_calls' is
    /// set
    @objc func syncSettingCalls() {
        let businessInjector = BusinessInjector()

        guard AppSetup.isCompleted,
              businessInjector.userSettings.enableMultiDevice,
              existsMdmKey(MDM_KEY_DISABLE_CALLS) || existsMdmKey(MDM_KEY_DISABLE_GROUP_CALLS) else {
            return
        }

        businessInjector.settingsStoreInternal.syncSettingCalls()
    }

    /// MD sync of MDM parameter 'th_disable_add_contact'
    @objc func sync() {
        guard UserSettings.shared().enableMultiDevice,
              AppSetup.isCompleted
        else {
            return
        }

        _ = TaskManager().add(taskDefinition: TaskDefinitionMdmParameterSync(mdmParameters: mdmParameters()))
    }

    func mdmParameters() -> Sync_MdmParameters {
        var mdmParametersSync = Sync_MdmParameters()

        if let externalMdm = getCompanyMDM(),
           let parameterDisableAddContact = mdmParameterSyncBool(
               key: MDM_KEY_DISABLE_ADD_CONTACT,
               mdmParameters: externalMdm
           ) {
            mdmParametersSync.externalParameters[MDM_KEY_DISABLE_ADD_CONTACT] = parameterDisableAddContact
        }

        if let threemaMdm = getThreemaMDM(),
           let mdmParameters = threemaMdm[MDM_KEY_THREEMA_PARAMS] as? [AnyHashable: Any],
           let parameterDisableAddContact = mdmParameterSyncBool(
               key: MDM_KEY_DISABLE_ADD_CONTACT,
               mdmParameters: mdmParameters
           ) {
            mdmParametersSync.threemaParameters[MDM_KEY_DISABLE_ADD_CONTACT] = parameterDisableAddContact
        }

        return mdmParametersSync
    }

    private func mdmParameterSyncBool(key: String, mdmParameters: [AnyHashable: Any]) -> Sync_MdmParameters.Parameter? {
        guard let value = mdmParameters[key] as? Bool else {
            return nil
        }

        return Sync_MdmParameters.Parameter.with {
            $0.booleanValue = value
        }
    }
}
