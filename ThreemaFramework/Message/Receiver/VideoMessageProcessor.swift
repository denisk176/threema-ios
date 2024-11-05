//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2021-2023 Threema GmbH
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
import PromiseKit

@objc class VideoMessageProcessor: NSObject {
    
    private let blobDownloader: BlobDownloader
    private let userSettings: UserSettingsProtocol
    private let entityManager: EntityManager
    
    enum VideoMessageProcessorError: Error {
        case downloadFailed(message: String)
        case messageNotFound(message: String)
    }
    
    @objc required init(
        blobDownloader: BlobDownloader,
        userSettings: UserSettingsProtocol,
        entityManager: EntityManager
    ) {
        self.blobDownloader = blobDownloader
        self.userSettings = userSettings
        self.entityManager = entityManager
    }

    @objc func downloadVideoThumbnail(
        videoMessageID: Data,
        in conversationManagedObjectID: NSManagedObjectID,
        thumbnailBlobID: Data,
        origin: BlobOrigin,
        maxBytesToDecrypt: Int,
        timeoutDownloadThumbnail: Int,
        completion: @escaping (Error?) -> Void
    ) {
        if timeoutDownloadThumbnail > 0 {
            race(
                downloadVideoThumbnail(
                    videoMessageID: videoMessageID,
                    in: conversationManagedObjectID,
                    origin: origin,
                    thumbnailBlobID: thumbnailBlobID,
                    maxBytesToDecrypt: maxBytesToDecrypt
                ),
                timeout(seconds: timeoutDownloadThumbnail)
            )
            .done(on: .global(), flags: .inheritQoS) {
                completion(nil)
            }
            .catch(on: .global(), flags: .inheritQoS, policy: .allErrors) { error in
                completion(error)
            }
        }
        else {
            downloadVideoThumbnail(
                videoMessageID: videoMessageID,
                in: conversationManagedObjectID,
                origin: origin,
                thumbnailBlobID: thumbnailBlobID,
                maxBytesToDecrypt: maxBytesToDecrypt
            )
            .done(on: .global(), flags: .inheritQoS) {
                completion(nil)
            }
            .catch(on: .global(), flags: .inheritQoS, policy: .allErrors) { error in
                completion(error)
            }
        }
    }
    
    func downloadVideoThumbnail(
        videoMessageID: Data,
        in conversationManagedObjectID: NSManagedObjectID,
        origin: BlobOrigin,
        thumbnailBlobID: Data,
        maxBytesToDecrypt: Int
    ) -> Promise<Void> {
        Promise { seal in
            // Download thumbnail
            self.blobDownloader.download(blobID: thumbnailBlobID, origin: origin) { data, error in
                if let error {
                    seal.reject(
                        VideoMessageProcessorError
                            .downloadFailed(message: "Download video thumbnail failed with error: \(error)")
                    )
                    return
                }

                guard let data else {
                    seal.reject(VideoMessageProcessorError.downloadFailed(message: "Download video thumbnail missing."))
                    return
                }
                
                self.entityManager.performAndWaitSave {
                    guard let conversation = self.entityManager.entityFetcher
                        .existingObject(with: conversationManagedObjectID) as? ConversationEntity,
                        let msg = self.entityManager.entityFetcher.message(
                            with: videoMessageID,
                            conversation: conversation
                        ) as? VideoMessageEntity
                    else {
                        seal.reject(
                            VideoMessageProcessorError
                                .downloadFailed(message: "message id: \(videoMessageID.hexString)")
                        )
                        return
                    }

                    if maxBytesToDecrypt > 0, data.count > maxBytesToDecrypt {
                        DDLogWarn("Video message (size:\(data.count)) to large to decrypt")
                        seal.fulfill_()
                        return
                    }

                    // Decrypt blob
                    let thumbnailData: Data? = NaClCrypto.shared()!.symmetricDecryptData(
                        data,
                        withKey: msg.encryptionKey,
                        nonce: ThreemaProtocol.nonce02
                    )

                    if let thumbnailData,
                       let thumbnailImage = UIImage(data: thumbnailData),
                       let thumbnailJpegData = thumbnailImage.jpegData(compressionQuality: 1.0) {
                        
                        let thumbnail: ImageDataEntity? = msg.thumbnail == nil ? self.entityManager.entityCreator
                            .imageDataEntity() : msg.thumbnail
                        
                        thumbnail?.data = thumbnailJpegData
                        thumbnail?.width = Int16(thumbnailImage.size.width)
                        thumbnail?.height = Int16(thumbnailImage.size.height)

                        msg.thumbnail = thumbnail

                        // Mark blob as done, if is group message and Multi Device is activated then always on `local`
                        // origin
                        if !msg.isGroupMessage {
                            self.blobDownloader.markDownloadDone(for: thumbnailBlobID, origin: msg.blobOrigin)
                        }
                        else if self.userSettings.enableMultiDevice {
                            self.blobDownloader.markDownloadDone(for: thumbnailBlobID, origin: .local)
                        }

                        seal.fulfill_()
                    }
                    else {
                        seal.reject(VideoMessageProcessorError.downloadFailed(message: "Blob decryption failed"))
                    }
                }
            }
        }
    }
    
    private func timeout(seconds: Int) -> Promise<Void> {
        Promise { seal in
            after(seconds: TimeInterval(seconds))
                .done {
                    let error = VideoMessageProcessorError.downloadFailed(message: "Timeout")
                    seal.reject(error)
                }
                .catch { error in
                    seal.reject(error)
                }
        }
    }
}
