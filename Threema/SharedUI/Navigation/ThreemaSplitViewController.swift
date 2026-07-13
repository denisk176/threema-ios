import SwiftUI
import UIKit

final class ThreemaSplitViewController: UISplitViewController {
    
    private(set) lazy var threemaTabBarController = ThreemaTabBarController()
    private lazy var navigationManager = ThreemaSplitViewNavigationManager()
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard (presentedViewController is PortraitNavigationController) == false else {
            return []
        }
        
        if isCollapsed {
            return .allButUpsideDown
        }
        else {
            return .all
        }
    }

    // MARK: - Lifecycle Methods
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        
        preferredDisplayMode = .oneBesideSecondary
        presentsWithGesture = false
        
        displayModeButtonItem.customView = UIView()
        displayModeButtonItem.isEnabled = false
        displayModeButtonItem.isHidden = true
        
        navigationManager.configure(
            with: self,
            tabBarController: threemaTabBarController
        )
    }
    
    // MARK: - Public functions

    func setViewControllers(
        _ viewControllers: [UIViewController],
        for item: ThreemaTab
    ) {
        navigationManager.thetaStack.store(
            stack: viewControllers,
            for: item
        )
    }
    
    func switchTabIfNeeded(to item: ThreemaTab) {
        guard threemaTabBarController.selectedIndex != item.rawValue else {
            return
        }

        navigationManager.storeCurrentTabStack()
        /// Non-animated: see `ThreemaSplitViewNavigationManager.tabBarController(_:shouldSelect:)`.
        UIView.performWithoutAnimation {
            threemaTabBarController.selectedIndex = item.rawValue
        }
        navigationManager.restoreTabStack(for: item)
    }
    
    func navigationController(
        for item: ThreemaTab
    ) -> UINavigationController? {
        if isCollapsed {
            threemaTabBarController.navigationController(
                for: item
            )
        }
        else {
            viewControllers.last as? UINavigationController
        }
    }
    
    func isTopControllerChat(for contact: ContactEntity?) -> Bool {
        guard
            threemaTabBarController.selectedThreemaTab == .conversations,
            let contact,
            let navigationController = navigationController(for: .conversations),
            let chatViewController = navigationController.topViewController as? ChatViewController
        else {
            return false
        }
        
        return chatViewController.isChat(for: contact)
    }

    /// Clears the secondary column for the given tab, showing the empty placeholder.
    /// Also stores an empty stack in thetaStack for consistency across tab switches / resize.
    func clearSecondaryColumn(for item: ThreemaTab) {
        guard
            isCollapsed == false,
            let secondaryNav = navigationController(for: item)
        else {
            return
        }

        secondaryNav.setViewControllers(
            [ThreemaLogoViewControllerFactory.threemaLogoViewController],
            animated: false
        )

        setViewControllers([], for: item)
    }
}
