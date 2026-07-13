import Coordinator
import Keychain
import ThreemaEssentials
import ThreemaFramework

final class RootCoordinator: Coordinator {
    var childCoordinators: [any Coordinator] = []
    
    var appCoordinator: AppCoordinator? {
        childCoordinators.first(where: {
            $0 is AppCoordinator
        }) as? AppCoordinator
    }
    
    var tabBarController: UITabBarController? {
        appCoordinator?.tabBarController
    }
    
    private lazy var rootNavigationController: UINavigationController = {
        let navigationController = UINavigationController()
        navigationController.isNavigationBarHidden = true
        return navigationController
    }()
    
    private lazy var loadingCoordinator = LoadingCoordinator(
        viewModel: LoadingViewModel(),
        presentingNavigationViewController: rootNavigationController,
        window: window
    )
    
    var rootViewController: UIViewController {
        rootNavigationController
    }
    
    private let window: UIWindow
    private let windowScene: UIWindowScene
    private let bootstrap: BootstrapContainer
    private let launchManager: AppLaunchSequenceManager

    private var isSceneForeground: Bool {
        windowScene.activationState != .background
    }

    init(
        window: UIWindow,
        windowScene: UIWindowScene,
        bootstrap: BootstrapContainer
    ) {
        self.window = window
        self.windowScene = windowScene
        self.bootstrap = bootstrap
        self.launchManager = AppLaunchSequenceManager(bootstrap: bootstrap)
    }

    func start() {
        childCoordinators.append(loadingCoordinator)
        loadingCoordinator.start()
        
        Task { @MainActor [weak self] in
            await self?.performLaunchSequence()
        }
    }
    
    // MARK: - Scene Lifecycle

    func sceneWillEnterForeground() {
        requestReauthenticationIfNeeded()
        hidePrivacyOverlay()
        reconcileTypingObservation()
    }

    func sceneDidEnterBackground() {
        showPrivacyOverlay()
        reconcileTypingObservation()
    }

    // MARK: - Re-authentication

    func requestReauthenticationIfNeeded() {
        guard
            let appContainer = appCoordinator?.appContainer,
            !childCoordinators.contains(where: { $0 is PasscodeCoordinator })
        else {
            return
        }

        let passcodeLock = appContainer.passcodeLock
        guard
            passcodeLock.isPasscodeRequired(),
            !passcodeLock.isWithinGracePeriod()
        else {
            return
        }

        let passcodeCoordinator = PasscodeCoordinator(
            windowScene: windowScene,
            appContainer: appContainer,
            delegate: self
        )
        childCoordinators.append(passcodeCoordinator)
        passcodeCoordinator.start()
    }

    private func reconcileTypingObservation() {
        guard let manager = appCoordinator?.appContainer?.typingIndicatorManager else {
            return
        }
        if isSceneForeground {
            manager.startObserving()
        }
        else {
            manager.stopObserving()
        }
    }

    // MARK: - Privacy Overlay

    func showPrivacyOverlay() {
        guard !childCoordinators.contains(where: { $0 is PrivacyCoordinator }) else {
            return
        }
        let coordinator = PrivacyCoordinator(
            windowScene: windowScene,
            isPasscodeRequired: { [weak self] in
                self?.appCoordinator?.appContainer?.passcodeLock.isPasscodeRequired() == true
            },
            isRemoteSecretEnabled: {
                RemoteSecretProvider.isRemoteSecretEnabled
            }
        )
        childCoordinators.append(coordinator)
        coordinator.start()
    }

    func hidePrivacyOverlay() {
        guard let coordinator = childCoordinators.first(where: {
            $0 is PrivacyCoordinator
        }) as? PrivacyCoordinator else {
            return
        }
        coordinator.hideOverlay()
        childDidFinish(coordinator)
    }

    // MARK: - Launch Sequence
    
    @MainActor
    private func performLaunchSequence() async {
        loadingCoordinator.showLoading()
        
        bootstrap.appLaunchManager.runLaunchSetup(window: window)
        
        let result = await launchManager.run()
        await handleLaunchResult(result)
    }
    
    private func handleLaunchResult(_ result: AppLaunchSequenceManager.LaunchResult) async {
        switch result {
        case .needsOnboarding:
            await goToOnboarding()
            
        case let .needsPasscode(appContainer):
            await goToPasscode(appContainer: appContainer)
            
        case .needsRemoteSecretFetch:
            await handleRemoteSecretFetch()
            
        case .protectedDataUnavailable:
            showProtectedDataUnavailable()
            
        case let .ready(appContainer):
            await goToApp(appContainer: appContainer)
            
        case let .failed(error):
            showError(error)
        }
    }
    
    // MARK: - Transitions
    
