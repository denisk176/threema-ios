//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2022-2024 Threema GmbH
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
import ThreemaFramework
import ThreemaMacros

public protocol NotificationManagerProtocol {
    func updateUnreadMessagesCount()
    func updateUnreadMessagesCount(baseMessage: BaseMessage?)
}

@objc class NotificationManager: NSObject, NotificationManagerProtocol {
    
    @objc var firstPushHandled = false
    
    private static var receivedMessageSound: SystemSoundID = 0
    private static var lastReceivedMessageSound = CFTimeInterval(0)

    private let webClientKey = "3mw"
    private let webClientSessionKey = "wcs"
    private let webClientVersionKey = "wcv"
    private let webClientAuthKey = "wca"
    private let availableCheckKey = "alive-check"
    private let pushTestKey = "push-test"
    
    private let businessInjector: BusinessInjectorProtocol
    
    required init(
        businessInjector: BusinessInjectorProtocol
    ) {
        self.businessInjector = businessInjector
        
        // Get sounds ready
        let soundPath = BundleUtil.path(forResource: "received_message", ofType: "caf")
        let baseURL = URL(fileURLWithPath: soundPath!) as CFURL
        AudioServicesCreateSystemSoundID(baseURL, &NotificationManager.receivedMessageSound)
    }
    
    @objc override convenience init() {
        self.init(
            businessInjector: BusinessInjector()
        )
    }
    
    final func updateTabBarBadge(badgeTotalCount: Int) {
        Task { @MainActor in
            if let mainTabBar = AppDelegate.getMainTabBarController(),
               let item = mainTabBar.tabBar.items?[Int(kChatTabBarIndex)] {
                item.badgeValue = badgeTotalCount > 0 ? String(badgeTotalCount) : nil
            }
            UIApplication.shared.applicationIconBadgeNumber = badgeTotalCount
        }
    }

    /// Update badge with unread messages count.
    @objc final func updateUnreadMessagesCount() {
        updateUnreadMessagesCount(baseMessage: nil)
    }

    /// Update badge with unread messages count.
    /// - Parameter baseMessage: Recalculate unread messages count for underlying conversation
    @objc final func updateUnreadMessagesCount(baseMessage: BaseMessage?) {
        // Calc and update unread messages badge in background
        Task {
            await businessInjector.runInBackground { backgroundBusinessInjector in
                let badgeTotalCount = await backgroundBusinessInjector.entityManager.perform {
                    let unreadMessages = backgroundBusinessInjector.unreadMessages
                    var totalCount = 0

                    if let baseMessageObjectID = baseMessage?.objectID,
                       let localBaseMessage = backgroundBusinessInjector.entityManager.entityFetcher
                       .existingObject(with: baseMessageObjectID) as? BaseMessage,
                       let conversation = localBaseMessage.conversation {
                        totalCount = unreadMessages.totalCount(doCalcUnreadMessagesCountOf: [conversation])
                    }
                    else {
                        totalCount = unreadMessages.totalCount()
                    }

                    return totalCount
                }

                NotificationCenter.default.post(
                    name: NSNotification.Name(rawValue: kNotificationMessagesCountChanged),
                    object: nil,
                    userInfo: [kKeyUnread: badgeTotalCount]
                )

                self.updateTabBarBadge(badgeTotalCount: badgeTotalCount)
            }
        }
    }

