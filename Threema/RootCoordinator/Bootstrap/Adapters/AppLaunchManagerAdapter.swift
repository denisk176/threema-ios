import CocoaLumberjackSwift
import FileUtility
import PushKit
import ThreemaFramework
import UIKit

// MARK: - AppLaunchManagerProtocol

@MainActor
protocol AppLaunchManagerProtocol: AnyObject {
    var isAppSetupCompleted: Bool { get }
    var hasPreexistingDatabaseFile: Bool { get }
    var isDatabaseEncrypted: Bool { get }
    var shouldDirectlyShowSetupWizard: Bool { get }
    var isBusinessApp: Bool { get }
    
    /// Runs the pre-launch setup required before any UI can be presented.
    /// This includes: BG task registration, PromiseKit config, crypto init,
    /// theme setup, notification setup, etc.
    /// - Parameter window: The window to configure themes for
    func runLaunchSetup(window: UIWindow)
    
    /// Runs the post-onboarding setup steps after identity creation/restoration.
    func runPostOnboardingSetup() async throws
}

// MARK: - AppLaunchManagerAdapter

final class AppLaunchManagerAdapter: AppLaunchManagerProtocol {
    
    private var manager: AppLaunchManager {
        AppLaunchManager.shared
    }
    
    var isAppSetupCompleted: Bool {
        manager.isAppSetupCompleted
    }
    
    var hasPreexistingDatabaseFile: Bool {
        AppSetup.hasPreexistingDatabaseFile
    }
    
    var isDatabaseEncrypted: Bool {
        DatabaseManager.isExistingDBEncrypted()
    }
    
    var shouldDirectlyShowSetupWizard: Bool {
        AppSetup.shouldDirectlyShowSetupWizard
    }
    
    var isBusinessApp: Bool {
        TargetManager.isBusinessApp
    }
    
    func runLaunchSetup(window: UIWindow) {
        // Register background tasks
        _ = ThreemaBGTaskManager.shared
        
        // Configure PromiseKit
        PromiseKitConfiguration.configurePromiseKit()
        
        // Initialize crypto
        _ = NaClCrypto.shared()
        
        // Setup server connector background state
        ServerConnector.shared().isAppInBackground = UIApplication.shared.applicationState == .background
        
        // Resolve theme
        Colors.resolveTheme()
        Colors.update(window: window)
        
        // Setup VoIP push registry
        let pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry.desiredPushTypes = [.voIP]

        LogManager.clearLoggerOutput(for: .appLaunchFileLog)
        LogManager.addLogger(for: .appLaunchFileLog)
    }
    
    // MARK: - Post-Onboarding Setup
    
    func runPostOnboardingSetup() async throws {
        deleteBackupData()
        
        LogManager.clearLoggerOutput(for: .appSetupStepsFileLog)
        LogManager.addLogger(for: .appSetupStepsFileLog)

        if TargetManager.isBusinessApp {
            await runWorkDataUpdate()
        }
        
        try await runAppSetupSteps()
        
        LogManager.removeLogger(for: .appSetupStepsFileLog)

        AppSetup.state = .complete
        
        LogManager.clearLoggerOutput(for: .appSetupStepsFileLog)
    }
    
    // MARK: - Private Helpers
    
    private func deleteBackupData() {
        let fileUtility = FileUtility()
        
        guard
            let backupURL = fileUtility.appDocumentsDirectory?
            .appendingPathComponent("safe-backup.json")
        else {
            return
        }
        
        fileUtility.deleteIfExists(at: backupURL)
    }
    
    private func runWorkDataUpdate() async {
        do {
            let fetcher = BusinessInjector.ui.workDataFetcher
            try await fetcher.checkUpdateWorkData(force: true, forceSendMDM: false)
        }
        catch {
            DDLogError("Error while checking for work data update post-onboarding: \(error)")
        }
    }
    
    private func runAppSetupSteps() async throws {
        try await AppSetupSteps().run()
    }
}
