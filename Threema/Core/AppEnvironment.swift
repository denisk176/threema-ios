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

import ThreemaFramework

public struct AppEnvironment {
    @NotificationPublisher(Notification.Name(kNotificationColorThemeChanged))
    var colorChanged
    
    @NotificationPublisher(Notification.Name(kShowNotificationSettings))
    var showNotificationSettings
    
    @NotificationPublisher(.showDesktopSettings)
    var showDesktopSettings
    
    @NotificationPublisher(Notification.Name(kNotificationSettingStoreSynchronization))
    var mdmChanged
    
    @NotificationPublisher(.navigateSafeSetup)
    var showSafeSetup
    
    @NotificationPublisher(.incomingProfileSync)
    var profileSyncPublisher
    
    @NotificationPublisher(.identityLinkedWithMobileNo)
    var identityLinked
    
    @NotificationPublisher(UIApplication.willEnterForegroundNotification)
    var enteredForeground
    
    @NotificationPublishedState(
        Notification
            .Name(kNotificationNavigationBarColorShouldChange)
    )
    var notificationBarColorShouldChange
    
    @NotificationPublishedState(
        Notification
            .Name(kNotificationNavigationItemPromptShouldChange)
    )
    var notificationBarItemPromptShouldChange
    
    var businessInjector: BusinessInjectorProtocol
    var connectionStateProvider = ConnectionStateProvider()
}
