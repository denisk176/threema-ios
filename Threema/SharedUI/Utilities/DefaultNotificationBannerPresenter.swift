import ThreemaFramework

protocol NotificationBannerPresenting {
    func newBanner(baseMessage: BaseMessageEntity)
    func dismissAllNotifications(for identifier: String)
}

struct DefaultNotificationBannerPresenter: NotificationBannerPresenting {
    func newBanner(baseMessage: BaseMessageEntity) {
        NotificationBannerHelper.newBanner(baseMessage: baseMessage)
    }

    func dismissAllNotifications(for identifier: String) {
        NotificationBannerHelper.dismissAllNotifications(for: identifier)
    }
}
