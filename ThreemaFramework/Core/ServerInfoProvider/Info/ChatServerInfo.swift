public final class ChatServerInfo: NSObject {
    @objc public let serverNamePrefix: String
    @objc public let serverNameSuffix: String
    @objc public let serverPorts: [Int]
    @objc public let useServerGroups: Bool
    @objc public let publicKey: Data
    @objc public let publicKeyAlt: Data
    
    init(
        serverNamePrefix: String,
        serverNameSuffix: String,
        serverPorts: [Int],
        useServerGroups: Bool,
        publicKey: Data,
        publicKeyAlt: Data
    ) {
        self.serverNamePrefix = serverNamePrefix
        self.serverNameSuffix = serverNameSuffix
        self.serverPorts = serverPorts
        self.useServerGroups = useServerGroups
        self.publicKey = publicKey
        self.publicKeyAlt = publicKeyAlt
    }
}
