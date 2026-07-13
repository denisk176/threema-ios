import Foundation

enum VideoExportError: Error {
    case failed
}

/// Abstraction over the two transcoding engines we use when sending videos:
/// `AVAssetExportSession` (passthrough / low quality) and `VideoTranscoder`
/// (bitrate-targeted re-encode). Callers only need progress, cancellation and a
/// way to run the export to completion, so they can stay engine-agnostic.
public protocol VideoExportSession: AnyObject {
    /// Encoding progress in the range `0...1`.
    var progress: Float { get }

    /// The URL the converted file is written to.
    var outputURL: URL? { get }

    /// Cancels an in-flight export.
    func cancelExport()

    /// Runs the export to completion and returns the output file URL.
    ///
    /// Named `runExport()` rather than `export()` to avoid colliding with
    /// `AVAssetExportSession`'s own `export()` on the conforming extension.
    /// - Throws: the underlying error (or ``VideoExportError/failed``) if the
    ///   export fails or is cancelled.
    func runExport() async throws -> URL
}
