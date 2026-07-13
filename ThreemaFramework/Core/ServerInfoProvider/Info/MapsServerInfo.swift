public final class MapsServerInfo: NSObject {
    public let poiNamesURL: String
    public let poiAroundURL: String
    
    init(poiNamesURL: String, poiAroundURL: String) {
        self.poiNamesURL = poiNamesURL
        self.poiAroundURL = poiAroundURL
    }
}
