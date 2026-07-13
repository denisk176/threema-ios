import AVFoundation
import CocoaLumberjackSwift
import FileUtility
import Foundation

final class VideoConversionHelper: NSObject {
    private let userSettings: any UserSettingsProtocol
    private let outputDirectoryURL: URL

    // MARK: - Internal Nested Types
    
    enum VideoConversionError: Error {
        case missingTrack
        case failedToCreateExportSession
        case invalidVideoBitrate
        case invalidDuration
    }
    
    enum VideoQualitySetting {
        case low
        case high
        case original
    }

    /// Fraction of `kMaxFileSize` we aim for, leaving a 10% safety margin so the
    /// converted file does not accidentally exceed the limit.
    private static let fileSizeLimitFactor = 0.90

    /// Estimated container overhead for the video in bytes (same as on Android).
    private static let fileOverhead = Double(48 * 1024)

    #if DEBUG
        init(
            userSettings: any UserSettingsProtocol,
            outputDirectoryURL: URL
        ) {
            self.userSettings = userSettings
            self.outputDirectoryURL = outputDirectoryURL
        }
    #endif
    
    @objc override init() {
        self.userSettings = UserSettings.shared()
        self.outputDirectoryURL = FileUtility.shared.appTemporaryDirectory
    }

    /// The maximum duration for a video at the lowest possible quality in minutes.
    @objc public static var videoMaxDurationInMinutes: Double {
        let maxFileSizeInBits = Int32(kMaxFileSize * 8)

        /// Estimated file overhead for the video (same as in Android)
        /// Use for estimating final file size of the video
        let fileOverhead = Int32(48 * 1024)

        return Double((maxFileSizeInBits - fileOverhead) / ((kVideoBitrateLow + kAudioBitrateLow) * 60))
    }

    /// Target output size in bytes: `kMaxFileSize` minus the safety margin.
    private static var targetFileSize: Double {
        Double(kMaxFileSize) * fileSizeLimitFactor
    }

    // MARK: - Functions
    
    @objc func videoHasAllowedSize(at url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        
        var allowed = false
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            allowed = await (self.getEstimatedVideoFileSize(for: asset) != nil)
            semaphore.signal()
        }
        semaphore.wait()
        
