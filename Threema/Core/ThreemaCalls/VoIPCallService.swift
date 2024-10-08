//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2024 Threema GmbH
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
import Intents
import ThreemaEssentials
import ThreemaFramework

protocol VoIPCallServiceDelegate: AnyObject {
    func callServiceFinishedProcess()
}

class VoIPCallService: NSObject {
    
    private let voIPCallSender: VoIPCallSender
    
    private let kIncomingCallTimeout = 60.0
    private let kCallFailedTimeout = 10.0
    private let kEndedDelay = 5.0
    
    @objc public enum CallState: Int, RawRepresentable, Equatable {
        case idle
        case sendOffer
        case receivedOffer
        case outgoingRinging
        case incomingRinging
        case sendAnswer
        case receivedAnswer
        case initializing
        case calling
        case reconnecting
        case ended
        case remoteEnded
        case rejected
        case rejectedBusy
        case rejectedTimeout
        case rejectedDisabled
        case rejectedOffHours
        case rejectedUnknown
        case microphoneDisabled
        
        var active: Bool {
            self != .idle
        }
        
        /// Return the string of the current state for the ValidationLogger
        /// - Returns: String of the current state
        func description() -> String {
            switch self {
            case .idle: "IDLE"
            case .sendOffer: "SENDOFFER"
            case .receivedOffer: "RECEIVEDOFFER"
            case .outgoingRinging: "RINGING"
            case .incomingRinging: "RINGING"
            case .sendAnswer: "SENDANSWER"
            case .receivedAnswer: "RECEIVEDANSWER"
            case .initializing: "INITIALIZING"
            case .calling: "CALLING"
            case .reconnecting: "RECONNECTING"
            case .ended: "ENDED"
            case .remoteEnded: "REMOTEENDED"
            case .rejected: "REJECTED"
            case .rejectedBusy: "REJECTEDBUSY"
            case .rejectedTimeout: "REJECTEDTIMEOUT"
            case .rejectedDisabled: "REJECTEDDISABLED"
            case .rejectedOffHours: "REJECTEDOFFHOURS"
            case .rejectedUnknown: "REJECTEDUNKNOWN"
            case .microphoneDisabled: "MICROPHONEDISABLED"
            }
        }
        
        /// Get the localized string for the current state
        /// - Returns: Current localized call state string
        func localizedString() -> String {
            switch self {
            case .idle: BundleUtil.localizedString(forKey: "call_status_idle")
            case .sendOffer: BundleUtil.localizedString(forKey: "call_status_wait_ringing")
            case .receivedOffer: BundleUtil.localizedString(forKey: "call_status_wait_ringing")
            case .outgoingRinging: BundleUtil.localizedString(forKey: "call_status_ringing")
            case .incomingRinging: BundleUtil.localizedString(forKey: "call_status_incom_ringing")
            case .sendAnswer: BundleUtil.localizedString(forKey: "call_status_ringing")
            case .receivedAnswer: BundleUtil.localizedString(forKey: "call_status_ringing")
            case .initializing: BundleUtil.localizedString(forKey: "call_status_initializing")
            case .calling: BundleUtil.localizedString(forKey: "call_status_calling")
            case .reconnecting: BundleUtil.localizedString(forKey: "call_status_reconnecting")
            case .ended: BundleUtil.localizedString(forKey: "call_end")
            case .remoteEnded: BundleUtil.localizedString(forKey: "call_end")
            case .rejected: BundleUtil.localizedString(forKey: "call_rejected")
            case .rejectedBusy: BundleUtil.localizedString(forKey: "call_rejected_busy")
            case .rejectedTimeout: BundleUtil.localizedString(forKey: "call_rejected_timeout")
            case .rejectedDisabled: BundleUtil.localizedString(forKey: "call_rejected_disabled")
            case .rejectedOffHours: BundleUtil.localizedString(forKey: "call_rejected")
            case .rejectedUnknown: BundleUtil.localizedString(forKey: "call_rejected")
            case .microphoneDisabled: BundleUtil.localizedString(forKey: "call_mic_access")
            }
        }
    }
    
    weak var delegate: VoIPCallServiceDelegate?
    
    private var peerConnectionClient: VoIPCallPeerConnectionClientProtocol
    private var callKitManager: VoIPCallKitManager?
    private var threemaVideoCallAvailable = false
    private var callViewController: CallViewController?

    private var state: CallState = .idle {
        didSet {
            invalidateTimers(state: state)
            callViewController?.voIPCallStatusChanged(state: state, oldState: oldValue)
            handleLocalNotification()
            switch state {
            case .idle:
                localAddedIceCandidates.removeAll()
                localRelatedAddresses.removeAll()
                receivedIcecandidatesMessages.removeAll()
            case .initializing:
                handleLocalIceCandidates([])
            default:
                // do nothing
                break
            }
            addCallMessageToConversation(oldCallState: oldValue)
            handleTones(state: state, oldState: oldValue)
        }
    }

    private var audioPlayer: AVAudioPlayer?
    private var contactIdentity: String?
    private var callID: VoIPCallID?
    private var alreadyAccepted = false {
        didSet {
            callViewController?.alreadyAccepted = alreadyAccepted
        }
    }

    private var callInitiator = false {
        didSet {
            callViewController?.isCallInitiator = callInitiator
        }
    }

    private var audioMuted = false
    private var speakerActive = false
    private var videoActive = false
    private var isReceivingVideo = false {
        didSet {
            if callViewController != nil {
                callViewController?.isReceivingRemoteVideo = isReceivingVideo
            }
        }
    }

    private var shouldShowCellularCallWarning = false {
        didSet {
            if let callViewController {
                DDLogDebug(
                    "VoipCallService: [cid=\(callID?.callID ?? 0)]: Should show cellular warning -> \(shouldShowCellularCallWarning)"
                )
                callViewController.shouldShowCellularCallWarning = shouldShowCellularCallWarning
            }
        }
    }
    
    private var initCallTimeoutTimer: Timer?
    private var incomingCallTimeoutTimer: Timer?
    private var callDurationTimer: Timer?
    private var callDurationTime = 0
    private var callFailedTimer: Timer?
    private var transportExpectedStableTimer: Timer?
    
    private var incomingOffer: VoIPCallOfferMessage?
    
    private var iceCandidatesLockQueue = DispatchQueue(label: "VoIPCallIceCandidatesLockQueue")
    private var iceCandidatesTimer: Timer?
    private var localAddedIceCandidates = [RTCIceCandidate]()
    private var localRelatedAddresses: Set<String> = []
    private var receivedIceCandidatesLockQueue = DispatchQueue(label: "VoIPCallReceivedIceCandidatesLockQueue")
    private var receivedIcecandidatesMessages = [VoIPCallIceCandidatesMessage]()
    private var receivedUnknowCallIcecandidatesMessages = [String: [VoIPCallIceCandidatesMessage]]()
    
    private var localRenderer: RTCVideoRenderer?
    private var remoteRenderer: RTCVideoRenderer?
    
    private var reconnectingTimer: Timer?
    private var peerWasConnected = false
    
    private var isModal: Bool {
        // Check whether our callViewController is currently in the state presented modally
        let a = callViewController?.presentingViewController?.presentedViewController == callViewController
        // Check whether our callViewController has a navigationController
        let b1 = callViewController?.navigationController != nil
        // Check whether our callViewController is in the state presented modally as part of a navigation controller
        let b2 = callViewController?.navigationController?.presentingViewController?
            .presentedViewController == callViewController?.navigationController
        let b = b1 && b2
        // Check whether our callViewController has a tabbarcontroller which has a tabbarcontroller. Nesting two
        // tabBarControllers is only possible in the state presented modally
        let c = callViewController?.tabBarController?.presentingViewController is UITabBarController
        return a || b || c
    }
    
    private var audioRouteChangeObserver: NSObjectProtocol?

    private let businessInjector: BusinessInjectorProtocol

    required init(
        businessInjector: BusinessInjectorProtocol,
        peerConnectionClient: VoIPCallPeerConnectionClientProtocol
    ) {
        self.businessInjector = businessInjector
        self.voIPCallSender = VoIPCallSender(
            messageSender: businessInjector.messageSender,
            myIdentityStore: businessInjector.myIdentityStore
        )
        self.peerConnectionClient = peerConnectionClient
        super.init()
        
        self.audioRouteChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] n in
            guard let self else {
                return
            }
            if state != .idle {
                var isBluetoothAvailable = false
                if let inputs = AVAudioSession.sharedInstance().availableInputs {
                    for input in inputs {
                        if input.portType == AVAudioSession.Port.bluetoothA2DP || input.portType == AVAudioSession.Port
                            .bluetoothHFP || input.portType == AVAudioSession.Port.bluetoothLE {
                            isBluetoothAvailable = true
                        }
                    }
                }
                guard let info = n.userInfo,
                      let value = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: value) else {
                    return
                }
                
                switch reason {
                case .categoryChange:
                    let currentRoute = AVAudioSession.sharedInstance().currentRoute
                    
                    for output in currentRoute.outputs {
                        switch output.portType {
                        case .builtInReceiver:
                            if isBluetoothAvailable {
                                self.speakerActive = false
                                try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                            }
                            if speakerActive {
                                try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                            }
                        case .builtInSpeaker:
                            if isBluetoothAvailable {
                                self.speakerActive = true
                                try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                            }
                            if !speakerActive {
                                try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                            }
                        case .headphones:
                            try? AVAudioSession.sharedInstance()
                                .overrideOutputAudioPort(speakerActive ? .speaker : .none)
                        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                            break
                        default: break
                        }
                    }
                default: break
                }
            }
        }
    }
    
    deinit {
        if let observer = audioRouteChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override convenience init() {
        self.init(businessInjector: BusinessInjector(), peerConnectionClient: VoIPCallPeerConnectionClient())
    }
}

extension VoIPCallService {
    // MARK: Public functions
    
