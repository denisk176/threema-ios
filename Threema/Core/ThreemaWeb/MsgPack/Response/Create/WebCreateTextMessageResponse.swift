//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2018-2025 Threema GmbH
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

class WebCreateTextMessageResponse: WebAbstractMessage {
    
    var message: BaseMessageEntity?
    var type: String
    var id: String
    var messageID: String?
    
    init(message: BaseMessageEntity, request: WebCreateTextMessageRequest) {
        self.message = message
        self.type = request.type
        if request.groupID != nil {
            self.id = request.groupID!.hexEncodedString()
        }
        else {
            self.id = request.id!
        }
        
        self.messageID = message.id.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        
        let tmpArgs: [AnyHashable: Any?] = ["type": type, "id": id]
        let tmpData: [AnyHashable: Any?] = ["messageId": messageID!] as [String: Any]
        let success: Bool = request.tmpError == nil
        let error: String? = request.tmpError
        let tmpAck = WebAbstractMessageAcknowledgement(request.requestID, success, error)
        
        super.init(
            messageType: "create",
            messageSubType: "textMessage",
            requestID: nil,
            ack: tmpAck,
            args: tmpArgs,
            data: tmpData
        )
    }
    
    init(request: WebCreateTextMessageRequest) {
        self.type = request.type
        if request.groupID != nil {
            self.id = request.groupID!.hexEncodedString()
        }
        else {
            self.id = request.id!
        }
        
        let tmpArgs: [AnyHashable: Any?] = ["type": type, "id": id]
        let success: Bool = request.tmpError == nil
        let error: String? = request.tmpError
        let tmpAck = WebAbstractMessageAcknowledgement(request.requestID, success, error)
        
        super.init(
            messageType: "create",
            messageSubType: "textMessage",
            requestID: nil,
            ack: tmpAck,
            args: tmpArgs,
            data: nil
        )
    }
}
