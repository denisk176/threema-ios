import CocoaLumberjackSwift
import Darwin
import Foundation

final class FileLoggerCustom: DDAbstractLogger {
    let logFile: URL

    /// Swift-side reference to the formatter, used on the logging hot path.
    ///
    /// `DDAbstractLogger.logFormatter` cannot be read from `log(message:)`: its accessor
    /// serialises through the logger queue that the callback already runs on, so the read
    /// would deadlock. Objective-C subclasses sidestep this by reading the ivar directly,
    /// which Swift cannot do for an inherited Objective-C ivar.
    private let logFormatterCustom: LogFormatterCustom

    init(logFile: URL) {
        self.logFile = logFile
        let formatter = LogFormatterCustom()
        self.logFormatterCustom = formatter
        super.init()
        self.logFormatter = formatter
    }

    /// Called by CocoaLumberjack on the logger queue, serialised per logger instance.
    /// Each `FileLoggerCustom` writes to its own file, so no cross-instance lock is needed.
    override func log(message logMessage: DDLogMessage) {
        let formatted = logFormatterCustom.format(message: logMessage) ?? logMessage.message
        guard let data = (formatted + "\n").data(using: .utf8) else {
            return
        }

        guard let file = fopen(logFile.path, "a") else {
            return
        }
        defer { fclose(file) }

        _ = data.withUnsafeBytes { buffer in
            fwrite(buffer.baseAddress, 1, data.count, file)
        }
        fsync(fileno(file))
    }
}
