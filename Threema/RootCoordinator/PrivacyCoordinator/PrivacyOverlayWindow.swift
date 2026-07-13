import UIKit

final class PrivacyOverlayWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = WindowLevel.privacy
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
}
