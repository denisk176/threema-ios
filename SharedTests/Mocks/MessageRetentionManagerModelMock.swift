import Foundation
import ThreemaFramework

final class MessageRetentionManagerModelMock: MessageRetentionManagerModelProtocol {
    var selection = 0
    
    var isMDM = false
    
    func deleteOldMessages() { }
    
    func numberOfMessagesToDelete(for retentionDays: Int?) -> Int {
        0
    }
    
    func set(_ days: Int) {
        selection = days
    }
}