    /// Start process to handle the message
    /// - parameter element: Message
    func startProcess(element: Any) {
        if let action = element as? VoIPCallUserAction {
            switch action.action {
            case .call:
                if ProcessInfoHelper.isRunningForScreenshots {
                    callInitiator = true
                    contactIdentity = action.contactIdentity
                    presentCallViewController()
                    delegate?.callServiceFinishedProcess()
                    action.completion?()
                    return
                }
                
                startCallAsInitiator(action: action, completion: {
                    self.delegate?.callServiceFinishedProcess()
                    action.completion?()
                    
                })
            case .callWithVideo:
                startCallAsInitiator(action: action, completion: {
                    self.delegate?.callServiceFinishedProcess()
                    action.completion?()
                })
            case .accept, .acceptCallKit:
                alreadyAccepted = true
                acceptIncomingCall(action: action) {
                    self.delegate?.callServiceFinishedProcess()
                    action.completion?()
                }
            case .reject, .rejectDisabled, .rejectTimeout, .rejectBusy, .rejectOffHours, .rejectUnknown:
                rejectCall(action: action)
                delegate?.callServiceFinishedProcess()
                action.completion?()
            case .end:
                if ProcessInfoHelper.isRunningForScreenshots {
                    dismissCallView()
                    delegate?.callServiceFinishedProcess()
                    action.completion?()
                    return
                }
                DDLogNotice("Threema call: HangupBug -> Send hangup for end action")
                if state == .sendOffer || state == .outgoingRinging || state == .sendAnswer || state ==
                    .receivedAnswer ||
                    state == .initializing || state == .calling || state == .reconnecting {
                    RTCAudioSession.sharedInstance().isAudioEnabled = false
                    let hangupMessage = VoIPCallHangupMessage(
                        contactIdentity: action.contactIdentity,
                        callID: action.callID!,
                        completion: nil
                    )
                    voIPCallSender.sendVoIPCallHangup(hangupMessage: hangupMessage)
                    state = .ended
                    callKitManager?.endCall()
                    dismissCallView()
                    disconnectPeerConnection()
                }
                delegate?.callServiceFinishedProcess()
                action.completion?()
            case .speakerOn:
                speakerActive = true
                peerConnectionClient.speakerOn()
                delegate?.callServiceFinishedProcess()
                action.completion?()
            case .speakerOff:
                speakerActive = false
                peerConnectionClient.speakerOff()
                delegate?.callServiceFinishedProcess()
                action.completion?()
            case .muteAudio:
                peerConnectionClient.muteAudio(completion: {
                    self.delegate?.callServiceFinishedProcess()
                    action.completion?()
                })
            case .unmuteAudio:
                peerConnectionClient.unmuteAudio(completion: {
                    self.delegate?.callServiceFinishedProcess()
                    action.completion?()
                })
            case .hideCallScreen:
                dismissCallView()
                delegate?.callServiceFinishedProcess()
                action.completion?()
            }
        }
        else if let offer = element as? VoIPCallOfferMessage {
            handleOfferMessage(offer: offer, completion: {
                offer.completion?()
                self.delegate?.callServiceFinishedProcess()
            })
        }
        else if let answer = element as? VoIPCallAnswerMessage {
            handleAnswerMessage(answer: answer, completion: {
                answer.completion?()
                self.delegate?.callServiceFinishedProcess()
            })
        }
        else if let ringing = element as? VoIPCallRingingMessage {
            handleRingingMessage(ringing: ringing, completion: {
                ringing.completion?()
                self.delegate?.callServiceFinishedProcess()
            })
        }
        else if let hangup = element as? VoIPCallHangupMessage {
            handleHangupMessage(hangup: hangup, completion: {
                hangup.completion?()
                self.delegate?.callServiceFinishedProcess()
            })
        }
        else if let ice = element as? VoIPCallIceCandidatesMessage {
            handleIceCandidatesMessage(ice: ice) {
                ice.completion?()
                self.delegate?.callServiceFinishedProcess()
            }
        }
        else {
            delegate?.callServiceFinishedProcess()
        }
    }
    
    /// Get the current call state
    /// - Returns: CallState
    func currentState() -> CallState {
        state
    }
    
    /// Get the current call contact
    /// - Returns: Contact or nil
    func currentContactIdentity() -> String? {
        contactIdentity
    }

    /// Get the current callID
    /// - Returns: VoIPCallID or nil
    func currentCallID() -> VoIPCallID? {
        callID
    }
    
    /// Is initiator of the current call
    /// - Returns: true or false
    func isCallInitiator() -> Bool {
        callInitiator
    }
    
    /// Is the current call muted
    /// - Returns: true or false
    func isCallMuted() -> Bool {
        audioMuted
    }
    
    /// Is the speaker for the current call active
    /// - Returns: true or false
    func isSpeakerActive() -> Bool {
        speakerActive
    }
    
    /// Is the current call already accepted
    /// - Returns: true or false
    func isCallAlreadyAccepted() -> Bool {
        alreadyAccepted
    }
    
    /// Present the CallViewController
    func presentCallViewController() {
        if let identity = contactIdentity,
           alreadyAccepted || ProcessInfoHelper.isRunningForScreenshots {
            presentCallView(
                contactIdentity: identity,
                alreadyAccepted: alreadyAccepted,
                isCallInitiator: callInitiator,
                isThreemaVideoCallAvailable: threemaVideoCallAvailable,
                videoActive: videoActive,
                receivingVideo: isReceivingVideo,
                viewWasHidden: false
            )
        }
    }
    
    /// Dismiss the CallViewController
    func dismissCallViewController() {
        dismissCallView()
    }
    
    /// Set the RTC audio session from CallKit
    /// - parameter callKitAudioSession: AVAudioSession from callkit
    func setRTCAudioSession(_ callKitAudioSession: AVAudioSession) {
        handleTones(state: .calling, oldState: .calling)
        RTCAudioSession.sharedInstance().audioSessionDidActivate(callKitAudioSession)
    }
    
    /// Configure the audio session and set RTC audio active
    func activateRTCAudio() {
        peerConnectionClient.activateRTCAudio(speakerActive: speakerActive)
    }
    
    /// Reports a new call to CallKit with an unknown caller
    /// - Parameters:
    ///   - identity: Threema ID of the caller
    ///   - name: Name of the caller. If it's nil, it use the unknown caller string
    ///   - completion: Completion handler returns true if call successfully reported to CallKit
    func reportInitialCall(from identity: String, name: String?, completion: @escaping (Bool) -> Void) {
        
        guard ThreemaEnvironment.supportsCallKit() else {
            completion(false)
            return
        }
        
        if let callKitManager {
            if callKitManager.currentUUID() != nil {
                callKitManager.endCall()
            }
        }
        else {
            callKitManager = VoIPCallKitManager()
        }
        
        guard let callKitManager else {
            // CallKitManager must have been initialized before we continue execution
            fatalError()
        }
        
        VoIPCallStateManager.shared.preCallHandling = true
        
        callKitManager.reportIncomingCall(
            uuid: UUID(),
            contactIdentity: identity,
            contactName: name ?? BundleUtil.localizedString(forKey: "identity_not_found_title"),
            completion: completion
        )
    }
    
    /// Start capture local video
    func startCaptureLocalVideo(renderer: RTCVideoRenderer, useBackCamera: Bool, switchCamera: Bool = false) {
        localRenderer = renderer
        videoActive = true
        peerConnectionClient.startCaptureLocalVideo(
            renderer: renderer,
            useBackCamera: useBackCamera,
            switchCamera: switchCamera
        )
    }
    
    /// End capture local video
    func endCaptureLocalVideo(switchCamera: Bool = false) {
        if !switchCamera {
            videoActive = false
        }
        if let renderer = localRenderer {
            peerConnectionClient.endCaptureLocalVideo(renderer: renderer, switchCamera: switchCamera)
            localRenderer = nil
        }
    }
    
    /// Get local video renderer
    func localVideoRenderer() -> RTCVideoRenderer? {
        localRenderer
    }
    
    /// Start render remote video
    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        remoteRenderer = renderer
        peerConnectionClient.renderRemoteVideo(to: renderer)
    }
    
    /// End remote video
    func endRemoteVideo() {
        if let renderer = remoteRenderer {
            peerConnectionClient.endRemoteVideo(renderer: renderer)
            remoteRenderer = nil
        }
    }
    
    /// Get remote video renderer
    func remoteVideoRenderer() -> RTCVideoRenderer? {
        remoteRenderer
    }
    
    /// Get peer video quality profile
    func remoteVideoQualityProfile() -> CallsignalingProtocol.ThreemaVideoCallQualityProfile? {
        peerConnectionClient.remoteVideoQualityProfile
    }
    
    /// Get peer is using turn server
    func networkIsRelayed() -> Bool {
        peerConnectionClient.networkIsRelayed
    }
}

extension VoIPCallService {
    // MARK: private functions
    
