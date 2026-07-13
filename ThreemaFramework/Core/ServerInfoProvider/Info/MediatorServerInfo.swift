public final class MediatorServerInfo: NSObject {
    @objc public let url: String
    @objc public let blob: BlobServerInfo

    init(deviceGroupIDFirstByteHex: String, url: String, blob: BlobServerInfo) {
        let prefix4 = String(deviceGroupIDFirstByteHex.prefix(1)).lowercased()
        let prefix8 = deviceGroupIDFirstByteHex.lowercased()
        
        func replacePrefixesInURL(url: String) -> String {
            url
                .replacingOccurrences(of: "{deviceGroupIdPrefix4}", with: prefix4)
                .replacingOccurrences(of: "{deviceGroupIdPrefix8}", with: prefix8)
        }
        
        self.url = replacePrefixesInURL(url: url)
        self.blob = BlobServerInfo(
            downloadURL: replacePrefixesInURL(url: blob.downloadURL),
            uploadURL: replacePrefixesInURL(url: blob.uploadURL),
            doneURL: replacePrefixesInURL(url: blob.doneURL)
        )
    }
}
