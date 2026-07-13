import AVFoundation
import CocoaLumberjackSwift
import FileUtility

extension AVAssetExportSession: VideoExportSession {
    public func runExport() async throws -> URL {
        // Convert video to MPEG4 for compatibility with Android.
        await withCheckedContinuation { continuation in
            exportAsynchronously { continuation.resume() }
        }

        DDLogVerbose(
            "Export Complete \(status.rawValue) \(String(describing: error)) \(String(describing: outputURL))"
        )

        guard status == .completed, let outputURL else {
            if let outputURL {
                try? FileUtility.shared.delete(at: outputURL)
            }
            throw error ?? VideoExportError.failed
        }

        return outputURL
    }
}
