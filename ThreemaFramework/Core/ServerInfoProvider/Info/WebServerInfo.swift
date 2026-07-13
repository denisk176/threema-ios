public final class WebServerInfo: NSObject {
    public let url: String
    public let overrideSaltyRtcHost: String?
    public let overrideSaltyRtcPort: Int?
    
    init(url: String, overrideSaltyRtcHost: String?, overrideSaltyRtcPort: Int?) {
        self.url = url
        self.overrideSaltyRtcHost = overrideSaltyRtcHost
        self.overrideSaltyRtcPort = overrideSaltyRtcPort
    }
}
