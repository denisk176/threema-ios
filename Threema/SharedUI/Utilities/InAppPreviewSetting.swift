import ThreemaFramework

protocol InAppPreviewSetting {
    var inAppPreview: Bool { get }
}

// MARK: - UserSettings + InAppPreviewSetting

extension UserSettings: InAppPreviewSetting { }
