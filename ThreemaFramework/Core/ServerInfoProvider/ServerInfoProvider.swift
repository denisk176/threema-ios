@objc public protocol ServerInfoProvider {
    func chatServer(ipv6: Bool, completionHandler: @escaping (ChatServerInfo?, Error?) -> Void)
    func directoryServer(ipv6: Bool, completionHandler: @escaping (DirectoryServerInfo?, Error?) -> Void)
    func blobServer(ipv6: Bool, completionHandler: @escaping (BlobServerInfo?, Error?) -> Void)
    func workServer(ipv6: Bool, completionHandler: @escaping (WorkServerInfo?, Error?) -> Void)
    func workBaseServer(completionHandler: @escaping (WorkServerInfo?, Error?) -> Void)
    func avatarServer(ipv6: Bool, completionHandler: @escaping (AvatarServerInfo?, Error?) -> Void)
    func safeServer(ipv6: Bool, completionHandler: @escaping (SafeServerInfo?, Error?) -> Void)
    func mediatorServer(
        deviceGroupIDFirstByteHex: String,
        completionHandler: @escaping (MediatorServerInfo?, Error?) -> Void
    )
    func webServer(ipv6: Bool, completionHandler: @escaping (WebServerInfo?, Error?) -> Void)
    func rendezvousServer(completionHandler: @escaping (RendezvousServerInfo?, Error?) -> Void)
    func domains(completionHandler: @escaping ([Domain]?, Error?) -> Void)
    func mapsServer(completionHandler: @escaping (MapsServerInfo?, Error?) -> Void)
    func doRecovery() async throws
}

extension ServerInfoProvider {
    // Simplest way to get work server URL for now
    public func workServerURL() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            // IPv6 check cannot be applied here as we are not allowed to load the settings
            workServer(ipv6: true) { workServerInfo, error in
                if let workServerInfo {
                    continuation.resume(returning: workServerInfo.url)
                }
                else if let error {
                    continuation.resume(throwing: error)
                }
                else {
                    assertionFailure("This should never be reached")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // Simplest way to get work base server URL for now
    public func workBaseServerURL() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            workBaseServer { workServerInfo, error in
                if let workServerInfo {
                    continuation.resume(returning: workServerInfo.url)
                }
                else if let error {
                    continuation.resume(throwing: error)
                }
                else {
                    assertionFailure("This should never be reached")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