    // This does not necessarily operate on the original push payload from the server (nor its decrypted version)
    @objc func handleThreemaNotification(
        payload: [AnyHashable: Any],
        receivedWhileRunning: Bool,
        notification: UNNotification? = nil,
        withCompletionHandler completionHandler: ((_ options: UNNotificationPresentationOptions) -> Void)? = nil
    ) {
        if let webPayload = payload[webClientKey] as? [AnyHashable: Any] {
            handleWebClientNotification(webPayload: webPayload, withCompletionHandler: completionHandler)
        }
        else {
            DDLogVerbose("[Push] remote notification: \(payload), while running: \(receivedWhileRunning)")
            
            guard let threemaPayload = PushPayloadDecryptor
                .decryptPushPayload(payload[ThreemaPushNotificationDictionary.key.rawValue] as? [String: Any])
            else {
                DDLogError("[Push] Missing information to handle notification")
                completionHandler?([])
                return
            }
            
            if !receivedWhileRunning {
                if let from = threemaPayload["from"] as? String,
                   let contact = businessInjector.entityManager.entityFetcher.contact(for: from),
                   let cmd = threemaPayload["cmd"] as? String {
                    var info: [AnyHashable: Any]?
                    if cmd == "newmsg" || cmd == "missedcall" {
                        // New message push - switch to appropriate conversation
                        info = [
                            kKeyContact: contact,
                            kKeyForceCompose: true,
                        ] as [String: Any]
                    }
                    else if cmd == "newgroupmsg" {
                        // Try to find an appropriate group - if there is only one conversation in which
                        // the sender is a member, then it must be the right one. If there are more we cannot know.
                        // In the regular case we get the groupID and groupCreator anyways
                        if let groupIDString = threemaPayload["groupId"] as? String,
                           let groupID = Data(base64Encoded: groupIDString),
                           let groupCreator = threemaPayload["groupCreator"] as? String,
                           let conversation = businessInjector.entityManager.entityFetcher.conversationEntity(
                               for: groupID,
                               creator: groupCreator
                           ) {
                            info = [
                                kKeyConversation: conversation,
                                kKeyForceCompose: true,
                            ] as [String: Any]
                        }
                        else {
                            if let groups = businessInjector.entityManager.entityFetcher
                                .conversations(forMember: contact) as? [ConversationEntity],
                                groups.count == 1 {
                                info = [
                                    kKeyConversation: groups.first!,
                                    kKeyForceCompose: true,
                                ] as [String: Any]
                            }
                            else {
                                DDLogError(
                                    "We do not have a groupID in this notification, don't attempt to guess the correct chat and do nothing instead"
                                )
                            }
                        }
                    }
                    
                    if let info {
                        DispatchQueue.main.async {
                            if !self.firstPushHandled {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name(rawValue: kNotificationShowConversation),
                                    object: nil,
                                    userInfo: info
                                )
                                self.firstPushHandled = true
                            }
                        }
                    }
                    else {
                        DDLogError("Could not open chat from notification due to an unknown error.")
                    }
                }
                completionHandler?([])
            }
            else if let availableCheck = threemaPayload[availableCheckKey] as? Bool,
                    availableCheck {
                completionHandler?([])
            }
            else if let pushTestCheck = threemaPayload[pushTestKey] as? Bool,
                    pushTestCheck {
                completionHandler?([
                    UNNotificationPresentationOptions.list,
                    UNNotificationPresentationOptions.banner,
                    UNNotificationPresentationOptions.badge,
                    UNNotificationPresentationOptions.sound,
                ])
            }
            else if let key = payload["key"] as? String,
                    key == "safe-backup-notification",
                    let notification {
                UIAlertTemplate.showAlert(
                    owner: AppDelegate.shared().currentTopViewController(),
                    title: notification.request.content.title,
                    message: notification.request.content.body,
                    actionOk: nil
                )
                completionHandler?([])
            }
            else {
                completionHandler?([])
            }
        }
    }
    
    @objc func handleVoipPush(
        payload: [AnyHashable: Any],
        withCompletionHandler completionHandler: @escaping (
            (_ isThreemaDict: Bool, _ payload: [AnyHashable: Any]?)
                -> Void
        )
    ) {
        guard !businessInjector.myIdentityStore.isKeychainLocked() else {
            if payload["threema"] != nil {
                NotificationManager.showNoAccessToDatabaseNotification {
                    exit(0)
                }
            }
            // The keychain is locked; we cannot proceed. The UI will show the ProtectedDataUnavailable screen
            // at this point. To prevent this screen from appearing when the user unlocks their device after we
            // have processed the push, we exit now so that the process will restart after the device is unlocked.
            completionHandler(false, nil)
            return
        }
        if payload["NotificationExtensionOffer"] != nil {
            DatabaseManager.db().refreshDirtyObjects(true)
            
            if ServerConnector.shared().connectionState == .disconnected {
                ServerConnector.shared().isAppInBackground = AppDelegate.shared().isAppInBackground()
                ServerConnector.shared().connectWait(initiator: .threemaCall)
                completionHandler(false, nil)
            }
            return
        }
        
        loadVoIPMessages(payload: payload, withCompletionHandler: completionHandler)
    }
    
    func loadVoIPMessages(
        payload: [AnyHashable: Any],
        withCompletionHandler completionHandler: @escaping (
            (_ isThreemaDict: Bool, _ payload: [AnyHashable: Any]?)
                -> Void
        )
    ) {
        guard let threemaPayload = PushPayloadDecryptor
            .decryptPushPayload(payload[ThreemaPushNotificationDictionary.key.rawValue] as? [AnyHashable: Any]) else {
            DDLogError("[Push] Missing information to show notification")
            completionHandler(false, payload)
            return
        }
        
        // swiftformat:disable:next acronyms
        let messageID = threemaPayload[ThreemaPushNotificationDictionary.messageIDKey]
        let senderID = threemaPayload[ThreemaPushNotificationDictionary.fromKey]
        
        DDLogInfo("[Push] Received VoIP Push Notification for \(messageID ?? "?") from \(senderID ?? "?")")
        
        DatabaseManager.db().refreshDirtyObjects(true)
        
        if ServerConnector.shared().connectionState == .disconnected {
            ServerConnector.shared().isAppInBackground = AppDelegate.shared().isAppInBackground()
            ServerConnector.shared().connectWait(initiator: .threemaCall)
        }
        completionHandler(true, threemaPayload)
    }
    
    func playReceivedMessageSound() {
        let curTime = CACurrentMediaTime()
        
        // play sound only twice per second
        if curTime - NotificationManager.lastReceivedMessageSound > 0.5 {
            if UserSettings.shared().inAppSounds,
               UserSettings.shared().inAppVibrate {
                AudioServicesPlayAlertSound(NotificationManager.receivedMessageSound)
            }
            else if UserSettings.shared().inAppSounds {
                AudioServicesPlaySystemSound(NotificationManager.receivedMessageSound)
            }
            else if UserSettings.shared().inAppVibrate {
                AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
            }
        }
        NotificationManager.lastReceivedMessageSound = curTime
    }
}

