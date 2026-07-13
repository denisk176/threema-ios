import Foundation

public protocol MessageRetentionManagerModelProtocol {
    var selection: Int { get set }
    var isMDM: Bool { get }
    func deleteOldMessages()
    func numberOfMessagesToDelete(for retentionDays: Int?) -> Int
    func set(_ days: Int)
}

extension MessageRetentionManagerModelProtocol {
    func deletionDate(_ days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: -days, to: Date.currentDate)
    }
}
