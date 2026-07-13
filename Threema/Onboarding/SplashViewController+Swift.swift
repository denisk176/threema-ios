import Foundation
import SwiftUI
import ThreemaFramework
import UIKit

extension SplashViewController: SetupAppDelegate {
    @MainActor
    func encryptedDataDetected() {
        if SharedAppProvider.isSceneDelegateDevelopment {
            /// In the coordinator flow, RS resolution is handled by OnboardingCoordinator
            /// which calls showEncryptedDataDetected() directly. This path is unreachable.
            assertionFailure("encryptedDataDetected should not be called in coordinator flow")
            return
        }
        else {
            let window = SharedAppProvider.window
            let viewC = UIHostingController(rootView: RemoteSecretEncryptedDataView())
            let navC = UINavigationController(rootViewController: viewC)
            window?.rootViewController = navC
        }
    }
    
    func mismatchCancelled() {
        assertionFailure("Should not be reached")
    }

    @objc func addAppSetupStepsLogger() {
        LogManager.addLogger(for: .appSetupStepsFileLog)
    }

    @objc func removeAppSetupStepsLogger() {
        LogManager.removeLogger(for: .appSetupStepsFileLog)
    }

    @objc func clearAppSetupStepsLoggerOutput() {
        LogManager.clearLoggerOutput(for: .appSetupStepsFileLog)
    }
}
