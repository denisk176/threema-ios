import CocoaLumberjackSwift
import FileUtility
import ThreemaFramework
import ThreemaMacros

struct PreviewUnavailableViewModel {
    private let fileMessageEntity: FileMessageEntity
    private let mdmManager: MDMSetup

    var thumbnailSymbolName: String {
        "document.fill"
    }
    
    var fileName: String? {
        fileMessageEntity.fileName
    }
    
    var fileSizeText: String? {
        guard let size = fileMessageEntity.fileSize?.floatValue else {
            return nil
        }
        return ThreemaUtility.formatDataLength(size)
    }
        
    let shareButtonName: String = #localize("share")
    
    var isShareable: Bool {
        mdmManager.disableShareMedia() == false
    }
    
    private var shareableItem: UIActivityItemSource? {
        guard let data = BaseMessageEntityMessageShareContentMapper.mapToContent(
            from: fileMessageEntity,
            fileUtility: FileUtility.shared
        ) else {
            return nil
        }
        
        return UIActivityHelperFactory.makeItemSource(type: .messageActivity(data))
    }
    
    init(
        fileMessageEntity: FileMessageEntity,
        mdmManager: MDMSetup = MDMSetup()
    ) {
        self.fileMessageEntity = fileMessageEntity
        self.mdmManager = mdmManager
    }
    
    // A bit a hacky way to show share sheet in SwiftUI for types, that don't support `Transferable`
    // TODO: (IOS-5599) Adapt (file) messages to `Transferable` protocol
    @MainActor
    func shareFile() {
        guard isShareable else {
            DDLogVerbose("Item not shareable.")
            return
        }
        
        guard let shareableItem else {
            DDLogVerbose("Shareable item is nil.")
            return
        }
                
        guard let topViewController = SharedAppProvider.currentTopViewController else {
            DDLogError("`SharedAppProvider.currentTopViewController` not available.")
            return
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareableItem],
            applicationActivities: nil
        )
        
        if topViewController.traitCollection.horizontalSizeClass == .regular {
            activityViewController.popoverPresentationController?.sourceView = topViewController.view
            activityViewController.popoverPresentationController?.sourceRect = CGRectMake(
                topViewController.view.bounds.maxX,
                topViewController.view.bounds.midY,
                0,
                0
            )
        }
        
        topViewController.present(activityViewController, animated: true)
    }
}