    /// When the current call state is idle and the permission is granted to the microphone, it will create the peer
    /// client and add the offer.
    /// If the state is wrong, it will reject the call with the reason unknown.
    /// If the permission to the microphone is not granted, it will reject the call with the reason unknown.
    /// If Threema Calls are disabled, it will reject the call with the reason disabled.
    /// - parameter offer: VoIPCallOfferMessage
    /// - parameter completion: Completion block
    private func handleOfferMessage(offer: VoIPCallOfferMessage, completion: @escaping (() -> Void)) {
        // We're logging this twice as a quick fix for compatibility with Android style logging
        DDLogNotice(
            "VoipCallService: [cid=\(offer.callID.callID)]: Handle new call with \(offer.contactIdentity ?? "?"), we are the callee"
        )
        DDLogNotice(
            "VoipCallService: [cid=\(offer.callID.callID)]: Call offer received from \(offer.contactIdentity ?? "?")"
        )
        
        // Store call in temporary call history
        Task {
            if let contactIdentity = offer.contactIdentity {
                DDLogNotice(
                    "VoipCallService: [cid=\(offer.callID.callID)]: Start add callID to CallHistory"
                )
                await CallHistoryManager(identity: contactIdentity, businessInjector: businessInjector)
                    .store(callID: offer.callID.callID, date: Date())
                DDLogNotice(
                    "VoipCallService: [cid=\(offer.callID.callID)]: End add callID to CallHistory"
                )
            }
        }
        
        if businessInjector.userSettings.enableThreemaCall {
            var appRunsInBackground = false
            DispatchQueue.main.sync {
                appRunsInBackground = AppDelegate.shared().isAppInBackground()
            }

            DDLogNotice(
                "VoipCallService: [cid=\(offer.callID.callID)]: Update lastUpdate for conversation"
            )
            businessInjector.entityManager.performSyncBlockAndSafe {
                if let conversation = self.businessInjector.entityManager.entityFetcher
                    .conversation(forIdentity: offer.contactIdentity) {
                    conversation.lastUpdate = Date.now
                }
            }

            if state == .idle, !NavigationBarPromptHandler.isGroupCallActive {
                if !businessInjector.pushSettingManager.canMasterDndSendPush() {
                    DDLogWarn("VoipCallService: [cid=\(offer.callID.callID)]: Master DND active, reject the call")
                    contactIdentity = offer.contactIdentity
                    let action = VoIPCallUserAction(
                        action: .rejectOffHours,
                        contactIdentity: offer.contactIdentity!,
                        callID: offer.callID,
                        completion: offer.completion
                    )
                    rejectCall(action: action, closeCallView: true)
                    completion()
                    return
                }
                
                if ThreemaEnvironment.supportsCallKit(), callKitManager == nil {
                    callKitManager = VoIPCallKitManager()
                }
                
                // If a call was already reported, it was the initial call launched when the app was in background. So
                // we update the caller.
                if let uuid = callKitManager?.currentUUID() {
                    DDLogNotice(
                        "VoipCallService: [cid=\(offer.callID.callID)]: updateReportedIncomingCall"
                    )
                    callKitManager?.updateReportedIncomingCall(
                        uuid: uuid,
                        contactIdentity: offer.contactIdentity!
                    )
                }
                else {
                    DDLogNotice(
                        "VoipCallService: [cid=\(offer.callID.callID)]: reportIncomingCall"
                    )
                    callKitManager?.reportIncomingCall(
                        uuid: UUID(),
                        contactIdentity: offer.contactIdentity!,
                        contactName: nil,
                        completion: { succeeded in
                            if !succeeded {
                                DDLogError("Report incoming call failed, call is starting anyway")
                            }
                        }
                    )
                }
                
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    if granted {
                        self.contactIdentity = offer.contactIdentity
                        self.alreadyAccepted = false
                        self.state = .receivedOffer
                        self.incomingOffer = offer
                        self.callID = offer.callID
                        self.videoActive = false
                        self.isReceivingVideo = false
                        self.localRenderer = nil
                        self.remoteRenderer = nil
                        self.threemaVideoCallAvailable = offer.isVideoAvailable
                        self.startIncomingCallTimeoutTimer()
                        
                        DDLogNotice(
                            "VoipCallService: [cid=\(offer.callID.callID)]: connectWait"
                        )
                        
                        /// Make sure that the connection is not prematurely disconnected when the app is put into the
                        /// background
                        self.businessInjector.serverConnector.connectWait(initiator: .threemaCall)

                        DDLogNotice(
                            "VoipCallService: [cid=\(offer.callID.callID)]: Send ringing message"
                        )
                        
                        // New Call
                        // Send ringing message
                        let ringingMessage = VoIPCallRingingMessage(
                            contactIdentity: offer.contactIdentity!,
                            callID: offer.callID,
                            completion: nil
                        )
                        self.voIPCallSender.sendVoIPCallRinging(ringingMessage: ringingMessage)
                        
                        self.state = .incomingRinging
                        
                        // Prefetch ICE/TURN servers so they're likely to be already available when the user accepts the
                        // call
                        VoIPIceServerSource.prefetchIceServers()
                        
                        if !ThreemaEnvironment.supportsCallKit() {
                            self.presentCallView(
                                contactIdentity: offer.contactIdentity!,
                                alreadyAccepted: false,
                                isCallInitiator: false,
                                isThreemaVideoCallAvailable: self.threemaVideoCallAvailable,
                                videoActive: false,
                                receivingVideo: false,
                                viewWasHidden: false,
                                completion: completion
                            )
                        }
                        else {
                            completion()
                        }
                    }
                    else {
                        DDLogWarn("VoipCallService: [cid=\(offer.callID.callID)]: Audio is not granted")
                        self.contactIdentity = offer.contactIdentity
                        self.state = .microphoneDisabled
                        // reject call because there is no permission for the microphone
                        self.state = .rejectedDisabled
                        let action = VoIPCallUserAction(
                            action: .rejectUnknown,
                            contactIdentity: offer.contactIdentity!,
                            callID: offer.callID,
                            completion: offer.completion
                        )
                        self.rejectCall(action: action, closeCallView: false)
                        
                        if appRunsInBackground {
                            // show notification that incoming call can't connect because mic is not granted
                            NotificationManager.showNoMicrophonePermissionNotification()
                            self.disconnectPeerConnection()
                            completion()
                        }
                        else {
                            self.presentCallView(
                                contactIdentity: offer.contactIdentity!,
                                alreadyAccepted: false,
                                isCallInitiator: false,
                                isThreemaVideoCallAvailable: self.threemaVideoCallAvailable,
                                videoActive: false,
                                receivingVideo: false,
                                viewWasHidden: false,
                                completion: {
                                    
                                    // No access to microphone, stop call
                                    let rootVC = self.callViewController != nil ? self
                                        .callViewController! : UIApplication
                                        .shared.windows.first!.rootViewController!
                                    
                                    DispatchQueue.main.async {
                                        UIAlertTemplate.showOpenSettingsAlert(
                                            owner: rootVC,
                                            noAccessAlertType: .microphone
                                        ) {
                                            self.dismissCallView()
                                            self.disconnectPeerConnection()
                                        } actionCancel: {
                                            self.dismissCallView()
                                            self.disconnectPeerConnection()
                                        }
                                    }
                                    
                                    completion()
                                }
                            )
                        }
                    }
                }
            }
            else {
                DDLogWarn(
                    "VoipCallService: [cid=\(offer.callID.callID)]: Current state is not IDLE (\(state.description()))"
                )
                if contactIdentity == offer.contactIdentity, state == .incomingRinging {
                    DDLogNotice("Threema call: handleOfferMessage -> same contact as the current call")
                    if !businessInjector.pushSettingManager.canMasterDndSendPush(), appRunsInBackground {
                        DDLogNotice(
                            "Threema call: handleOfferMessage -> Master DND active -> reject call from \(String(describing: offer.contactIdentity))"
                        )
                        let action = VoIPCallUserAction(
                            action: .rejectOffHours,
                            contactIdentity: offer.contactIdentity!,
                            callID: offer.callID,
                            completion: offer.completion
                        )
                        rejectCall(action: action, closeCallView: true)
                        completion()
                    }
                    else {
                        DDLogWarn(
                            "VoipCallService: [cid=\(offer.callID.callID)]: Same contact as the current call ((\(offer.contactIdentity ?? "?")), Master DND inactive, set the offer"
                        )
                        disconnectPeerConnection()
                        handleOfferMessage(offer: offer, completion: completion)
                    }
                }
                else {
                    // reject call because it's the wrong state
                    let reason: VoIPCallUserAction.Action = contactIdentity == offer
                        .contactIdentity ? .rejectUnknown : .rejectBusy
                    let action = VoIPCallUserAction(
                        action: reason,
                        contactIdentity: offer.contactIdentity!,
                        callID: offer.callID,
                        completion: offer.completion
                    )
                    rejectCall(action: action)
                    completion()
                }
            }
        }
        else {
            // reject call because Threema Calls are disabled or unavailable
            let action = VoIPCallUserAction(
                action: .rejectDisabled,
                contactIdentity: offer.contactIdentity!,
                callID: offer.callID,
                completion: offer.completion
            )
            rejectCall(action: action)
            completion()
        }
    }
    
    private func startIncomingCallTimeoutTimer() {
        DispatchQueue.main.async {
            if let offer = self.incomingOffer {
                self.invalidateIncomingCallTimeout()
                self.incomingCallTimeoutTimer = Timer.scheduledTimer(
                    withTimeInterval: self.kIncomingCallTimeout,
                    repeats: false,
                    block: { _ in
                        BackgroundTaskManager.shared.newBackgroundTask(
                            key: kAppVoIPBackgroundTask,
                            timeout: Int(kAppVoIPBackgroundTaskTime)
                        ) { [weak self] in
                            guard let self else {
                                return
                            }
                            
                            guard offer.callID == incomingOffer?.callID else {
                                DDLogError(
                                    "Trying to run background task for call with ID \(offer.callID), but current incoming offer call ID is \(incomingOffer?.callID ?? VoIPCallID(callID: nil))"
                                )
                                return
                            }
                            
                            businessInjector.serverConnector.connect(initiator: .threemaCall)

                            callKitManager?.timeoutCall()
                            let action = VoIPCallUserAction(
                                action: .rejectTimeout,
                                contactIdentity: offer.contactIdentity!,
                                callID: offer.callID,
                                completion: offer.completion
                            )
                            rejectCall(action: action)
                            invalidateIncomingCallTimeout()
                        }
                    }
                )
            }
        }
    }
    
    /// Handle the answer message if the contact in the answer message is the same as in the call service and call state
    /// is ringing.
    /// Call will cancel if it's rejected and CallViewController will close.
    /// - parameter answer: VoIPCallAnswerMessage
    /// - parameter completion: Completion block
    private func handleAnswerMessage(answer: VoIPCallAnswerMessage, completion: @escaping (() -> Void)) {
        let logString =
            "VoipCallService: [cid=\(answer.callID.callID)]: Call answer received from \(answer.contactIdentity ?? "?"): \(answer.action.description())"
        if answer.action == .call {
            DDLogNotice(logString)
        }
        else {
            DDLogNotice(logString + "/\(answer.rejectReason?.description() ?? "unknown")")
        }
        
        if let identity = contactIdentity {
            if callInitiator {
                if let callID, state == .sendOffer || state == .outgoingRinging,
                   identity == answer.contactIdentity, callID.isSame(answer.callID) {
                    state = .receivedAnswer
                    if answer.action == VoIPCallAnswerMessage.MessageAction.reject {
                        // call is rejected
                        switch answer.rejectReason {
                        case .busy?:
                            state = .rejectedBusy
                        case .timeout?:
                            state = .rejectedTimeout
                        case .reject?:
                            state = .rejected
                        case .disabled?:
                            state = .rejectedDisabled
                        case .offHours?:
                            state = .rejectedOffHours
                        case .none:
                            state = .rejected
                        case .some(.unknown):
                            state = .rejectedUnknown
                        }
                        callKitManager?.rejectCall()
                        dismissCallView(rejected: true, completion: {
                            self.disconnectPeerConnection()
                            completion()
                        })
                    }
                    else {
                        // handle answer
                        state = .receivedAnswer
                        if answer.isVideoAvailable, UserSettings.shared().enableVideoCall {
                            threemaVideoCallAvailable = true
                            callViewController?.enableThreemaVideoCall()
                        }
                        else {
                            threemaVideoCallAvailable = false
                            callViewController?.disableThreemaVideoCall()
                        }
                        if let remoteSdp = answer.answer {
                            peerConnectionClient.set(remoteSdp: remoteSdp, completion: { error in
                                if error == nil {
                                    switch self.state {
                                    case .idle, .sendOffer, .receivedOffer, .outgoingRinging, .incomingRinging,
                                         .sendAnswer, .receivedAnswer:
                                        self.state = .initializing
                                    default:
                                        break
                                    }
                                }
                                else {
                                    DDLogError(
                                        "VoipCallService: [cid=\(answer.callID.callID)]: Can't add remote sdp to the peerConnection"
                                    )
                                    let hangupMessage = VoIPCallHangupMessage(
                                        contactIdentity: self.contactIdentity!,
                                        callID: self.callID!,
                                        completion: nil
                                    )
                                    self.voIPCallSender.sendVoIPCallHangup(hangupMessage: hangupMessage)
                                    self.state = .rejectedUnknown
                                    self.dismissCallView()
                                    self.disconnectPeerConnection()
                                }
                                completion()
                            })
                        }
                        else {
                            DDLogError("VoipCallService: [cid=\(answer.callID.callID)]: Remote sdp is empty")
                            let hangupMessage = VoIPCallHangupMessage(
                                contactIdentity: contactIdentity!,
                                callID: self.callID!,
                                completion: nil
                            )
                            voIPCallSender.sendVoIPCallHangup(hangupMessage: hangupMessage)
                            state = .rejectedUnknown
                            dismissCallView()
                            disconnectPeerConnection()
                            completion()
                        }
                    }
                }
                else {
                    if identity == answer.contactIdentity {
                        DDLogWarn(
                            "VoipCallService: [cid=\(answer.callID.callID)]: Current state is wrong (\(state.description())) or callId is different to \(callID?.callID ?? 0)"
                        )
                    }
                    else {
                        DDLogWarn(
                            "VoipCallService: [cid=\(answer.callID.callID)]: Answer contact (\(answer.contactIdentity ?? "?") is different to current call contact (\(identity)"
                        )
                    }
                    completion()
                }
            }
            else {
                // We are not the initiator so we can ignore this message
                DDLogWarn("VoipCallService: [cid=\(answer.callID.callID)]: No initiator, ignore this answer")
                completion()
            }
        }
        else {
            DDLogWarn("VoipCallService: [cid=\(answer.callID.callID)]: No contact set for currenct call")
            completion()
        }
    }
    
    /// Handle the ringing message if the contact in the answer message is the same as in the call service and call
    /// state is sendOffer.
    /// CallViewController will play the ringing tone
    /// - parameter ringing: VoIPCallRingingMessage
    /// - parameter completion: Completion block
    private func handleRingingMessage(ringing: VoIPCallRingingMessage, completion: @escaping (() -> Void)) {
        DDLogNotice(
            "VoipCallService: [cid=\(ringing.callID.callID)]: Call ringing message received from \(ringing.contactIdentity ?? "?")"
        )
        if let identity = contactIdentity {
            if let callID, identity == ringing.contactIdentity, callID.isSame(ringing.callID) {
                switch state {
                case .sendOffer:
                    state = .outgoingRinging
                default:
                    DDLogWarn(
                        "VoipCallService: [cid=\(ringing.callID.callID)]: Wrong state (\(state.description())) to handle ringing message"
                    )
                }
            }
            else {
                DDLogWarn(
                    "VoipCallService: [cid=\(ringing.callID.callID)]: Ringing contact (\(ringing.contactIdentity ?? "?") is different to current call contact (\(identity)"
                )
            }
        }
        else {
            DDLogWarn("VoipCallService: [cid=\(ringing.callID.callID)]: No contact set for currenct call")
        }
        completion()
    }
    
    /// Handle add or remove received remote ice candidates (IpV6 candidates will be removed)
    /// - parameter ice: VoIPCallIceCandidatesMessage
    /// - parameter completion: Completion block
    private func handleIceCandidatesMessage(ice: VoIPCallIceCandidatesMessage, completion: @escaping (() -> Void)) {
        DDLogNotice(
            "VoipCallService: [cid=\(ice.callID.callID)]: Call ICE candidate message received from \(ice.contactIdentity ?? "?") (\(ice.candidates.count) candidates)"
        )
        
        for candidate in ice.candidates {
            DDLogNotice("VoipCallService: [cid=\(ice.callID.callID)]: Incoming ICE candidate: \(candidate.sdp)")
        }
        if let identity = contactIdentity {
            if let callID, identity == ice.contactIdentity, callID.isSame(ice.callID) {
                switch state {
                case .sendOffer, .outgoingRinging, .sendAnswer, .receivedAnswer, .initializing, .calling, .reconnecting:
                    if !ice.removed {
                        for candidate in ice.candidates {
                            if shouldAdd(candidate: candidate, local: false) == (true, nil) {
                                peerConnectionClient.set(addRemoteCandidate: candidate)
                            }
                        }
                        completion()
                    }
                    else {
                        // ICE candidate messages are currently allowed to have a "removed" flag. However, this is
                        // non-standard.
                        // When receiving an VoIP ICE Candidate (0x62) message with removed set to true, discard the
                        // message
                        completion()
                    }
                case .receivedOffer, .incomingRinging:
                    // add to local array
                    receivedIceCandidatesLockQueue.sync {
                        receivedIcecandidatesMessages.append(ice)
                        completion()
                    }
                default:
                    DDLogWarn(
                        "VoipCallService: [cid=\(ice.callID.callID)]: Wrong state (\(state.description())) to handle ICE candidates message"
                    )
                    completion()
                }
            }
            else {
                addUnknownCallIcecandidatesMessages(message: ice)
                DDLogNotice(
                    "VoipCallService: [cid=\(ice.callID.callID)]: ICE candidates contact (\(ice.contactIdentity ?? "?") is different to current call contact (\(identity)"
                )
                completion()
            }
        }
        else {
            addUnknownCallIcecandidatesMessages(message: ice)
            DDLogWarn("VoipCallService: [cid=\(ice.callID.callID)]: No contact set for currenct call")
            completion()
        }
    }
    
    /// Handle the hangup message if the contact in the answer message is the same as in the call service and call state
    /// is receivedOffer, ringing, sendAnswer, initializing, calling or reconnecting.
    /// / If we receive a hangup message without having had a call with this callID in any state, we assume that it
    /// belonged to a missed call whose other messages were already dropped by the server.
    /// It will dismiss the CallViewController after the call was ended.
    /// - parameter hangup: VoIPCallHangupMessage
    /// - parameter completion: Completion block
    private func handleHangupMessage(hangup: VoIPCallHangupMessage, completion: @escaping (() -> Void)) {
        DDLogNotice(
            "VoipCallService: [cid=\(hangup.callID.callID)]: Call hangup message received from \(hangup.contactIdentity ?? "?")"
        )
        
        if let identity = contactIdentity {
            if let callID, identity == hangup.contactIdentity, callID.isSame(hangup.callID) {
                switch state {
                case .receivedOffer, .outgoingRinging, .incomingRinging, .sendAnswer, .initializing, .calling,
                     .reconnecting:
                    RTCAudioSession.sharedInstance().isAudioEnabled = false
                    state = .remoteEnded
                    callKitManager?.endCall()
                    dismissCallView()
                    disconnectPeerConnection()
                default:
                    DDLogWarn(
                        "VoipCallService: [cid=\(hangup.callID.callID)]: Wrong state (\(state.description())) to handle hangup message"
                    )
                }
            }
            else {
                DDLogNotice(
                    "VoipCallService: [cid=\(hangup.callID.callID)]: Hangup contact (\(hangup.contactIdentity ?? "?") is different to current call contact (\(identity)"
                )
            }
        }
        else {
            DDLogWarn("VoipCallService: [cid=\(hangup.callID.callID)]: Hangup received")
            // If we receive a hangup message without having had a call with this callID in any state,
            // we assume that it belonged to a missed call whose other messages were already dropped by the server.
            let businessInjector = BusinessInjector()
            CallSystemMessageHelper
                .maybeAddMissedCallNotificationToConversation(
                    with: hangup,
                    on: businessInjector
                ) { conversation, systemMessage in
                    if let conversation, systemMessage != nil {
                        ConversationActions(businessInjector: businessInjector).unarchive(conversation)
                        NotificationManager(businessInjector: businessInjector).updateUnreadMessagesCount()
                    }
                }
        }
        completion()
    }
    
    /// Handle a new outgoing call if Threema calls are enabled and permission for microphone is granted.
    /// It will present the CallViewController.
    /// - parameter action: VoIPCallUserAction
    /// - parameter completion: Completion block
    private func startCallAsInitiator(action: VoIPCallUserAction, completion: @escaping (() -> Void)) {
        
        guard !NavigationBarPromptHandler.isGroupCallActive else {
            showCallActiveAlert()
            completion()
            return
        }
        
        if UserSettings.shared().enableThreemaCall {
            RTCAudioSession.sharedInstance().useManualAudio = true
            if state == .idle {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    if granted {
                        self.callInitiator = true
                        
                        let entityManager = BusinessInjector().entityManager
                        
                        entityManager.performSyncBlockAndSafe {
                            if let conversation = entityManager.entityFetcher
                                .conversation(forIdentity: action.contactIdentity) {
                                conversation.lastUpdate = Date.now
                            }
                        }
                        
                        self.contactIdentity = action.contactIdentity
                        self.createPeerConnectionForInitiator(action: action, completion: completion)
                        self.businessInjector.serverConnector.connect(initiator: .threemaCall)
                    }
                    else {
                        DispatchQueue.main.async {
                            // No access to microphone, stop call
                            let rootVC = UIApplication.shared.windows.first!.rootViewController!
                        
                            UIAlertTemplate.showOpenSettingsAlert(
                                owner: rootVC,
                                noAccessAlertType: .microphone
                            )
                        }
                    
                        completion()
                    }
                }
            }
            else {
                // do nothing because it's the wrong state
                DDLogWarn(
                    "VoipCallService: [cid=\(action.callID?.callID ?? 0)]: Wrong state (\(state.description())) to start call as initiator"
                )
                showCallActiveAlert()
                completion()
            }
        }
        else {
            // do nothing because Threema calls are disabled or unavailable
            completion()
        }
    }
    
    /// Accept a incoming call if state is ringing. Will send a answer message to initiator and update
    /// CallViewController.
    /// It will present the CallViewController.
    /// - parameter action: VoIPCallUserAction
    /// - parameter completion: Completion block
    private func acceptIncomingCall(action: VoIPCallUserAction, completion: @escaping (() -> Void)) {
        createPeerConnectionForIncomingCall {
            RTCAudioSession.sharedInstance().useManualAudio = true
            if self.state == .incomingRinging, !NavigationBarPromptHandler.isGroupCallActive {
                /// Make sure that the connection is not prematurely disconnected when the app is put into the
                /// background
                self.businessInjector.serverConnector.connect(initiator: .threemaCall)
                self.state = .sendAnswer
                self.presentCallViewController()
                
                self.peerConnectionClient.answer(completion: { sdp in
                    if self.threemaVideoCallAvailable, UserSettings.shared().enableVideoCall {
                        self.threemaVideoCallAvailable = true
                        self.callViewController?.enableThreemaVideoCall()
                    }
                    else {
                        self.threemaVideoCallAvailable = false
                        self.callViewController?.disableThreemaVideoCall()
                    }
                    
                    let answerMessage = VoIPCallAnswerMessage(
                        action: .call,
                        contactIdentity: action.contactIdentity,
                        answer: sdp,
                        rejectReason: nil,
                        features: nil,
                        isVideoAvailable: self.threemaVideoCallAvailable,
                        isUserInteraction: true,
                        callID: self.callID!,
                        completion: nil
                    )
                    self.voIPCallSender.sendVoIPCall(answer: answerMessage)
                    
                    if action.action != .acceptCallKit {
                        self.callKitManager?.callAccepted()
                    }
                    self.receivedIceCandidatesLockQueue.sync {
                        if let receivedCandidatesBeforeCall = self
                            .receivedUnknowCallIcecandidatesMessages[action.contactIdentity] {
                            for ice in receivedCandidatesBeforeCall {
                                if ice.callID.callID == self.callID?.callID {
                                    self.receivedIcecandidatesMessages.append(ice)
                                }
                            }
                            self.receivedUnknowCallIcecandidatesMessages.removeAll()
                        }
                        
                        for message in self.receivedIcecandidatesMessages {
                            if !message.removed {
                                for candidate in message.candidates {
                                    if self.shouldAdd(candidate: candidate, local: false) == (true, nil) {
                                        self.peerConnectionClient.set(addRemoteCandidate: candidate)
                                    }
                                }
                            }
                        }
                        self.receivedIcecandidatesMessages.removeAll()
                    }
                    completion()
                })
            }
            else {
                // dismiss call view because it's the wrong state
                DDLogWarn(
                    "VoipCallService: [cid=\(action.callID?.callID ?? 0)]: Wrong state (\(self.state.description())) to accept incoming call action"
                )
                self.callKitManager?.answerFailed()
                self.dismissCallView()
                self.disconnectPeerConnection()
                completion()
                return
            }
        }
    }
    
    /// Creates the peer connection for the initiator and set the offer.
    /// After this, it will present the CallViewController.
    /// - parameter action: VoIPCallUserAction
    /// - parameter completion: Completion block
    private func createPeerConnectionForInitiator(action: VoIPCallUserAction, completion: @escaping (() -> Void)) {
        let entityManager = BusinessInjector().entityManager
        entityManager.performBlock {
            guard let contactIdentity = self.contactIdentity,
                  let contact = entityManager.entityFetcher.contact(for: self.contactIdentity) else {
                completion()
                return
            }
            FeatureMask.check(contacts: [contact], for: Int(FEATURE_MASK_VOIP_VIDEO)) { unsupportedContacts in
                self.threemaVideoCallAvailable = false
                if unsupportedContacts.isEmpty && UserSettings.shared().enableVideoCall {
                    self.threemaVideoCallAvailable = true
                }
                self.peerConnectionClient.close()
                let forceTurn: Bool = Int(truncating: contact.verificationLevel) == kVerificationLevelUnverified ||
                    UserSettings.shared()?.alwaysRelayCalls == true
                let peerConnectionParameters = PeerConnectionParameters(
                    isVideoCallAvailable: self.threemaVideoCallAvailable,
                    videoCodecHwAcceleration: self.threemaVideoCallAvailable,
                    forceTurn: forceTurn,
                    gatherContinually: true,
                    allowIpv6: UserSettings.shared().enableIPv6,
                    isDataChannelAvailable: false
                )
                self.callID = VoIPCallID.generate()
                
                // Store call in temporary call history
                Task {
                    guard let callID = self.callID else {
                        DDLogVerbose("Cannot store call in call history because the callID was set to nil again")
                        return
                    }
                    await CallHistoryManager(
                        identity: action.contactIdentity,
                        businessInjector: BusinessInjector()
                    ).store(callID: callID.callID, date: Date())
                }
                
                DDLogNotice(
                    "VoipCallService: [cid=\(self.callID!.callID)]: Handle new call with \(contactIdentity), we are the caller"
                )
                
                if Int(truncating: contact.verificationLevel) == kVerificationLevelUnverified {
                    DDLogNotice("VoipCallService: [cid=\(self.callID!.callID)]: Force TURN since contact is unverified")
                }
                if let userSettings = UserSettings.shared(), userSettings.alwaysRelayCalls == true {
                    DDLogNotice("VoipCallService: [cid=\(self.callID!.callID)]: Force TURN as requested by user")
                }
                
                guard ServerConnector.shared().connectionState == .loggedIn else {
                    self.callID = nil
                    self.noInternetConnectionError()
                    return
                }

                self.peerConnectionClient.initialize(
                    contactIdentity: contactIdentity,
                    callID: self.callID,
                    peerConnectionParameters: peerConnectionParameters,
                    delegate: self
                ) { error in
                    if let error {
                        self.callID = nil
                        self.callCantCreateOffer(error: error)
                        return
                    }

                    if ThreemaEnvironment.supportsCallKit(), self.callKitManager == nil {
                        self.callKitManager = VoIPCallKitManager()
                    }

                    self.peerConnectionClient.offer(completion: { sdp, sdpError in
                        if let error = sdpError {
                            self.callID = nil
                            self.callCantCreateOffer(error: error)
                            return
                        }
                        guard let sdp, let callID = self.callID else {
                            self.callID = nil
                            self.callCantCreateOffer(error: nil)
                            return
                        }

                        let offerMessage = VoIPCallOfferMessage(
                            offer: sdp,
                            contactIdentity: self.contactIdentity,
                            features: nil,
                            isVideoAvailable: self.threemaVideoCallAvailable,
                            callID: callID,
                            completion: nil
                        )
                        self.voIPCallSender.sendVoIPCall(offer: offerMessage)
                        self.state = .sendOffer
                        DispatchQueue.main.async {
                            self.initCallTimeoutTimer = Timer.scheduledTimer(
                                withTimeInterval: self.kIncomingCallTimeout,
                                repeats: false,
                                block: { _ in
                                    BackgroundTaskManager.shared.newBackgroundTask(
                                        key: kAppVoIPBackgroundTask,
                                        timeout: Int(kAppPushBackgroundTaskTime)
                                    ) {
                                        DispatchQueue.global(qos: .userInitiated).async {
                                            RTCAudioSession.sharedInstance().isAudioEnabled = false

                                            if let callID = self.callID {
                                                DDLogNotice("VoipCallService: [cid=\(callID)]: Call ringing timeout")
                                                let hangupMessage = VoIPCallHangupMessage(
                                                    contactIdentity: contactIdentity,
                                                    callID: callID,
                                                    completion: nil
                                                )
                                                self.voIPCallSender.sendVoIPCallHangup(hangupMessage: hangupMessage)
                                            }
                                            else {
                                                assertionFailure("This should not have happened.")
                                                DDLogError("VoipCallService: [cid=CID WAS NIL]: Call ringing timeout")
                                            }

                                            self.state = .ended
                                            self.disconnectPeerConnection()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                                                self.dismissCallView(rejected: false, completion: {
                                                    self.callKitManager?.endCall()
                                                    self.invalidateInitCallTimeout()

                                                    let rootVC = UIApplication.shared.windows.first!.rootViewController!
                                                    UIAlertTemplate.showAlert(
                                                        owner: rootVC,
                                                        title: BundleUtil
                                                            .localizedString(forKey: "call_voip_not_supported_title"),
                                                        message: BundleUtil
                                                            .localizedString(forKey: "call_contact_not_reachable")
                                                    )
                                                })
                                            }
                                        }
                                    }
                                }
                            )
                        }
                        self.alreadyAccepted = true
                        self.presentCallView(
                            contactIdentity: self.contactIdentity!,
                            alreadyAccepted: true,
                            isCallInitiator: true,
                            isThreemaVideoCallAvailable: self.threemaVideoCallAvailable,
                            videoActive: action.action == .callWithVideo,
                            receivingVideo: false,
                            viewWasHidden: false
                        )
                        self.callKitManager?.startCall(for: self.contactIdentity!)
                        completion()
                    })
                }
            }
        }
    }
    
    /// Creates the peer connection for the incoming call and set the offer if contact is set in the offer.
    /// After this, it will present the CallViewController.
    /// - parameter action: VoIPCallUserAction
    /// - parameter completion: Completion block
    private func createPeerConnectionForIncomingCall(completion: @escaping () -> Void) {
        peerConnectionClient.close()

        let entityManager = BusinessInjector().entityManager
        entityManager.performBlock {
            
            guard let offer = self.incomingOffer,
                  let identity = offer.contactIdentity,
                  let contact = entityManager.entityFetcher.contact(for: identity) else {
                self.state = .idle
                completion()
                return
            }
            FeatureMask.check(contacts: [contact], for: Int(FEATURE_MASK_VOIP_VIDEO)) { _ in
                if self.incomingOffer?.isVideoAvailable ?? false && UserSettings.shared().enableVideoCall {
                    self.threemaVideoCallAvailable = true
                    self.callViewController?.enableThreemaVideoCall()
                }
                else {
                    self.threemaVideoCallAvailable = false
                    self.callViewController?.disableThreemaVideoCall()
                }
                
                let forceTurn = Int(truncating: contact.verificationLevel) == kVerificationLevelUnverified ||
                    UserSettings
                    .shared().alwaysRelayCalls
                let peerConnectionParameters = PeerConnectionParameters(
                    isVideoCallAvailable: self.threemaVideoCallAvailable,
                    videoCodecHwAcceleration: self.threemaVideoCallAvailable,
                    forceTurn: forceTurn,
                    gatherContinually: true,
                    allowIpv6: UserSettings.shared().enableIPv6,
                    isDataChannelAvailable: false
                )

                self.peerConnectionClient.initialize(
                    contactIdentity: identity,
                    callID: offer.callID,
                    peerConnectionParameters: peerConnectionParameters,
                    delegate: self
                ) { error in
                    if let error {
                        DDLogError("Can't instantiate client: \(error)")
                        return
                    }

                    self.peerConnectionClient.set(remoteSdp: offer.offer!, completion: { error in
                        if let error {
                            // reject because we can't add offer
                            DDLogError("We can't add the offer \(error))")
                            let action = VoIPCallUserAction(
                                action: .reject,
                                contactIdentity: identity,
                                callID: offer.callID,
                                completion: offer.completion
                            )
                            self.rejectCall(action: action)
                        }

                        completion()
                    })
                }
            }
        }
    }
    
    /// Removes the peer connection, reset the call state and reset all other values
    private func disconnectPeerConnection() {
        // remove peerConnection
        
        func reset() {
            peerConnectionClient.close()
            contactIdentity = nil
            callID = nil
            threemaVideoCallAvailable = false
            alreadyAccepted = false
            callInitiator = false
            audioMuted = false
            speakerActive = false
            videoActive = false
            isReceivingVideo = false
            incomingOffer = nil
            localRenderer = nil
            remoteRenderer = nil
            audioPlayer?.pause()
            
            do {
                RTCAudioSession.sharedInstance().lockForConfiguration()
                try RTCAudioSession.sharedInstance().setActive(false)
                RTCAudioSession.sharedInstance().unlockForConfiguration()
            }
            catch {
                DDLogError("Could not set shared session to not active. Error: \(error)")
            }
            
            DispatchQueue.main.async {
                NavigationBarPromptHandler.isCallActiveInBackground = false
                NavigationBarPromptHandler.name = nil
                NotificationCenter.default.post(
                    name: NSNotification.Name(kNotificationNavigationItemPromptShouldChange),
                    object: nil
                )
            }
            
            state = .idle
            DispatchQueue.main.async {
                Timer.scheduledTimer(
                    withTimeInterval: self.kEndedDelay,
                    repeats: false,
                    block: { _ in
                        if self.state == .idle {
                            self.businessInjector.serverConnector.disconnect(initiator: .threemaCall)
                        }
                    }
                )
            }
        }
        
        peerConnectionClient.stopVideoCall()
        peerConnectionClient.logDebugEndStats {
            reset()
        }
    }
    
    /// Present the CallViewController on the main thread.
    /// - parameter contact: Contact of the call
    /// - parameter alreadyAccepted: Set to true if the call was already accepted
    /// - parameter isCallInitiator: If user is the call initiator
    private func presentCallView(
        contactIdentity: String,
        alreadyAccepted: Bool,
        isCallInitiator: Bool,
        isThreemaVideoCallAvailable: Bool,
        videoActive: Bool,
        receivingVideo: Bool,
        viewWasHidden: Bool,
        completion: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            var viewWasHidden = viewWasHidden
            if self.callViewController == nil {
                let callStoryboard = UIStoryboard(name: "CallStoryboard", bundle: nil)
                let callVC = callStoryboard.instantiateInitialViewController() as! CallViewController
                self.callViewController = callVC
                viewWasHidden = false
            }
            
            let rootVC = UIApplication.shared.windows.first!.rootViewController
            var presentingVC = (rootVC?.presentedViewController ?? rootVC)
            
            if let navController = presentingVC as? UINavigationController {
                presentingVC = navController.viewControllers.last
            }
            
            if !(presentingVC?.isKind(of: CallViewController.self) ?? false) {
                if let presentedVC = presentingVC?.presentedViewController {
                    if presentedVC.isKind(of: CallViewController.self) {
                        return
                    }
                }
                self.showCallViewIfActive(
                    presentingVC: presentingVC,
                    viewWasHidden: viewWasHidden,
                    isCallInitiator: isCallInitiator,
                    isThreemaVideoCallAvailable: isThreemaVideoCallAvailable,
                    receivingVideo: receivingVideo,
                    completion: completion
                )
            }
        }
    }
    
    private func showCallActiveAlert() {
        Task { @MainActor in
            guard let vc = UIApplication.shared.windows.first?.rootViewController else {
                return
            }
            
            UIAlertTemplate.showAlert(
                owner: vc,
                title: BundleUtil.localizedString(forKey: "group_call_error_already_in_call_title"),
                message: BundleUtil.localizedString(forKey: "group_call_error_already_in_call_message")
            )
        }
    }
    
    private func showCallViewIfActive(
        presentingVC: UIViewController?,
        viewWasHidden: Bool,
        isCallInitiator: Bool,
        isThreemaVideoCallAvailable: Bool,
        receivingVideo: Bool,
        completion: (() -> Void)? = nil
    ) {
        if UIApplication.shared.applicationState == .active,
           !callViewController!.isBeingPresented,
           !isModal {
            callViewController!.viewWasHidden = viewWasHidden
            callViewController!.voIPCallStatusChanged(state: state, oldState: state)
            callViewController!.contactIdentity = contactIdentity
            callViewController!.alreadyAccepted = alreadyAccepted
            callViewController!.isCallInitiator = isCallInitiator
            callViewController!.threemaVideoCallAvailable = isThreemaVideoCallAvailable
            callViewController!.isLocalVideoActive = videoActive
            callViewController!.isReceivingRemoteVideo = receivingVideo
            if ProcessInfoHelper.isRunningForScreenshots {
                callViewController!.isTesting = true
            }
            callViewController!.modalPresentationStyle = .overFullScreen
            presentingVC?.present(callViewController!, animated: false, completion: {
                // need to check is fresh start, then we have to set isReceivingRemotVideo again to show the video of
                // the remote
                if !viewWasHidden, !isCallInitiator {
                    self.callViewController!.isReceivingRemoteVideo = receivingVideo
                }
                if completion != nil {
                    completion!()
                }
            })
        }
    }
    
    /// Dismiss the CallViewController in the main thread.
    private func dismissCallView(rejected: Bool? = false, completion: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            if let callVC = self.callViewController {
                self.callViewController?.resetStatsTimer()
                if rejected == true {
                    if let callViewController = self.callViewController {
                        callViewController.endButton?.isEnabled = false
                        callViewController.speakerButton?.isEnabled = false
                        callViewController.muteButton?.isEnabled = false
                    }
                    Timer.scheduledTimer(withTimeInterval: 4, repeats: false, block: { _ in
                        callVC.dismiss(animated: true, completion: {
                            switch self.state {
                            case .sendOffer, .receivedOffer, .outgoingRinging, .incomingRinging, .sendAnswer,
                                 .receivedAnswer, .initializing, .calling, .reconnecting: break
                            case .idle, .ended, .remoteEnded, .rejected, .rejectedBusy, .rejectedTimeout,
                                 .rejectedDisabled, .rejectedOffHours, .rejectedUnknown, .microphoneDisabled:
                                self.callViewController = nil
                            }
                            if AppDelegate.shared()?.isAppLocked == true {
                                AppDelegate.shared()?.presentPasscodeView()
                            }
                            completion?()
                        })
                    })
                }
                else {
                    callVC.dismiss(animated: true, completion: {
                        switch self.state {
                        case .sendOffer, .receivedOffer, .outgoingRinging, .incomingRinging, .sendAnswer,
                             .receivedAnswer, .initializing, .calling, .reconnecting: break
                        case .idle, .ended, .remoteEnded, .rejected, .rejectedBusy, .rejectedTimeout, .rejectedDisabled,
                             .rejectedOffHours, .rejectedUnknown, .microphoneDisabled:
                            self.callViewController = nil
                        }
                        if AppDelegate.shared()?.isAppLocked == true {
                            AppDelegate.shared()?.presentPasscodeView()
                        }
                        completion?()
                    })
                }
                
                NotificationCenter.default.post(
                    name: NSNotification.Name(rawValue: kNotificationNavigationItemPromptShouldChange),
                    object: self.callDurationTime
                )
            }
        }
    }
    
    /// Reject the call with the reason given in the action.
    /// Will end call and dismiss the CallViewController.
    /// - parameter action: VoIPCallUserAction with the given reject reason
    /// - parameter closeCallView: Default is true. If set false, it will not disconnect the peer connection and will
    /// not close the call view
    private func rejectCall(action: VoIPCallUserAction, closeCallView: Bool? = true) {
        var reason: VoIPCallAnswerMessage.MessageRejectReason = .reject
        
        switch action.action {
        case .rejectDisabled:
            reason = .disabled
            if action.contactIdentity == contactIdentity {
                state = .rejectedDisabled
            }
        case .rejectTimeout:
            reason = .timeout
            if action.contactIdentity == contactIdentity {
                state = .rejectedTimeout
            }
        case .rejectBusy:
            reason = .busy
            if action.contactIdentity == contactIdentity {
                state = .rejectedBusy
            }
        case .rejectOffHours:
            reason = .offHours
            if action.contactIdentity == contactIdentity {
                state = .rejectedOffHours
            }
        case .rejectUnknown:
            reason = .unknown
            if action.contactIdentity == contactIdentity {
                state = .rejectedUnknown
            }
        default:
            if action.contactIdentity == contactIdentity {
                state = .rejected
            }
        }
        
        let answer = VoIPCallAnswerMessage(
            action: .reject,
            contactIdentity: action.contactIdentity,
            answer: nil,
            rejectReason: reason,
            features: nil,
            isVideoAvailable: UserSettings.shared().enableVideoCall,
            isUserInteraction: false,
            callID: action.callID ?? VoIPCallID(callID: nil),
            completion: nil
        )
        voIPCallSender.sendVoIPCall(answer: answer)
        if contactIdentity == action.contactIdentity {
            callKitManager?.rejectCall()
            if closeCallView == true {
                // remove peerConnection
                dismissCallView()
                disconnectPeerConnection()
            }
        }
        else {
            addRejectedMessageToConversation(contactIdentity: action.contactIdentity, reason: kSystemMessageCallMissed)
        }
    }
    
    /// It will check the current call state and play the correct tone if it's needed
    private func handleTones(state: VoIPCallService.CallState, oldState: VoIPCallService.CallState) {
        if ProcessInfoHelper.isRunningForScreenshots {
            return
        }
        switch state {
        case .outgoingRinging, .incomingRinging:
            if callInitiator {
                let soundFilePath = BundleUtil.path(forResource: "ringing-tone-ch-fade", ofType: "mp3")
                let soundURL = URL(fileURLWithPath: soundFilePath!)
                setupAudioSession()
                playSound(soundURL: soundURL, loops: -1)
            }
        case .rejected, .rejectedBusy, .rejectedTimeout, .rejectedOffHours, .rejectedUnknown, .rejectedDisabled:
            if !businessInjector.pushSettingManager.canMasterDndSendPush() || !isCallInitiator() {
                // do not play sound if dnd mode is active and user is not the call initiator
                audioPlayer?.stop()
            }
            else {
                let soundFilePath = BundleUtil.path(forResource: "busy-4x", ofType: "mp3")
                let soundURL = URL(fileURLWithPath: soundFilePath!)
                setupAudioSession()
                playSound(soundURL: soundURL, loops: 0)
            }
        case .ended, .remoteEnded:
            if oldState != .incomingRinging {
                let soundFilePath = BundleUtil.path(forResource: "threema_hangup", ofType: "mp3")
                let soundURL = URL(fileURLWithPath: soundFilePath!)
                setupAudioSession()
                playSound(soundURL: soundURL, loops: 0)
            }
            else {
                audioPlayer?.stop()
            }
        case .calling:
            if oldState != .reconnecting {
                let soundFilePath = BundleUtil.path(forResource: "threema_pickup", ofType: "mp3")
                let soundURL = URL(fileURLWithPath: soundFilePath!)
                setupAudioSession()
                playSound(soundURL: soundURL, loops: 0)
            }
            else {
                audioPlayer?.stop()
            }
        case .reconnecting:
            let soundFilePath = BundleUtil.path(forResource: "threema_problem", ofType: "mp3")
            let soundURL = URL(fileURLWithPath: soundFilePath!)
            setupAudioSession()
            playSound(soundURL: soundURL, loops: -1)
        case .idle:
            break
        case .sendOffer, .receivedOffer, .sendAnswer, .receivedAnswer, .initializing:
            // do nothing
            break
        case .microphoneDisabled:
            // do nothing
            break
        }
    }
    
    private func setupAudioSession(_ soloAmbient: Bool = false) {
        let audioSession = AVAudioSession.sharedInstance()
        if soloAmbient {
            do {
                try audioSession.setCategory(
                    .soloAmbient,
                    mode: .default,
                    options: [.allowBluetooth, .allowBluetoothA2DP]
                )
                try audioSession.overrideOutputAudioPort(speakerActive ? .speaker : .none)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            }
            catch {
                print(error.localizedDescription)
            }
        }
        else {
            do {
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .voiceChat,
                    options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
                )
                try audioSession.overrideOutputAudioPort(speakerActive ? .speaker : .none)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            }
            catch {
                print(error.localizedDescription)
            }
        }
    }
    
    /// It will play the given sound
    /// - parameter soundURL: URL of the sound file
    /// - parameter loop: -1 for endless
    /// - parameter playOnSpeaker: True or false if should play the tone over the speaker
    private func playSound(soundURL: URL, loops: Int) {
        audioPlayer?.stop()
        do {
            let player = try AVAudioPlayer(contentsOf: soundURL, fileTypeHint: AVFileType.mp3.rawValue)
            player.numberOfLoops = loops
            audioPlayer = player
            player.play()
        }
        catch {
            print(error.localizedDescription)
        }
    }
    
    /// Invalidate the timers per call state
    /// - parameter state: new set state of the call state
    private func invalidateTimers(state: CallState) {
        switch state {
        case .idle:
            invalidateIncomingCallTimeout()
            invalidateInitCallTimeout()
            invalidateCallDuration()
            invalidateCallFailedTimer()
            invalidateTransportExpectedStableTimer()
        case .sendOffer:
            invalidateCallFailedTimer()
        case .receivedOffer:
            invalidateInitCallTimeout()
            invalidateCallFailedTimer()
        case .outgoingRinging, .incomingRinging:
            invalidateInitCallTimeout()
            invalidateCallFailedTimer()
        case .sendAnswer:
            invalidateInitCallTimeout()
            invalidateIncomingCallTimeout()
            invalidateCallFailedTimer()
        case .receivedAnswer:
            invalidateInitCallTimeout()
            invalidateCallFailedTimer()
        case .initializing:
            invalidateInitCallTimeout()
            invalidateIncomingCallTimeout()
        case .calling:
            invalidateInitCallTimeout()
            invalidateIncomingCallTimeout()
            invalidateCallFailedTimer()
            invalidateTransportExpectedStableTimer()
        case .reconnecting:
            invalidateInitCallTimeout()
            invalidateIncomingCallTimeout()
        case .ended, .remoteEnded:
            invalidateInitCallTimeout()
            invalidateIncomingCallTimeout()
            invalidateCallFailedTimer()
            invalidateTransportExpectedStableTimer()
        case .rejected, .rejectedBusy, .rejectedTimeout, .rejectedDisabled, .rejectedOffHours, .rejectedUnknown:
            invalidateInitCallTimeout()
            invalidateCallDuration()
            invalidateIncomingCallTimeout()
            invalidateCallFailedTimer()
            invalidateTransportExpectedStableTimer()
        case .microphoneDisabled:
            invalidateInitCallTimeout()
            invalidateCallDuration()
            invalidateIncomingCallTimeout()
            invalidateCallFailedTimer()
            invalidateTransportExpectedStableTimer()
        @unknown default:
            break
        }
    }
    
    /// Invalidate the incoming call timer
    private func invalidateIncomingCallTimeout() {
        incomingCallTimeoutTimer?.invalidate()
        incomingCallTimeoutTimer = nil
    }
    
    /// Invalidate the init call timer
    private func invalidateInitCallTimeout() {
        initCallTimeoutTimer?.invalidate()
        initCallTimeoutTimer = nil
    }
    
    /// Invalidate the call duration timer and set the callDurationTime to 0
    private func invalidateCallDuration() {
        callDurationTimer?.invalidate()
        callDurationTimer = nil
        callDurationTime = 0
    }
    
    /// Invalidate the call failed timer
    private func invalidateCallFailedTimer() {
        callFailedTimer?.invalidate()
        callFailedTimer = nil
    }
    
    /// Invalidate the transport expected stable
    private func invalidateTransportExpectedStableTimer() {
        transportExpectedStableTimer?.invalidate()
        transportExpectedStableTimer = nil
    }
    
    /// Add icecandidate to local array if it's in the correct state. Start a timer to send candidates as packets all
    /// 0.05 seconds
    /// - parameter candidate: RTCIceCandidate
    private func handleLocalIceCandidates(_ candidates: [RTCIceCandidate]) {
        func addCandidateToLocalArray(_ addedCadidates: [RTCIceCandidate]) {
            iceCandidatesLockQueue.sync {
                for (_, candidate) in addedCadidates.enumerated() {
                    if shouldAdd(candidate: candidate, local: true) == (true, nil) {
                        localAddedIceCandidates.append(candidate)
                    }
                }
            }
        }
        
        switch state {
        case .sendOffer, .outgoingRinging, .receivedAnswer, .initializing, .calling, .reconnecting:
            addCandidateToLocalArray(candidates)
            let seperatedCandidates = localAddedIceCandidates.take(localAddedIceCandidates.count)
            if !seperatedCandidates.isEmpty {
                let message = VoIPCallIceCandidatesMessage(
                    removed: false,
                    candidates: seperatedCandidates,
                    contactIdentity: contactIdentity,
                    callID: callID!,
                    completion: nil
                )
                voIPCallSender.sendVoIPCall(iceCandidates: message)
            }
            localAddedIceCandidates.removeAll()
        case .idle, .receivedOffer, .incomingRinging, .sendAnswer:
            addCandidateToLocalArray(candidates)
        case .ended, .remoteEnded, .rejected, .rejectedBusy, .rejectedTimeout, .rejectedOffHours, .rejectedUnknown,
             .rejectedDisabled, .microphoneDisabled:
            // do nothing
            
            break
        }
    }
    
    /// Check if should add a ice candidate
    /// - parameter candidate: RTCIceCandidate
    /// - Returns: true or false, reason
    private func shouldAdd(candidate: RTCIceCandidate, local: Bool) -> (Bool, String?) {
        let parts = candidate.sdp.components(separatedBy: CharacterSet(charactersIn: " "))
        
        // Invalid candidate but who knows what they're doing, so we'll just eat it...
        if parts.count < 8 {
            return (true, nil)
        }
        
        // Discard loopback
        let ip = parts[4]
        if ip == "127.0.0.1" || ip == "::1" {
            DDLogNotice(
                "VoipCallService: [cid=\(callID?.callID ?? 0)]: Discarding loopback candidate: \(candidate.sdp)"
            )
            return (false, "loopback")
        }
        
        // Discard IPv6 if disabled
        if UserSettings.shared()?.enableIPv6 == false && ip.contains(":") {
            DDLogNotice(
                "VoipCallService: [cid=\(callID?.callID ?? 0)]: Discarding local IPv6 candidate: \(candidate.sdp)"
            )
            return (false, "ipv6_disabled")
        }
        
        // Always add if not relay
        let type = parts[7]
        if type != "relay" || parts.count < 10 {
            return (true, nil)
        }
        
        // Always add if related address is any
        let relatedAddress = parts[9]
        if relatedAddress == "0.0.0.0" {
            return (true, nil)
        }
        
        if local {
            // Discard only local relay candidates with the same related address
            // Important: This only works as long as we don't do ICE restarts and don't add further relay transport types!
            if localRelatedAddresses.contains(relatedAddress) {
                DDLogNotice(
                    "VoipCallService: [cid=\(callID?.callID ?? 0)]: Discarding local relay candidate (duplicate related address: \(relatedAddress)): \(candidate.sdp)"
                )
                return (false, "duplicate_related_addr")
            }
            else {
                localRelatedAddresses.insert(relatedAddress)
            }
        }
        
        // Add it!
        return (true, nil)
    }
    
    /// Check if an IP address is IPv6
    /// - parameter ipToValidate: String of the ip
    /// - Returns: true or false
    private func isIPv6Address(_ ipToValidate: String) -> Bool {
        var sin6 = sockaddr_in6()
        if ipToValidate.withCString({ cstring in inet_pton(AF_INET6, cstring, &sin6.sin6_addr) }) == 1 {
            return true
        }
        
        return false
    }
    
    // MARK: - Missed Call

    /// Handle notification if needed
    private func handleLocalNotification() {
        switch state {
        case .idle, .sendOffer, .receivedOffer, .outgoingRinging, .incomingRinging, .sendAnswer, .receivedAnswer,
             .initializing, .calling, .reconnecting, .ended, .rejected, .rejectedOffHours, .rejectedUnknown,
             .rejectedDisabled, .microphoneDisabled:
            break
        case .remoteEnded, .rejectedBusy, .rejectedTimeout:
            addMissedCall()
        }
    }
    
    private func addMissedCall() {
        
        guard let identity = contactIdentity else {
            DDLogError("Cannot add missed call without identity")
            return
        }
        
        DispatchQueue.main.async {
            guard AppDelegate.shared().isAppInBackground(),
                  !self.isCallInitiator(),
                  self.callDurationTime == 0 else {
                return
            }

            let pushSetting = self.businessInjector.pushSettingManager.find(forContact: ThreemaIdentity(identity))
            let canSendPush = pushSetting.canSendPush()
            
            guard canSendPush else {
                return
            }
            
            let notification = UNMutableNotificationContent()
            notification.categoryIdentifier = "CALL"
            
            if self.businessInjector.userSettings.pushSound != "none", !pushSetting.muted {
                notification.sound = UNNotificationSound(
                    named: UNNotificationSoundName(
                        rawValue: UserSettings
                            .shared().pushSound! + ".caf"
                    )
                )
            }
            
            let notificationType = self.businessInjector.settingsStore.notificationType
            var contact: ContactEntity?
            
            self.businessInjector.entityManager.performSyncBlockAndSafe {
                contact = self.businessInjector.entityManager.entityFetcher.contact(for: self.contactIdentity)
            }
            guard let contact else {
                return
            }
            notification.userInfo = ["threema": ["cmd": "missedcall", "from": identity]]
            
            if case .restrictive = notificationType {
                if let publicNickname = contact.publicNickname,
                   !publicNickname.isEmpty {
                    notification.title = publicNickname
                }
                else {
                    notification.title = identity
                }
            }
            else {
                notification.title = contact.displayName
            }
            
            notification.body = BundleUtil.localizedString(forKey: "call_missed")
            
            // Group notification together with others from the same contact
            notification.threadIdentifier = "SINGLE-\(identity)"
            
            if case .complete = notificationType,
               let interaction = IntentCreator(
                   userSettings: self.businessInjector.userSettings,
                   entityManager: self.businessInjector.entityManager
               ).inSendMessageIntentInteraction(
                   for: identity,
                   direction: .incoming
               ) {
                self.showRichMissedCallNotification(
                    interaction: interaction,
                    identifier: identity,
                    content: notification
                )
            }
            else {
                self.showRegularMissedCallNotification(with: identity, content: notification)
            }
        }
    }
    
    private func showRegularMissedCallNotification(with identifier: String, content: UNNotificationContent) {
        let notificationRequest = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(notificationRequest)
    }
    
    private func showRichMissedCallNotification(
        interaction: INInteraction,
        identifier: String,
        content: UNNotificationContent
    ) {
        
        interaction.donate { error in
            guard error == nil else {
                self.showRegularMissedCallNotification(with: identifier, content: content)
                return
            }
            
            do {
                let updated = try content.updating(from: interaction.intent as! UNNotificationContentProviding)
                let notificationRequest = UNNotificationRequest(
                    identifier: identifier,
                    content: updated,
                    trigger: nil
                )
                
                UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: { _ in
                })
            }
            catch {
                self.showRegularMissedCallNotification(with: identifier, content: content)
            }
        }
    }
    
    /// Add call message to conversation
    private func addCallMessageToConversation(oldCallState: CallState) {
        
        let businessInjector = BusinessInjector()
        let entityManager = businessInjector.entityManager
        let utilities = ConversationActions(businessInjector: businessInjector)
        
        switch state {
        case .idle:
            break
        case .sendOffer:
            break
        case .receivedOffer:
            break
        case .incomingRinging:
            break
        case .outgoingRinging:
            break
        case .sendAnswer:
            break
        case .receivedAnswer:
            break
        case .initializing:
            break
        case .calling:
            break
        case .reconnecting:
            break
        case .ended, .remoteEnded:
            // add call message
            if ProcessInfoHelper.isRunningForScreenshots {
                return
            }
            
            // if remoteEnded is incoming at the same time like user tap on end call button
            if oldCallState == .ended || oldCallState == .remoteEnded {
                return
            }
            
            guard let identity = contactIdentity else {
                return
            }
            
            var messageRead = true
            var systemMessage: SystemMessage?
            
            entityManager.performSyncBlockAndSafe {
                let conversation = entityManager.conversation(for: identity, createIfNotExisting: true)
                systemMessage = entityManager.entityCreator.systemMessage(for: conversation)
                
                systemMessage?.type = NSNumber(value: kSystemMessageCallEnded)
                
                var callInfo = [
                    "DateString": DateFormatter.shortStyleTimeNoDate(Date()),
                    "CallInitiator": NSNumber(booleanLiteral: self.isCallInitiator()),
                ] as [String: Any]
                if self.callDurationTime > 0 {
                    callInfo["CallTime"] = DateFormatter.timeFormatted(self.callDurationTime)
                }
                
                if !self.isCallInitiator(),
                   self.callDurationTime == 0 {
                    messageRead = false
                    conversation?.lastUpdate = Date.now
                }
                
                do {
                    let callInfoData = try JSONSerialization.data(withJSONObject: callInfo, options: .prettyPrinted)
                    systemMessage?.arg = callInfoData
                    systemMessage?.isOwn = NSNumber(booleanLiteral: self.isCallInitiator())
                    systemMessage?.conversation = conversation
                    
                    if let contact = entityManager.entityFetcher.contact(for: identity) {
                        let cont = Contact(contactEntity: contact)
                        systemMessage?.forwardSecurityMode = NSNumber(value: cont.forwardSecurityMode.rawValue)
                    }
                    
                    if messageRead {
                        systemMessage?.read = NSNumber(booleanLiteral: true)
                        systemMessage?.readDate = Date()
                    }
                    conversation?.lastMessage = systemMessage
                    utilities.unarchive(conversation!)
                }
                catch {
                    DDLogError(
                        "VoipCallService: [cid=\(self.currentCallID()?.callID ?? 0)]: Can't add call info to system message"
                    )
                }
            }
            if !messageRead {
                DispatchQueue.main.async {
                    let notificationManager = NotificationManager()
                    notificationManager.updateUnreadMessagesCount(baseMessage: systemMessage)
                }
            }
        case .rejected:
            // add call message
            entityManager.performBlockAndWait {
                guard let identity = self.contactIdentity,
                      let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                    return
                }
                self.addRejectedMessageToConversation(contactIdentity: identity, reason: kSystemMessageCallRejected)
                utilities.unarchive(conversation)
            }
        case .rejectedTimeout:
            // add call message
            entityManager.performBlockAndWait {
                guard let identity = self.contactIdentity,
                      let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                    return
                }
                let reason = self.isCallInitiator() ? kSystemMessageCallRejectedTimeout : kSystemMessageCallMissed
                self.addRejectedMessageToConversation(contactIdentity: identity, reason: reason)
                utilities.unarchive(conversation)
            }
        case .rejectedBusy:
            entityManager.performBlockAndWait {
                // add call message
                guard let identity = self.contactIdentity,
                      let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                    return
                }
                let reason = self.isCallInitiator() ? kSystemMessageCallRejectedBusy : kSystemMessageCallMissed
                self.addRejectedMessageToConversation(contactIdentity: identity, reason: reason)
                utilities.unarchive(conversation)
            }
        case .rejectedOffHours:
            entityManager.performBlockAndWait {
                // add call message
                guard let identity = self.contactIdentity,
                      let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                    return
                }
                let reason = self.isCallInitiator() ? kSystemMessageCallRejectedOffHours : kSystemMessageCallMissed
                self.addRejectedMessageToConversation(contactIdentity: identity, reason: reason)
                utilities.unarchive(conversation)
            }
        case .rejectedUnknown:
            entityManager.performBlockAndWait {
                // add call message
                guard let identity = self.contactIdentity,
                      let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                    return
                }
                let reason = self.isCallInitiator() ? kSystemMessageCallRejectedUnknown : kSystemMessageCallMissed
                self.addRejectedMessageToConversation(contactIdentity: identity, reason: reason)
                utilities.unarchive(conversation)
            }
        case .rejectedDisabled:
            // add call message
            entityManager.performBlockAndWait {
                if self.callInitiator {
                    guard let identity = self.contactIdentity,
                          let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                        return
                    }
                    self.addRejectedMessageToConversation(
                        contactIdentity: identity,
                        reason: kSystemMessageCallRejectedDisabled
                    )
                    utilities.unarchive(conversation)
                }
            }
        case .microphoneDisabled:
            entityManager.performBlockAndWait {
                guard let identity = self.contactIdentity,
                      let conversation = entityManager.conversation(for: identity, createIfNotExisting: true) else {
                    return
                }
                utilities.unarchive(conversation)
            }
        }
    }
    
    private func addRejectedMessageToConversation(contactIdentity: String, reason: Int) {
        var systemMessage: SystemMessage?
        
        let entityManager = BusinessInjector().entityManager
        entityManager.performSyncBlockAndSafe {
            if let conversation = entityManager.conversation(for: contactIdentity, createIfNotExisting: true),
               let contact = entityManager.entityFetcher.contact(for: contactIdentity) {
                systemMessage = entityManager.entityCreator.systemMessage(for: conversation)
                systemMessage?.type = NSNumber(value: reason)
                let callInfo = [
                    "DateString": DateFormatter.shortStyleTimeNoDate(Date()),
                    "CallInitiator": NSNumber(booleanLiteral: self.isCallInitiator()),
                ] as [String: Any]
                do {
                    let callInfoData = try JSONSerialization.data(withJSONObject: callInfo, options: .prettyPrinted)
                    systemMessage?.arg = callInfoData
                    systemMessage?.isOwn = NSNumber(booleanLiteral: self.isCallInitiator())
                    systemMessage?.conversation = conversation
                    
                    let cont = Contact(contactEntity: contact)
                    systemMessage?.forwardSecurityMode = NSNumber(value: cont.forwardSecurityMode.rawValue)
                    
                    conversation.lastMessage = systemMessage
                    if reason == kSystemMessageCallMissed || reason == kSystemMessageCallRejectedBusy || reason ==
                        kSystemMessageCallRejectedTimeout || reason == kSystemMessageCallRejectedDisabled { }
                    else {
                        systemMessage?.read = true
                        systemMessage?.readDate = Date()
                    }
                    
                    if reason == kSystemMessageCallMissed {
                        conversation.lastUpdate = Date.now
                    }
                }
                catch {
                    print(error)
                }
            }
            else {
                DDLogNotice("Threema Calls: Can't add rejected message because conversation is nil")
            }
        }
        if reason == kSystemMessageCallMissed || reason == kSystemMessageCallRejectedBusy || reason ==
            kSystemMessageCallRejectedTimeout || reason == kSystemMessageCallRejectedDisabled {
            DispatchQueue.main.async {
                let notificationManager = NotificationManager()
                notificationManager.updateUnreadMessagesCount(baseMessage: systemMessage)
            }
        }
    }
    
    private func addUnknownCallIcecandidatesMessages(message: VoIPCallIceCandidatesMessage) {
        receivedIceCandidatesLockQueue.sync {
            guard let identity = message.contactIdentity else {
                return
            }
            if var contactCandidates = receivedUnknowCallIcecandidatesMessages[identity] {
                contactCandidates.append(message)
            }
            else {
                receivedUnknowCallIcecandidatesMessages[identity] = [message]
            }
        }
    }
    
    private func sdpContainsVideo(sdp: RTCSessionDescription?) -> Bool {
        guard sdp != nil else {
            return false
        }
        return sdp!.sdp.contains("m=video")
    }
    
    private func callFailed() {
        if !peerWasConnected {
            // show error as notification
            if let identity = contactIdentity {
                let hangupMessage = VoIPCallHangupMessage(contactIdentity: identity, callID: callID!, completion: nil)
                voIPCallSender.sendVoIPCallHangup(hangupMessage: hangupMessage)
            }
            NotificationPresenterWrapper.shared.present(type: .connectedCallError)
        }
        else {
            NotificationPresenterWrapper.shared.present(type: .notConnectedCallError)
        }
        
        invalidateCallFailedTimer()
        invalidateTransportExpectedStableTimer()
        handleTones(state: .ended, oldState: .reconnecting)
        callKitManager?.endCall()
        dismissCallView()
        disconnectPeerConnection()
    }
    
    private func callCantCreateOffer(error: Error?) {
        DDLogNotice(
            "VoipCallService: [cid=\(callID?.callID ?? 0)]: Can't create offer (\(error?.localizedDescription ?? "error is missing")"
        )
        NotificationPresenterWrapper.shared.present(type: .callCreationError)
        invalidateCallFailedTimer()
        invalidateTransportExpectedStableTimer()
        handleTones(state: .ended, oldState: .reconnecting)
        callKitManager?.endCall()
        dismissCallView()
        disconnectPeerConnection()
    }
    
    /// Displays a no internet message and cancels the call
    private func noInternetConnectionError() {
        DDLogNotice(
            "VoipCallService: [cid=\(callID?.callID ?? 0)]: Can't create offer (no internet connection)"
        )
        NotificationPresenterWrapper.shared.present(type: .noConnection)
        invalidateCallFailedTimer()
        invalidateTransportExpectedStableTimer()
        handleTones(state: .ended, oldState: .reconnecting)
        callKitManager?.endCall()
        dismissCallView()
        disconnectPeerConnection()
    }
}

