import CocoaLumberjackSwift
import UIKit

/// Centralized accessor for app-level shared state (window, top view controller,
/// tab bar controller, lifecycle flags, etc). Routes between the legacy
/// `AppDelegate`-owned hierarchy and the `SceneDelegate` / `RootCoordinator`
/// hierarchy gated by `SCENE_DELEGATE_ROOT_COORDINATOR_DEVELOPMENT`.
///
/// Call sites should depend on this type rather than reaching into
/// `AppDelegate.shared()` directly — the latter crashes under the scene flow
/// because `UIApplication.shared.delegate` is an app delegate for the scene
/// life cycle instead of the `AppDelegate`.
@MainActor
enum SharedAppProvider {
    
    static var isSceneDelegateDevelopment: Bool {
        #if SCENE_DELEGATE_ROOT_COORDINATOR_DEVELOPMENT
            return true
        #else
            return false
        #endif
    }

    // MARK: - Navigation

    static var tabBarController: UITabBarController? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.rootCoordinator?.tabBarController
        }
        else {
            AppDelegate.shared()?.tabBarController()
        }
    }

    static var currentTopViewController: UIViewController? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.currentTopViewController
        }
        else {
            AppDelegate.shared()?.currentTopViewController()
        }
    }

    static var window: UIWindow? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.window
        }
        else {
            AppDelegate.shared()?.window
        }
    }

    // MARK: - Lifecycle

    static var isAppActive: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isActive == true
        }
        else {
            AppDelegate.shared()?.active == true
        }
    }

    static var isAppLocked: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isAppLocked == true
        }
        else {
            AppDelegate.shared()?.isAppLocked == true
        }
    }

    // MARK: - Coordinator access

    static var appCoordinator: AppCoordinator? {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.rootCoordinator?.appCoordinator
        }
        else {
            AppDelegate.shared()?.appCoordinator as? AppCoordinator
        }
    }

    static func execute(_ closure: (AppCoordinator) -> Void) {
        if let appCoordinator {
            closure(appCoordinator)
        }
        else {
            fatalError("AppCoordinator not found.")
        }
    }

    // MARK: - License

    static var isPresentingEnterLicense: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isPresentingEnterLicense == true
        }
        else {
            AppDelegate.shared()?.isPresentingEnterLicense() == true
        }
    }

    static var isPresentingKeyGeneration: Bool {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.isPresentingKeyGeneration == true
        }
        else {
            AppDelegate.shared()?.isPresentingKeyGeneration() == true
        }
    }

    static func presentIDBackupRestore() {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.presentIDBackupRestore()
        }
        else {
            AppDelegate.shared()?.presentIDBackupRestore()
        }
    }

    // MARK: - Passcode

    static func presentPasscodeView() {
        if isSceneDelegateDevelopment {
            SceneDelegate.current?.presentPasscodeView()
        }
        else {
            AppDelegate.shared()?.presentPasscodeView()
        }
    }

    // MARK: - Main-thread bridge

    /// Synchronously executes a closure on the main thread, asserting MainActor
    /// isolation. Use from nonisolated callers that need to read @MainActor
    /// properties (e.g., `isCompactSizeClass`) without converting the caller
    /// to async.
    nonisolated static func onMain<T: Sendable>(_ closure: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                closure()
            }
        }
        else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    closure()
                }
            }
        }
    }

    // MARK: - Class-level bridges

    static var isAppInBackground: Bool {
        SceneDelegate.isAppInBackground
    }

    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    static var alertViewShown: UIAlertController? {
        window?.rootViewController?.presentedViewController as? UIAlertController
    }

    // MARK: - Trait collection

    static var isCompactSizeClass: Bool {
        appCoordinator?.splitViewController.traitCollection.horizontalSizeClass == .compact
    }

    // MARK: - Orientation (per-scene)

    static var orientationLock: UIInterfaceOrientationMask {
        get {
            if isSceneDelegateDevelopment {
                SceneDelegate.current?.orientationLock ?? .all
            }
            else {
                AppDelegate.shared()?.orientationLock ?? .all
            }
        }
        set {
            if isSceneDelegateDevelopment {
                SceneDelegate.current?.orientationLock = newValue
            }
            else {
                AppDelegate.shared()?.orientationLock = newValue
            }
        }
    }
}
