public enum RemoteSecretFileEncryptionWhitelist {
    // MARK: - Public properties

    public static let whiteList: [String] = files + directories.map { "/\($0)/" }

    // MARK: - Private properties

    private static let files: [String] = [
        "config.oppf",
        "work_server_url.cache",
        "idbackup.txt",
        "ThreemaData.sqlite",
        "RepairedThreemaData.sqlite",
        "threema-fs.db",
        "APP_SETUP_NOT_COMPLETED",

        LogManager.Destination.appLaunchFileLog.rawValue,
        LogManager.Destination.appSetupStepsFileLog.rawValue,
        LogManager.Destination.safeRestoreFileLog.rawValue,
    ]

    private static let directories: [String] = [
        "unencrypted",
        LogManager.Destination.debugDirectoryLog.rawValue,
    ]
}
