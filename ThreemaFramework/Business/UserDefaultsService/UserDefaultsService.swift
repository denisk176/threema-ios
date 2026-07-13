import Foundation

public protocol UserDefaultsService: Sendable {
    func object(forKey: String) -> Any?
    func url(forKey: String) -> URL?
    func array(forKey: String) -> [Any]?
    func dictionary(forKey: String) -> [String: Any]?
    func string(forKey: String) -> String?
    func stringArray(forKey: String) -> [String]?
    func data(forKey: String) -> Data?
    func bool(forKey: String) -> Bool
    func integer(forKey: String) -> Int
    func float(forKey: String) -> Float
    func double(forKey: String) -> Double
    func dictionaryRepresentation() -> [String: Any]
    func set(_ value: Any?, forKey: String)
    func set(_ value: Float, forKey: String)
    func set(_ value: Double, forKey: String)
    func set(_ value: Int, forKey: String)
    func set(_ value: Bool, forKey: String)
    func set(_ url: URL?, forKey: String)
    func removeObject(forKey: String)
}
