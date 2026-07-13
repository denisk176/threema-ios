import CocoaLumberjackSwift
import Foundation
import Photos
import PromiseKit
import ThreemaMacros

open class VideoPreviewItem: MediaPreviewItem {
    public typealias PreviewType = URL
    
    // MARK: Private Properties
        
    private(set) var exportSession: (any VideoExportSession)?
    private(set) var transcodedItem: URL?
    
    open var internalOriginalAsset: Promise<AVAsset> {
        Promise { seal in
            guard let itemURL else {
                seal.reject(MediaPreviewItem.LoadError.unknown)
                return
            }
            
            seal.fulfill(AVAsset(url: itemURL))
        }
    }
    
    override open var thumbnail: Promise<UIImage> {
        internalOriginalAsset.then { asset in
            self.getThumbnail(for: asset)
        }
    }
    
    private func getThumbnail(for avasset: AVAsset) -> Promise<UIImage> {
        Promise<Void>().then(on: itemQueue, flags: [.barrier]) { () -> Promise<UIImage> in
            Promise { seal in
                if let internalThumbnail = self.internalThumbnail {
                    seal.fulfill(internalThumbnail)
                }
                guard let image = MediaConverter.getThumbnailForVideo(avasset) else {
                    seal.reject(MediaPreviewItem.LoadError.unknown)
                    return
                }
                self.internalThumbnail = image
                seal.fulfill(image)
            }
        }
    }

    public var item: Promise<PreviewType> {
        if let transcodedItem {
            return Promise { $0.fulfill(transcodedItem) }
        }

        return internalOriginalAsset.then { (asset: AVAsset) -> Promise<PreviewType> in
            guard let outputURL = MediaConverter.getAssetOutputURL() else {
                return Promise { $0.reject(MediaPreviewItem.LoadError.unknown) }
            }

            return Promise { seal in
                Task {
                    let session: any VideoExportSession
                    do {
                        session = try await VideoConversionHelper()
                            .getAVAssetExportSession(from: asset, outputURL: outputURL)
                    }
                    catch {
                        seal.reject(MediaPreviewItem.LoadError.unknown)
                        return
                    }

                    do {
                        let url = try await self.convertVideo(exportSession: session)
                        seal.fulfill(url)
                    }
                    catch {
                        seal.reject(error)
                    }
                }
            }
        }
    }

    @available(*, deprecated, message: "item should be used instead")
    open func getTranscodedItem() -> URL? {
        let sema = DispatchSemaphore(value: 0)
        var url: URL?
        _ = item.done(on: DispatchQueue.global()) { newURL in
            url = newURL
            sema.signal()
        }
        sema.wait()
        return url
    }
    
    override open func getAccessibilityDescription() -> String? {
        let text = #localize("video")
        return text
    }
    
    open func getOriginalItem() -> URL? {
        itemURL
    }
    
    // MARK: Private functions
    
    private func convertVideo(exportSession: any VideoExportSession) async throws -> URL {
        self.exportSession = exportSession
        let url = try await exportSession.runExport()
        self.transcodedItem = url
        return url
    }
}
