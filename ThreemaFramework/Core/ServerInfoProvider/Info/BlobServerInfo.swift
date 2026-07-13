public final class BlobServerInfo: NSObject {
    public let downloadURL: String
    public let uploadURL: String
    public let doneURL: String
    
    init(downloadURL: String, uploadURL: String, doneURL: String) {
        self.downloadURL = downloadURL
        self.uploadURL = uploadURL
        self.doneURL = doneURL
    }
}