extension NotificationManager {
    @objc final class func showNoAccessToDatabaseNotification(completionHandler: @escaping () -> Void) {
        let title = #localize("new_message_no_access_title")
        let message = String.localizedStringWithFormat(
            #localize("new_message_no_access_message"),
            ThreemaApp.currentName
        )
        ThreemaUtilityObjC.sendErrorLocalNotification(title, body: message, userInfo: nil) {
            ThreemaUtilityObjC.wait(forSeconds: 2, finish: completionHandler)
        }
    }
    
    final class func showNoMicrophonePermissionNotification() {
        let title = #localize("call_voip_not_supported_title")
        let message = String.localizedStringWithFormat(
            #localize("alert_no_access_message_microphone"),
            ThreemaApp.currentName
        )
        ThreemaUtilityObjC.sendErrorLocalNotification(title, body: message, userInfo: nil)
    }
}

extension NotificationManager {
    private func wait(for seconds: Int, finish: @escaping (() -> Void)) {
        if seconds > 0,
           AppGroup.getActiveType() == AppGroupTypeApp {
            let deadlineTime = DispatchTime.now() + .seconds(seconds)
            DispatchQueue.main.asyncAfter(deadline: deadlineTime) {
                self.wait(for: seconds - 1, finish: finish)
            }
        }
        else {
            finish()
        }
    }
    
    static func showThreemaWebError(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else {
            UIAlertTemplate.showAlert(
                owner: AppDelegate.shared().currentTopViewController(),
                title: title,
                message: body,
                actionOk: nil
            )
            return
        }
        let notification = UNMutableNotificationContent()
        notification.title = title
        notification.body = body
        
        if UserSettings.shared().pushSound != "none" {
            notification
                .sound =
                UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(UserSettings.shared().pushSound!).caf"))
        }
        
        let request = UNNotificationRequest(identifier: "ThreemaWebError", content: notification, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    private func handleWebClientNotification(
        webPayload: [AnyHashable: Any],
        withCompletionHandler completionHandler: ((_ options: UNNotificationPresentationOptions) -> Void)? = nil
    ) {
        var currentSession: WebClientSessionEntity?
        
        if let hash = webPayload[webClientSessionKey] as? String {
            currentSession = WebClientSessionStore.shared.webClientSessionForHash(hash)
        }
        
        guard let currentSession else {
            ValidationLogger.shared().logString("[ThreemaWeb] Unknown session try to connect; Session blocked")
            completionHandler?([])
            return
        }
        
        let protocolVersion = webPayload[webClientVersionKey] as? Int
        
        guard let protocolVersion,
              let sessionVersion = currentSession.version,
              sessionVersion.intValue >= protocolVersion else {
            NotificationManager.showThreemaWebError(
                title: #localize("webClientSession_error_updateApp_title"),
                body: #localize("webClientSession_error_updateApp_message")
            )
            completionHandler?([])
            return
        }
        
        guard !currentSession.selfHosted.boolValue else {
            NotificationManager.showThreemaWebError(
                title: #localize("webClientSession_error_updateServer_title"),
                body: #localize("webClientSession_error_updateServer_message")
            )
            completionHandler?([])
            return
        }
        
        guard sessionVersion.intValue == protocolVersion else {
            NotificationManager.showThreemaWebError(
                title: #localize("webClientSession_error_wrongVersion_title"),
                body: #localize("webClientSession_error_wrongVersion_message")
            )
            completionHandler?([])
            return
        }
        
        WCSessionManager.shared.connect(
            authToken: nil,
            wca: webPayload[webClientAuthKey] as? String,
            webClientSession: currentSession
        )
        DatabaseManager.db().refreshDirtyObjects(false)
        
        completionHandler?([])
    }
}
