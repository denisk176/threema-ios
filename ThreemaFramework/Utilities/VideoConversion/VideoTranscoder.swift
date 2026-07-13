import AVFoundation
import CocoaLumberjackSwift
import CoreMedia
import CoreVideo
import FileUtility
import Foundation

// MARK: - VideoTranscoder

/// Bitrate-targeted video transcoder built on `AVAssetReader` / `AVAssetWriter`.
///
/// Unlike `AVAssetExportSession` presets — which only let `fileLengthLimit` act
/// as a ceiling — this targets an explicit average video bitrate so the output
/// lands as close as possible to the file-size limit. Encoding is performed by
/// the VideoToolbox hardware encoder (the default backend for H.264 in
/// `AVAssetWriter`).
final class VideoTranscoder: VideoExportSession {

    // MARK: - Public interface

    let outputURL: URL?

    var progress: Float {
        get { locked { internalProgress } }
        set { locked { internalProgress = newValue } }
    }

    // MARK: - Private properties

    private let asset: AVAsset
    private let videoBitrate: Int
    private let audioBitrate: Int
    private let audioChannels: Int
    private let renderSize: CGSize
    private let durationSeconds: Double

    private let lock = NSLock()
    private var internalProgress: Float = 0
    private var cancelled = false

    private let videoQueue = DispatchQueue(label: "ch.threema.VideoTranscoder.video")
    private let audioQueue = DispatchQueue(label: "ch.threema.VideoTranscoder.audio")

    private var isCancelled: Bool {
        locked { cancelled }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - asset: source asset to transcode.
    ///   - outputURL: destination file URL (`.mp4`).
    ///   - videoBitrate: target average video bitrate in bits per second.
    ///   - audioBitrate: target audio bitrate in bits per second.
    ///   - audioChannels: number of audio channels for the output.
    ///   - renderSize: encoded (un-transformed) output dimensions.
    ///   - durationSeconds: source duration in seconds (used for progress and estimation).
    init(
        asset: AVAsset,
        outputURL: URL,
        videoBitrate: Int,
        audioBitrate: Int,
        audioChannels: Int,
        renderSize: CGSize,
        durationSeconds: Double
    ) {
        self.asset = asset
        self.outputURL = outputURL
        self.videoBitrate = videoBitrate
        self.audioBitrate = audioBitrate
        self.audioChannels = audioChannels
        self.renderSize = renderSize
        self.durationSeconds = durationSeconds
    }

    // MARK: - VideoExportSession

    func cancelExport() {
        locked { cancelled = true }
    }

    func runExport() async throws -> URL {
        guard let outputURL else {
            throw VideoExportError.failed
        }

        do {
            return try await run(outputURL: outputURL)
        }
        catch {
            try? FileUtility.shared.delete(at: outputURL)
            throw error
        }
    }

    // MARK: - Private

    private func run(outputURL: URL) async throws -> URL {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoExportError.failed
        }
        
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        // `AVAssetWriter` never copies the source's metadata — it only writes what
        // we put here — so an empty array means the output carries no movie-level
        // metadata (location, device, original timestamps, …) at all.
        writer.metadata = []

        // Reader outputs (decompressed).
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw VideoExportError.failed
        }
        reader.add(videoOutput)

        // Decide whether the audio can be copied without re-encoding: if the
        // source is already AAC and within our audio budget, passthrough saves a
        // full audio decode + encode. Otherwise we convert it to AAC (which also
        // keeps non-AAC sources compatible with Android).
        var audioPassthrough = false
        var audioFormatHint: CMFormatDescription?
        if let audioTrack {
            let formats = await (try? audioTrack.load(.formatDescriptions)) ?? []
            audioFormatHint = formats.first
            let isAAC = formats.contains { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }
            let sourceAudioRate = await (try? audioTrack.load(.estimatedDataRate)) ?? .greatestFiniteMagnitude
            audioPassthrough = isAAC && sourceAudioRate <= Float(audioBitrate)
        }

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack {
            // `nil` output settings hand back the original (compressed) samples
            // for passthrough; otherwise decompress to PCM for re-encoding.
            let readerSettings: [String: Any]? = audioPassthrough
                ? nil
                : [AVFormatIDKey: kAudioFormatLinearPCM]
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }

        // Writer inputs (re-encoded).
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(renderSize.width),
            AVVideoHeightKey: Int(renderSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: videoBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = false
        // Preserve orientation: the encoded buffers stay in the track's natural
        // orientation and the transform tells players how to rotate.
        videoInput.transform = preferredTransform
        
        guard writer.canAdd(videoInput) else {
            throw VideoExportError.failed
        }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input: AVAssetWriterInput =
                if audioPassthrough {
                    // `nil` output settings append the source samples unchanged.
                    AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormatHint)
                }
                else {
                    AVAssetWriterInput(mediaType: .audio, outputSettings: [
                        AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVNumberOfChannelsKey: audioChannels,
                        AVSampleRateKey: 44100,
                        AVEncoderBitRateKey: audioBitrate,
                    ])
                }
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard reader.startReading() else {
            throw reader.error ?? VideoExportError.failed
        }

        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? VideoExportError.failed
        }

        writer.startSession(atSourceTime: .zero)

        // Pump both tracks concurrently; the task group returns once every input
        // has drained its source (or the export was cancelled).
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.pump(videoInput, from: videoOutput, on: self.videoQueue, isVideo: true)
            }
            if let audioInput, let audioOutput {
                group.addTask {
                    await self.pump(audioInput, from: audioOutput, on: self.audioQueue, isVideo: false)
                }
            }
        }

        if isCancelled {
            writer.cancelWriting()
            reader.cancelReading()
            throw VideoExportError.failed
        }

        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? VideoExportError.failed
        }

        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }

        guard writer.status == .completed else {
            throw writer.error ?? VideoExportError.failed
        }

        progress = 1.0
        return outputURL
    }

    private func pump(
        _ input: AVAssetWriterInput,
        from output: AVAssetReaderTrackOutput,
        on queue: DispatchQueue,
        isVideo: Bool
    ) async {
        await withCheckedContinuation { continuation in
            input.requestMediaDataWhenReady(on: queue) { [weak self] in
                guard let self else {
                    input.markAsFinished()
                    continuation.resume()
                    return
                }

                while input.isReadyForMoreMediaData {
                    if isCancelled {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                    if let sampleBuffer = output.copyNextSampleBuffer() {
                        if isVideo {
                            updateProgress(for: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                        }
                        input.append(sampleBuffer)
                    }
                    else {
                        input.markAsFinished()
                        continuation.resume()
                        return
                    }
                }
            }
        }
    }

    private func updateProgress(for presentationTime: CMTime) {
        guard durationSeconds > 0 else {
            return
        }
        let seconds = CMTimeGetSeconds(presentationTime)
        let value = Float(max(0, min(1, seconds / durationSeconds)))
        progress = value
    }
}
