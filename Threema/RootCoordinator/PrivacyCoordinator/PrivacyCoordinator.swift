import Coordinator
import UIKit

@MainActor
protocol PrivacyCoordinatorProtocol: AnyObject {
    /// Show the privacy overlay if needed.
    func showOverlay()
    
    /// Hide the privacy overlay.
    func hideOverlay()
}

@MainActor
final class PrivacyCoordinator: Coordinator, PrivacyCoordinatorProtocol {

    var childCoordinators: [any Coordinator] = []

    // PrivacyCoordinator lives on its own window, not in the parent's view hierarchy.
    var rootViewController: UIViewController { UIViewController() }

    private weak var windowScene: UIWindowScene?
    private var overlayWindow: PrivacyOverlayWindow?

    private let isPasscodeRequired: () -> Bool
    private let isRemoteSecretEnabled: () -> Bool

    private var shouldShowOverlay: Bool {
        isPasscodeRequired() || isRemoteSecretEnabled()
    }

    init(
        windowScene: UIWindowScene,
        isPasscodeRequired: @escaping () -> Bool,
        isRemoteSecretEnabled: @escaping () -> Bool
    ) {
        self.windowScene = windowScene
        self.isPasscodeRequired = isPasscodeRequired
        self.isRemoteSecretEnabled = isRemoteSecretEnabled
    }

    func start() {
        showOverlay()
    }

    func showOverlay() {
        guard shouldShowOverlay else {
            return
        }
        guard overlayWindow == nil, let windowScene else {
            return
        }

        let window = PrivacyOverlayWindow(windowScene: windowScene)
        window.rootViewController = PrivacyViewController()
        window.isHidden = false
        overlayWindow = window
    }

    func hideOverlay() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
    }
}
