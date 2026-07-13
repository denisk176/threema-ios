import CocoaLumberjackSwift
import FileUtility
import Foundation
import libthreemaSwift
import ZipArchive

public enum LogManager {
    // MARK: - Public Types

    public enum Destination: String {
        case appLaunchFileLog = "app-launch.log"
        case appSetupStepsFileLog = "app-setup-steps.log"
        case debugDirectoryLog = "debug_log" // directory
        case safeRestoreFileLog = "safe-restore.log"
    }

    // MARK: Private Types

    /// Log levels definition for Swift. Includes new Notice Log level at the end,
    /// to not break the standard Log levels like in <CocoaLumberjack/DDLog.h>
    private enum DDLogLevelCustom: UInt {
        case err = 0b0000001
        case warn = 0b0000010
        case info = 0b0000100
        case verbose = 0b0001000
        case debug = 0b0010000
        case notice = 0b0100000
    }

    private enum LogManagerError: Error {
        case fileUtilityUnavailable
    }

    // MARK: - Private properties

    private static var isDebug = false
    private static var fileUtility: (any FileUtilityProtocol)? { FileUtility.shared }
    private static var libthreemaLogDispatcherInitialized = false
    private static let libthreemaLogDispatcher = LibthreemaLogDispatcher()

    private static let logZipFileName = "debug_log.zip"

    // MARK: - Public methods

    public static func initializeGlobalLogger(debug: Bool) {
        isDebug = debug
        if isDebug {
            DDOSLogger.sharedInstance.logFormatter = LogFormatterCustom()
            DDLog.add(DDOSLogger.sharedInstance, with: logLevel())
        }

        // Add Debug Logger is enabled by user
        if let validationLogging = UserSettings.shared()?.validationLogging, validationLogging {
            addLogger(for: .debugDirectoryLog)
        }
        else {
            removeLogger(for: .debugDirectoryLog)
        }

        // libthreema logging

        // Workaround: This should only be initialized once, however this function is called for every received
        // notification in the notification extension
        // TODO: (IOS-5355) Only initialize libthreema once
        if !libthreemaLogDispatcherInitialized {
            // .trace should only be used to closely debug something
            let libthreemaMinLogLevel: LogLevel = debug ? .debug : .info
            libthreemaSwift.initialize(
                minLogLevel: libthreemaMinLogLevel,
                logDispatcher: libthreemaLogDispatcher
            )
            libthreemaLogDispatcherInitialized = true
        }
    }

    public static func addLogger(for destination: Destination) {
        guard let destinationURL = url(for: destination), findLoggers(destinationURL).isEmpty else {
            return
        }
        do {
            let logger: any DDLogger = destinationURL.hasDirectoryPath
                ? try createCustomDirectoryLogger(url: destinationURL)
                : createCustomFileLogger(url: destinationURL)
            DDLog.add(logger, with: logLevel())
        }
        catch {
            DDLogError("Logger couldn't be created at \(destinationURL.path): \(error)")
        }
    }

    public static func removeLogger(for destination: Destination) {
        for logger in findLoggers(url(for: destination)) {
            DDLog.remove(logger)
        }
    }

    public static func clearLoggerOutput(for destination: Destination) {
        guard let destinationURL = url(for: destination), let fileUtility else {
            return
        }

        // Drain any active logger for this destination before deleting files underneath it, otherwise in-flight writes
        // can land on stale file handles. Flush while the loggers are still registered.
        let activeLoggers = findLoggers(destinationURL)
        if !activeLoggers.isEmpty {
            DDLog.flushLog()
        }
        for logger in activeLoggers {
            DDLog.remove(logger)
        }

        if destinationURL.hasDirectoryPath {
            fileUtility.removeItemsInDirectory(directoryURL: destinationURL)
        }
        else {
            fileUtility.deleteIfExists(at: destinationURL)
        }

        if !activeLoggers.isEmpty {
            addLogger(for: destination)
        }
    }

