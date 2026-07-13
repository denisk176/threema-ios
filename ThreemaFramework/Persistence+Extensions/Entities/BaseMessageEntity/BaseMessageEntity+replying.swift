import Foundation

extension BaseMessageEntity {
    /// Is replying of this message allowed?
    public var supportsReplying: Bool {
        !isDistributionListMessage
    }
}