    private func goToOnboarding() async {
        let remoteSecretResolver = RemoteSecretResolver(
            appLaunchManager: bootstrap.appLaunchManager,
            licenseStore: bootstrap.licenseStore.store,
            myIdentityStore: bootstrap.bootstrapIdentityStore.store,
            mdmSetup: MDMSetup(),
            flavorService: AppFlavorService(),
            hasPreexistingData: bootstrap.appLaunchManager.hasPreexistingDatabaseFile
        )
        let onboardingCoordinator = OnboardingCoordinator(
            bootstrap: bootstrap,
            delegate: self,
            window: window,
            remoteSecretResolver: remoteSecretResolver
        )
        
        childCoordinators.append(onboardingCoordinator)
        onboardingCoordinator.start()
        
        childDidFinish(loadingCoordinator)
    }
    
    private func goToPasscode(appContainer: AppDependencyContainer) async {
        let passcodeCoordinator = PasscodeCoordinator(
            windowScene: windowScene,
            appContainer: appContainer,
            delegate: self
        )
        childCoordinators.append(passcodeCoordinator)
        passcodeCoordinator.start()
        childDidFinish(loadingCoordinator)
    }
    
    /// Presents RemoteSecret fetch UI (spinner + error recovery) on the loading
    /// coordinator's navigation controller, then continues the launch sequence.
    private func handleRemoteSecretFetch() async {
        let navigationController = loadingCoordinator.presentingNavigationViewController
        
        let viewsManager = RemoteSecretInitializeViewsManager(
            navigationController: navigationController,
            showDeleteAfterRetries: 0
        )
        
        do {
            let identity = bootstrap.bootstrapIdentityStore.store.identity
                .map { ThreemaIdentity($0) }
            
            let remoteSecretManager = try await viewsManager.start(
                identity: identity,
                onDelete: { [weak self] in
                    try? self?.bootstrap.bootstrapKeychainManager.deleteAllItems()
                    exit(0)
                },
                onCancel: nil
            )
            
            // Restore loading view after fetch UI
            loadingCoordinator.showLoading()
            
            let result = await launchManager.continueAfterRemoteSecretFetch(
                remoteSecretManager: remoteSecretManager
            )
            await handleLaunchResult(result)
        }
        catch {
            loadingCoordinator.showLoading()
            showError(LaunchError.remoteSecretSetupFailed(error))
        }
    }
    
    private func goToApp(appContainer: AppDependencyContainer) async {
        let appCoordinator = AppCoordinator(
            window: window,
            appContainer: appContainer
        )
        childCoordinators.append(appCoordinator)

        window.rootViewController = appCoordinator.rootViewController
        window.makeKeyAndVisible()

        appCoordinator.start()
        childDidFinish(loadingCoordinator)

        reconcileTypingObservation()
    }
    
    private func showProtectedDataUnavailable() {
        loadingCoordinator.showError(
            message: "Protected data is not available. Please unlock your device.",
            isRetryable: true,
            onRetry: { [weak self] in
                Task {
                    await self?.performLaunchSequence()
                }
            }
        )
    }
    
    private func showError(_ error: LaunchError) {
        loadingCoordinator.showError(
            message: error.localizedDescription,
            isRetryable: error.isRetryable,
            onRetry: error.isRetryable
                ? { [weak self] in
                    Task {
                        await self?.performLaunchSequence()
                    }
                }
                : nil
        )
    }
}

// MARK: - PasscodeCoordinatorDelegate

extension RootCoordinator: PasscodeCoordinatorDelegate {

    func passcodeCoordinatorDidAuthenticate(
        _ coordinator: PasscodeCoordinator,
        appContainer: AppDependencyContainer,
        evaluatedPolicyDomainState: Data?
    ) {
        if let state = evaluatedPolicyDomainState {
            appContainer.businessInjector.userSettings.evaluatedPolicyDomainStateApp = state
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if appCoordinator != nil {
                // Re-auth: passcode window is gone, restore main window as key.
                window.makeKeyAndVisible()
            }
            else {
                // Launch-time auth: AppCoordinator doesn't exist yet.
                await goToApp(appContainer: appContainer)
            }
            childDidFinish(coordinator)
        }
    }

    func passcodeCoordinatorDidRequestErase(_ coordinator: PasscodeCoordinator) {
        Task { @MainActor in
            await DeleteRevokeIdentityManager.deleteLocalDataWithoutBusinessReady()
        }
    }
}

// MARK: - OnboardingCoordinatorDelegate

extension RootCoordinator: OnboardingCoordinatorDelegate {
    
    func onboardingDidComplete(_ coordinator: OnboardingCoordinator, appContainer: AppDependencyContainer) {
        Task { [weak self] in
            guard let self else {
                return
            }
            
            await goToApp(appContainer: appContainer)
            
            childDidFinish(coordinator)
        }
    }
}
