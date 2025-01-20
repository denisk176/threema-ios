//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2019-2025 Threema GmbH
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

public class VoIPCallSender {
    private let messageSender: MessageSenderProtocol
    private let myIdentityStore: MyIdentityStoreProtocol
    
    public init(messageSender: MessageSenderProtocol, myIdentityStore: MyIdentityStoreProtocol) {
        self.messageSender = messageSender
        self.myIdentityStore = myIdentityStore
    }
    
    public func sendVoIPCall(offer: VoIPCallOfferMessage) {
        let msg = BoxVoIPCallOfferMessage()
        do {
            msg.jsonData = try offer.encodeAsJson()
            msg.toIdentity = offer.contactIdentity
            msg.fromIdentity = myIdentityStore.identity

            DDLogNotice(
                "VoipCallService: [cid=\(offer.callID.callID)]: Call offer enqueued to \(offer.contactIdentity ?? "?")"
            )
            
            messageSender.sendMessage(abstractMessage: msg, isPersistent: false)
        }
        catch {
            DDLogError(
                "VoipCallService: [cid=\(offer.callID.callID)]: Can't send offer message to \(offer.contactIdentity ?? "?") -> \(error.localizedDescription)"
            )
        }
    }
    
    public func sendVoIPCall(answer: VoIPCallAnswerMessage) {
        let msg = BoxVoIPCallAnswerMessage()
        do {
            msg.jsonData = try answer.encodeAsJson()
            msg.toIdentity = answer.contactIdentity
            msg.fromIdentity = myIdentityStore.identity
            msg.isUserInteraction = answer.isUserInteraction
                        
            DDLogNotice(
                "VoipCallService: [cid=\(answer.callID.callID)]: Call answer enqueued to \(answer.contactIdentity ?? "?")"
            )

            messageSender.sendMessage(abstractMessage: msg, isPersistent: false)
        }
        catch {
            DDLogError(
                "VoipCallService: [cid=\(answer.callID.callID)]: Can't send answer message to \(answer.contactIdentity ?? "?") -> \(error.localizedDescription)"
            )
        }
    }

    public func sendVoIPCall(iceCandidates: VoIPCallIceCandidatesMessage) {
        let msg = BoxVoIPCallIceCandidatesMessage()
        do {
            msg.jsonData = try iceCandidates.encodeAsJson()
            msg.toIdentity = iceCandidates.contactIdentity
            msg.fromIdentity = myIdentityStore.identity
            
            DDLogNotice(
                "VoipCallService: [cid=\(iceCandidates.callID.callID)]: Call ICE candidate message enqueued to \(iceCandidates.contactIdentity ?? "?") (\(iceCandidates.candidates.count) candidates"
            )
            
            for candidate in iceCandidates.candidates {
                DDLogNotice(
                    "VoipCallService: [cid=\(iceCandidates.callID.callID)]: Outgoing ICE candidate: \(candidate.sdp)"
                )
            }

            messageSender.sendMessage(abstractMessage: msg, isPersistent: false)
        }
        catch {
            DDLogError(
                "VoipCallService: [cid=\(iceCandidates.callID.callID)]: Can't send ice candidates message \(iceCandidates.contactIdentity ?? "?") -> \(error.localizedDescription)"
            )
        }
    }
    
    public func sendVoIPCallHangup(hangupMessage: VoIPCallHangupMessage, wait: Bool = true) {
        if Thread.isMainThread, wait == true {
            let msg =
                "sendVoIPCallHangup may not be called on the main thread when wait is true. Wait will be disabled."
            assertionFailure(msg)
            DDLogError(msg)
        }
        
        let msg = BoxVoIPCallHangupMessage()
        do {
            msg.jsonData = try hangupMessage.encodeAsJson()
            msg.toIdentity = hangupMessage.contactIdentity
            msg.fromIdentity = myIdentityStore.identity
            
            DDLogNotice(
                "VoipCallService: [cid=\(hangupMessage.callID.callID)]: Call hangup message enqueued to \(hangupMessage.contactIdentity ?? "?")"
            )
        
            if wait, !Thread.isMainThread {
                var dispatchGroup: DispatchGroup? = DispatchGroup()
                dispatchGroup?.enter()
                
                messageSender.sendMessage(abstractMessage: msg, isPersistent: false, completion: {
                    dispatchGroup?.leave()
                    dispatchGroup = nil
                })
                
                // We only wait when there is a connection, or if it is being built up. Otherwise the UI freezes and one
                // cannot escape the situation.
                let state = ServerConnector.shared().connectionState
                let wait =
                    if state == .connecting || state == .connected || state == .loggedIn {
                        5
                    }
                    else {
                        10
                    }
                
                let result = dispatchGroup?.wait(timeout: .now() + .seconds(wait))
                
                if let result, result == .timedOut {
                    DDLogWarn("Sending hangup message timed out")
                }
            }
            else {
                messageSender.sendMessage(abstractMessage: msg, isPersistent: false)
            }
        }
        catch {
            DDLogError(
                "VoipCallService: [cid=\(hangupMessage.callID.callID)]: Can't send hangup message to \(hangupMessage.contactIdentity ?? "?") -> \(error.localizedDescription)"
            )
        }
    }
    
    public func sendVoIPCallRinging(ringingMessage: VoIPCallRingingMessage) {
        let msg = BoxVoIPCallRingingMessage()
        do {
            msg.jsonData = try ringingMessage.encodeAsJson()
            msg.toIdentity = ringingMessage.contactIdentity
            msg.fromIdentity = myIdentityStore.identity
            
            DDLogNotice(
                "VoipCallService: [cid=\(ringingMessage.callID.callID)]: Call ringing message enqueued to \(ringingMessage.contactIdentity ?? "?")"
            )

            messageSender.sendMessage(abstractMessage: msg, isPersistent: false)
        }
        catch {
            DDLogError(
                "VoipCallService: [cid=\(ringingMessage.callID.callID)]: Can't send call ringing message to \(ringingMessage.contactIdentity ?? "?") -> \(error.localizedDescription)"
            )
        }
    }
}
