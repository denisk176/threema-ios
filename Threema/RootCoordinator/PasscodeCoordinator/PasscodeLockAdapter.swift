import ThreemaFramework

@MainActor
protocol PasscodeLockProtocol: AnyObject {
    func isPasscodeRequired() -> Bool
    func isWithinGracePeriod() -> Bool
    func isBiometricAuthenticationEnabled() -> Bool
}

final class KKPasscodeLockAdapter: PasscodeLockProtocol {
    func isPasscodeRequired() -> Bool {
        KKPasscodeLock.shared().isPasscodeRequired()
    }
    
    func isWithinGracePeriod() -> Bool {
        KKPasscodeLock.shared().isWithinGracePeriod()
    }
    
    func isBiometricAuthenticationEnabled() -> Bool {
        KKPasscodeLock.shared().isTouchIDOn()
    }
}
