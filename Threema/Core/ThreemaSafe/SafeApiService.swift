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

@objc class SafeApiService: NSObject {
    
    enum SafeApiError: Error {
        case invalidServerURL
        case requestFailed(message: String)
        case uploadTempFileCouldNotBeSaved(error: NSError)
    }
    
    func testServer(
        server: URL,
        user: String?,
        password: String?,
        completionHandler: @escaping (() throws -> Data) -> Void
    ) {

        getHttpClient(user: user, password: password) { client in
            client
                .downloadData(
                    url: server.appendingPathComponent("config"),
                    contentType: .json
                ) { data, response, error in
                
                    let result = self.processResponse(data: data, response: response, error: error)
                    if let responseData = result.data {
                        completionHandler { responseData }
                    }
                    if let responseErrorMessage = result.errorMessage {
                        completionHandler { throw SafeApiError.requestFailed(message: responseErrorMessage) }
                    }
                }
        }
    }
    
    func delete(server: URL, user: String?, password: String?, completion: @escaping (String?) -> Void) {
        var errorMessage: String?
                
        DispatchQueue.global(qos: .background).async {
            self.getHttpClient(user: user, password: password) { client in
                client.delete(url: server) { data, response, error in
                    
                    let result = self.processResponse(data: data, response: response, error: error)
                    if let responseErrorMessage = result.errorMessage {
                        errorMessage = responseErrorMessage
                    }
                    completion(errorMessage)
                }
            }
        }
    }
    
    func upload(
        backup: URL,
        user: String?,
        password: String?,
        encryptedData: [UInt8],
        completionHandler: @escaping (Data?, String?) -> Void
    ) {
        getHttpClient(user: user, password: password) { client in
            client.uploadData(url: backup, data: Data(encryptedData)) { data, response, error in
                let result = self.processResponse(data: data, response: response, error: error)
                completionHandler(result.data, result.errorMessage)
            }
        }
    }
    
    func download(
        backup: URL,
        user: String?,
        password: String?,
        completionHandler: @escaping (() throws -> Data?) -> Void
    ) {
        getHttpClient(user: user, password: password) { client in
            client.downloadData(url: backup, contentType: .octetStream) { data, response, error in
                let result = self.processResponse(data: data, response: response, error: error)
                if let responseData = result.data {
                    completionHandler { responseData }
                }
                if let responseErrorMessage = result.errorMessage {
                    completionHandler { throw SafeApiError.requestFailed(message: responseErrorMessage) }
                }
            }
        }
    }
    
    private func processResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> (data: Data?, errorMessage: String?) {
        var errorMessage: String?
        
        if let error {
            errorMessage = error.localizedDescription
            return (nil, errorMessage)
        }
        guard let response = response as? HTTPURLResponse else {
            errorMessage = "response is missing"
            if let data {
                print("\(String(describing: String(data: data, encoding: .utf8)))")
            }
            return (nil, errorMessage)
        }
        
        if !(200...299).contains(response.statusCode) {
            errorMessage = "response code \(response.statusCode)"
            if let data {
                print("\(String(describing: String(data: data, encoding: .utf8)))")
            }
            return (nil, errorMessage)
        }
        
        guard let data else {
            errorMessage = "response data/config is missing"
            return (nil, errorMessage)
        }

        return (data, nil)
    }
    
    private func getHttpClient(user: String?, password: String?, completion: @escaping (HTTPClient) -> Void) {
        if user != nil, password != nil {
            completion(HTTPClient(user: user, password: password))
        }
        else {
            AuthTokenManager.shared().obtainToken { authToken, _ in
                if authToken != nil {
                    let authorization = "Token " + authToken!
                    completion(HTTPClient(authorization: authorization))
                }
                else {
                    completion(HTTPClient(user: user, password: password))
                }
            }
        }
    }
}