// MARK: - VoIPCallPeerConnectionClientDelegate

extension VoIPCallService: VoIPCallPeerConnectionClientDelegate {
    func peerconnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, startTransportExpectedStableTimer: Bool) {
        DispatchQueue.main.async {
            // Schedule to expect the transport to be 'stable' after 10s. This is a workaround
            // for intermittent FAILED states.
            if self.transportExpectedStableTimer != nil {
                DDLogError(
                    "VoipCallService: [cid=\(self.callID?.callID ?? 0)]: transportExpectedStableTimer was already running!"
                )
                self.transportExpectedStableTimer?.invalidate()
                self.transportExpectedStableTimer = nil
            }
            
            self.transportExpectedStableTimer = Timer.scheduledTimer(
                withTimeInterval: self.kCallFailedTimeout,
                repeats: false,
                block: { _ in
                    self.callFailed()
                }
            )
        }
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, removedCandidates: [RTCIceCandidate]) {
        // ICE candidate messages are currently allowed to have a "removed" flag. However, this is non-standard.
        // Ignore generated ICE candidates with removed set to true coming from libwebrtc
        
        for candidate in removedCandidates {
            let reason = shouldAdd(candidate: candidate, local: true).1 ?? "unknown"
            DDLogNotice(
                "VoipCallService: [cid=\(callID?.callID ?? 0)]: Ignoring local ICE candidate (\(reason)): \(candidate.sdp)"
            )
        }
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, addedCandidate: RTCIceCandidate) {
        if contactIdentity != nil {
            handleLocalIceCandidates([addedCandidate])
        }
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, changeState: CallState) {
        state = changeState
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, audioMuted: Bool) {
        self.audioMuted = audioMuted
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, speakerActive: Bool) {
        self.speakerActive = speakerActive
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: speakerActive ? .videoChat : .voiceChat,
                options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.overrideOutputAudioPort(speakerActive ? .speaker : .none)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }
        catch {
            print(error.localizedDescription)
        }
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, receivingVideo: Bool) {
        if isReceivingVideo != receivingVideo {
            isReceivingVideo = receivingVideo
        }
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, shouldShowCellularCallWarning: Bool) {
        self.shouldShowCellularCallWarning = shouldShowCellularCallWarning
    }
    
    func peerConnectionClient(
        _ client: VoIPCallPeerConnectionClientProtocol,
        didChangeConnectionState state: RTCPeerConnectionState
    ) {
        let oldState = self.state
        
        switch state {
        case .new:
            break
        case .connecting:
            if self.state != .sendOffer, self.state != .outgoingRinging, self.state != .incomingRinging {
                self.state = .initializing
            }
        case .connected:
            invalidateCallFailedTimer()
            invalidateTransportExpectedStableTimer()
            
            peerWasConnected = true
            if self.state != .reconnecting {
                self.state = .calling
                DispatchQueue.main.async {
                    self.callDurationTime = 0
                    self.callDurationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                        self.callDurationTime = self.callDurationTime + 1
                        if self.state == .calling {
                            self.callViewController?.voIPCallDurationChanged(self.callDurationTime)
                        }
                        else {
                            self.callViewController?.voIPCallStatusChanged(state: self.state, oldState: self.state)
                            DDLogWarn(
                                "VoipCallService: [cid=\(self.callID?.callID ?? 0)]: State is connected, but shows something different \(self.state.description())"
                            )
                        }
                        if NavigationBarPromptHandler.isCallActiveInBackground == true {
                            NotificationCenter.default.post(
                                name: NSNotification.Name(kNotificationNavigationItemPromptShouldChange),
                                object: self.callDurationTime
                            )
                        }
                    })
                }
                callViewController?.startDebugMode(connection: client.peerConnection)
                callKitManager?.callConnected()
            }
            else {
                self.state = .calling
            }
            activateRTCAudio()
        case .failed:
            if callFailedTimer != nil {
                invalidateCallFailedTimer()
                invalidateTransportExpectedStableTimer()
            }
            
            if transportExpectedStableTimer == nil {
                DDLogError(
                    "VoipCallService: [cid=\(callID?.callID ?? 0)]: transportExpectedStableFuture is nil as transport connection state moved into FAILED"
                )
                callFailed()
            }
        case .disconnected:
            if callFailedTimer == nil {
                self.state = .reconnecting
                
                // start timer and wait if state change back to connected
                DispatchQueue.main.async {
                    self.invalidateCallFailedTimer()
                    self.callFailedTimer = Timer.scheduledTimer(
                        withTimeInterval: self.kCallFailedTimeout,
                        repeats: false,
                        block: { _ in
                            self.callFailed()
                        }
                    )
                }
            }
        case .closed:
            break
        @unknown default:
            break
        }
        if oldState != self.state {
            DDLogNotice(
                "VoipCallService: [cid=\(callID?.callID ?? 0)]: Call state change from \(oldState.description()) to \(self.state.description())"
            )
        }
    }
    
    func peerConnectionClient(_ client: VoIPCallPeerConnectionClientProtocol, didReceiveData: Data) {
        let threemaVideoCallSignalingMessage = CallsignalingProtocol
            .decodeThreemaVideoCallSignalingMessage(didReceiveData)
        
        if let videoQualityProfile = threemaVideoCallSignalingMessage.videoQualityProfile {
            peerConnectionClient.remoteVideoQualityProfile = videoQualityProfile
        }
        
        if let captureState = threemaVideoCallSignalingMessage.captureStateChange {
            switch captureState.device {
            case .camera:
                switch captureState.state {
                case .off:
                    peerConnectionClient.isRemoteVideoActivated = false
                case .on:
                    peerConnectionClient.isRemoteVideoActivated = true
                }
            default: break
            }
        }
        
        debugPrint(threemaVideoCallSignalingMessage)
    }
}

extension Array {
    func take(_ elementsCount: Int) -> [Element] {
        let min = Swift.min(elementsCount, count)
        return Array(self[0..<min])
    }
}