        return allowed
    }
    
    func getEstimatedVideoFileSize(for url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        
        var size: Double?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            size = await self.getEstimatedVideoFileSize(for: asset)
            semaphore.signal()
        }
        semaphore.wait()

        return size
    }
    
    func getAVAssetExportSession(from asset: AVAsset, outputURL: URL) async throws -> VideoExportSession {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            DDLogError("No video track found")
            throw VideoConversionError.missingTrack
        }

        switch videoQualitySetting {
        case .low:
            return try createExportSession(presetName: AVAssetExportPresetLowQuality, asset: asset, outputURL: outputURL)

        case .high:
            return try await presetExportSession(
                presetNames: [AVAssetExportPresetMediumQuality, AVAssetExportPresetLowQuality],
                asset: asset,
                outputURL: outputURL
            )

        case .original:
            return try await originalExportSession(asset: asset, videoTrack: videoTrack, outputURL: outputURL)
        }
    }

    // MARK: Private Properties

    private var videoQualitySetting: VideoQualitySetting {
        guard let videoQualitySettingsString = userSettings.videoQuality else {
            return .high
        }

        switch videoQualitySettingsString {
        case "low":
            return .low
        case "high":
            return .high
        case "original":
            return .original
        default:
            return .high
        }
    }

    /// Returns the first preset whose output fits within the file-size limit.
    private func presetExportSession(
        presetNames: [String],
        asset: AVAsset,
        outputURL: URL
    ) async throws -> VideoExportSession {
        for presetName in presetNames {
            do {
                let session = try createExportSession(presetName: presetName, asset: asset, outputURL: outputURL)
                let estimatedSize = try await session.estimatedOutputFileLengthInBytes
                if estimatedSize > 0, estimatedSize <= kMaxFileSize {
                    return session
                }
            }
            catch {
                continue
            }
        }

        throw VideoConversionError.failedToCreateExportSession
    }

    /// Builds the engine for `.original`: pass the source through untouched when
    /// it already fits, otherwise re-encode at the native resolution with a
    /// bitrate computed to fill the file-size budget (hardware accelerated).
    private func originalExportSession(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        outputURL: URL
    ) async throws -> VideoExportSession {
        let info = try await loadSourceInfo(asset: asset, videoTrack: videoTrack)
        
        // The share extension avoids passthrough due to tighter resource limits.
        let allowPassthrough = AppGroup.getCurrentType() == AppGroupTypeApp

        // If the original already fits under the limit, send it untouched. The fit
        // check uses the source data rates (cheap) instead of asking AVFoundation
        // to analyze the whole asset.
        if allowPassthrough,
           info.originalSizeEstimate <= Double(kMaxFileSize) {
            return try createExportSession(
                presetName: AVAssetExportPresetPassthrough,
                asset: asset,
                outputURL: outputURL
            )
        }

        let audioBitrate = Int(kAudioBitrateHigh)
        let audioChannels = Int(kAudioChannelsHigh)

        // Distribute the file-size budget (minus container overhead and audio)
        // over the duration to get the average video bitrate.
        let budgetBits = Self.targetFileSize * 8
        let overheadBits = Self.fileOverhead * 8
        let audioBits = Double(audioBitrate) * info.durationSeconds
        let targetVideoBitrate = (budgetBits - overheadBits - audioBits) / info.durationSeconds

        // Never re-encode above the source bitrate: it cannot improve quality and
        // would only grow the file.
        var videoBitrate = targetVideoBitrate
        if info.videoRate > 0 {
            videoBitrate = min(videoBitrate, info.videoRate)
        }
        
        guard videoBitrate > 0 else {
            throw VideoConversionError.invalidVideoBitrate
        }

        // Preserve the source resolution — only the bitrate is reduced to fit.
        let renderSize = targetRenderSize(for: info.naturalSize, maxSide: .greatestFiniteMagnitude)

        return VideoTranscoder(
            asset: asset,
            outputURL: outputURL,
            videoBitrate: Int(videoBitrate),
            audioBitrate: audioBitrate,
            audioChannels: audioChannels,
            renderSize: renderSize,
            durationSeconds: info.durationSeconds
        )
    }

    /// Cheaply-loaded facts about the source needed to plan the conversion.
    private struct SourceInfo {
        let durationSeconds: Double
        let videoRate: Double
        let audioRate: Double
        let naturalSize: CGSize

        /// Approximate size of the untouched source in bytes (data rates × duration
        /// plus container overhead). Cheap to compute and good enough to decide
        /// whether the original already fits.
        var originalSizeEstimate: Double {
            (videoRate + audioRate) * durationSeconds / 8 + VideoConversionHelper.fileOverhead
        }
    }

    /// Loads only the lightweight track metadata (duration, data rates, size) we
    /// need to plan a conversion — no expensive whole-asset analysis.
    private func loadSourceInfo(asset: AVAsset, videoTrack: AVAssetTrack) async throws -> SourceInfo {
        guard let duration = try? await asset.load(.duration) else {
            throw VideoConversionError.invalidDuration
        }
        
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds > 0 else {
            throw VideoConversionError.invalidDuration
        }

        let videoRate = try await Double(videoTrack.load(.estimatedDataRate))
        let naturalSize = try await videoTrack.load(.naturalSize)

        var audioRate = 0.0
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            audioRate = try await Double(audioTrack.load(.estimatedDataRate))
        }

        return SourceInfo(
            durationSeconds: durationSeconds,
            videoRate: videoRate,
            audioRate: audioRate,
            naturalSize: naturalSize
        )
    }

    /// Scales `naturalSize` so its longest side is at most `maxSide`, never
    /// upscaling, and rounds to even dimensions (required by H.264).
    private func targetRenderSize(for naturalSize: CGSize, maxSide: CGFloat) -> CGSize {
        let width = abs(naturalSize.width)
        let height = abs(naturalSize.height)
        guard width > 0, height > 0 else {
            return naturalSize
        }

        let longest = max(width, height)
        let scale = longest > maxSide ? maxSide / longest : 1.0

        return CGSize(
            width: evenValue(width * scale),
            height: evenValue(height * scale)
        )
    }

    private func evenValue(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded(.down))
        return CGFloat(rounded - (rounded % 2))
    }

    private func createExportSession(
        presetName: String,
        asset: AVAsset,
        outputURL: URL
    ) throws -> AVAssetExportSession {

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoConversionError.failedToCreateExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.shouldOptimizeForNetworkUse = true
        let fileType: AVFileType = .mp4
        exportSession.outputFileType = fileType
        exportSession.fileLengthLimit = Int64(kMaxFileSize)
        // Strip metadata as aggressively as possible: `.forSharing()` scrubs
        // identifying items (e.g. location) — important for the passthrough path
        // where stream/track metadata would otherwise be copied verbatim — and an
        // empty `metadata` array means we write no movie-level metadata of our own
        // (not even a creation date).
        exportSession.metadataItemFilter = .forSharing()
        exportSession.metadata = []

        return exportSession
    }

    /// Cheap estimate of the converted output size in bytes, or `nil` if the
    /// video cannot be sent at all (too long to fit even at the lowest quality).
    private func getEstimatedVideoFileSize(for asset: AVAsset) async -> Double? {
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            DDLogError("No video track found")
            return nil
        }
        
        let info: SourceInfo
        do {
            info = try await loadSourceInfo(asset: asset, videoTrack: videoTrack)
        }
        catch {
            return nil
        }
        
        guard info.durationSeconds <= Self.videoMaxDurationInMinutes * 60 else {
            return nil
        }

        switch videoQualitySetting {
        case .low:
            let lowEstimate = Double(kVideoBitrateLow + kAudioBitrateLow) * info.durationSeconds / 8
                + Self.fileOverhead
            return min(lowEstimate, info.originalSizeEstimate, Double(kMaxFileSize))

        case .high:
            let mediumEstimate = Double(kVideoBitrateMedium + kAudioBitrateMedium) * info.durationSeconds / 8
                + Self.fileOverhead
            return min(mediumEstimate, info.originalSizeEstimate, Double(kMaxFileSize))

        case .original:
            let allowPassthrough = AppGroup.getCurrentType() == AppGroupTypeApp
            if allowPassthrough, info.originalSizeEstimate <= Double(kMaxFileSize) {
                return info.originalSizeEstimate
            }
            return min(info.originalSizeEstimate, Self.targetFileSize)
        }
    }
}
