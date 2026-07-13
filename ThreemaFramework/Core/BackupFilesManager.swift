import CocoaLumberjackSwift
import FileUtility
import Foundation

@objc public final class BackupFilesManager: NSObject {

    private let fileUtility: FileUtilityProtocol

    @objc override public init() {
        self.fileUtility = FileUtility.shared
        super.init()
    }

    init(fileUtility: FileUtilityProtocol) {
        self.fileUtility = fileUtility
        super.init()
    }

    @objc public func setIsExcludedFromBackup(exclude: Bool) {
        let fileAndDirectoryNames = [
            DatabaseManager.databaseFileName,
            DatabaseManager.databaseSupportPath,
            DatabaseManager.databaseTemporaryExternalStoragePath,
            DatabaseManager.databaseRepairedFileName,
            DatabaseManager.databaseOldVersionPath,
            PendingUserNotificationManager.processedUserNotificationsFileName,
            SQLDHSessionStore.databaseName,
            LogManager.Destination.appSetupStepsFileLog.rawValue,
            LogManager.Destination.debugDirectoryLog.rawValue,
            LogManager.Destination.safeRestoreFileLog.rawValue,
            "safe-backup.json",
            "DoneMessages",
            "WebSessions",
            "PreviousContext",
        ]

        do {
            try fileUtility.backup(of: fileAndDirectoryNames, exclude: exclude, appGroupID: AppGroup.groupID())
        }
        catch {
            DDLogError("Failed set exclude flag for backup files: \(error)")
        }
    }
}