    public static func zipDebugLog() -> URL? {
        guard getLoggerOutputSize(for: .debugDirectoryLog) > 0,
              let debugLogDir = url(for: .debugDirectoryLog),
              let fileUtility
        else {
            return nil
        }

        // Remove active debug loggers so file contents don't shift under SSZipArchive. Flush before
        // removal so pending writes are drained while the loggers are still registered.
        let activeLoggers = findLoggers(debugLogDir)
        if !activeLoggers.isEmpty {
            DDLog.flushLog()
        }
        for logger in activeLoggers {
            DDLog.remove(logger)
        }

        let zipURL = fileUtility.appTemporaryDirectory.appendingPathComponent(logZipFileName)

        try? fileUtility.delete(at: zipURL)

        let zipSucceeded = SSZipArchive.createZipFile(
            atPath: zipURL.path,
            withContentsOfDirectory: debugLogDir.path
        )

        // Restore debug logger
        if !activeLoggers.isEmpty {
            addLogger(for: .debugDirectoryLog)
        }

        guard zipSucceeded else {
            DDLogError("Failed to zip debug log")
            try? fileUtility.delete(at: zipURL)
            return nil
        }

        return zipURL
    }

    public static func getLoggerOutputSize(for destination: Destination) -> Int64 {
        guard let destinationURL = url(for: destination), let fileUtility else {
            return 0
        }

        if destinationURL.hasDirectoryPath {
            return debugLogDirectorySize(at: destinationURL)
        }

        return fileUtility.fileSizeInBytes(fileURL: destinationURL) ?? 0
    }

    // MARK: - Private methods

    private static func url(for destination: Destination) -> URL? {
        guard let fileUtility else {
            return nil
        }
        let documentsDirectory = fileUtility.appDocumentsDirectory
        let appDataDirectory = fileUtility.appDataDirectory(appGroupID: AppGroup.groupID())

        switch destination {
        case .debugDirectoryLog:
            return appDataDirectory?.appendingPathComponent(destination.rawValue, isDirectory: true)

        // Setup logs that should be accessible via Finder/iTunes (document directory), they are helpful if setup fails
        case .safeRestoreFileLog, .appSetupStepsFileLog, .appLaunchFileLog:
            return documentsDirectory?.appendingPathComponent(destination.rawValue)
        }
    }

    /// Default log level is Error, Warning and Notice
    private static let defaultLogLevel: DDLogLevel = {
        let level = DDLogLevelCustom.err.rawValue | DDLogLevelCustom.warn.rawValue | DDLogLevelCustom.notice.rawValue
        return DDLogLevel(rawValue: level) ?? .all
    }()

    private static func logLevel() -> DDLogLevel {
        isDebug ? .all : defaultLogLevel
    }

    private static func findLoggers(_ destinationURL: URL?) -> [DDLogger] {
        guard let destinationURL else {
            return []
        }
        let normalized = destinationURL.standardizedFileURL

        var fileLoggers: [DDLogger] = []
        for logger in DDLog.allLoggers {
            if let fileLogger = logger as? FileLoggerCustom,
               fileLogger.logFile.standardizedFileURL == normalized {
                fileLoggers.append(logger)
            }
            else if let fileLogger = logger as? DDFileLogger,
                    URL(fileURLWithPath: fileLogger.logFileManager.logsDirectory, isDirectory: true)
                    .standardizedFileURL == normalized {
                fileLoggers.append(logger)
            }
            else {
                // no-op
            }
        }
        return fileLoggers
    }

    private static func createCustomDirectoryLogger(url: URL) throws -> any DDLogger {
        guard let fileUtility else {
            throw LogManagerError.fileUtilityUnavailable
        }

        // Total on-disk budget for the debug log (one active file + at most one archive).
        let debugLogMaximumFileSize: UInt64 = 10 * 1024 * 1024
        let debugLogMaximumNumberOfFiles: UInt = 2
        let debugLogDiskQuota: UInt64 = 20 * 1024 * 1024

        try fileUtility.mkDir(at: url, withIntermediateDirectories: true, attributes: nil)

        let fileManager = DDLogFileManagerDefault(logsDirectory: url.path)
        fileManager.maximumNumberOfLogFiles = debugLogMaximumNumberOfFiles
        fileManager.logFilesDiskQuota = debugLogDiskQuota

        let logger = DDFileLogger(logFileManager: fileManager)
        logger.maximumFileSize = debugLogMaximumFileSize
        logger.rollingFrequency = 0 // Disable time-based rolling — only roll on size.
        logger.logFormatter = LogFormatterCustom()

        return logger
    }

    private static func createCustomFileLogger(url: URL) -> any DDLogger {
        FileLoggerCustom(logFile: url)
    }

    private static func debugLogDirectorySize(at destinationURL: URL) -> Int64 {
        guard let fileUtility,
              let files = try? fileUtility.contentsOfDirectory(
                  at: destinationURL,
                  includingPropertiesForKeys: [.fileSizeKey],
                  options: []
              )
        else {
            return 0
        }
        var total: Int64 = 0
        for file in files {
            if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
