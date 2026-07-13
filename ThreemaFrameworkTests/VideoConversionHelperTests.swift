import Foundation
import XCTest
@testable import ThreemaFramework

final class VideoConversationHelperTests: XCTestCase {

    func testGetEstimatedVideoFileSize() throws {
        let testBundle = Bundle(for: VideoConversationHelperTests.self)
        let testVideoURL = try XCTUnwrap(testBundle.url(forResource: "Video-1", withExtension: "mp4"))

        let userSettingsMock = UserSettingsMock(videoQuality: "original")
        let videoConversionHelper = makeSUT(userSettings: userSettingsMock)

        let size = try XCTUnwrap(videoConversionHelper.getEstimatedVideoFileSize(for: testVideoURL))

        // The estimate is now derived cheaply from the source data rates rather
        // than AVFoundation's whole-asset analysis. For this fixture (quality
        // "original", which passes through) it approximates the real file size:
        // positive, within the send limit, and in the same ballpark as the file.
        let attributes = try FileManager.default.attributesOfItem(atPath: testVideoURL.path)
        let realFileSize = try XCTUnwrap((attributes[.size] as? NSNumber)?.doubleValue)
        XCTAssertGreaterThan(size, 0)
        XCTAssertLessThanOrEqual(size, Double(kMaxFileSize))
        XCTAssertLessThan(size, realFileSize * 2)
    }

    func testVideoQualityOriginal() async throws {
        let testBundle = Bundle(for: VideoConversationHelperTests.self)
        let testVideoURL = try XCTUnwrap(testBundle.url(forResource: "Video-1", withExtension: "mp4"))
        let asset = AVAsset(url: testVideoURL)
        
        let userSettingsMock = UserSettingsMock(videoQuality: "original")
        let videoConversionHelper = makeSUT(userSettings: userSettingsMock)

        let exportSession = try await videoConversionHelper.getAVAssetExportSession(
            from: asset,
            outputURL: FileManager.default.temporaryDirectory
        )
        
        XCTAssertEqual((exportSession as? AVAssetExportSession)?.presetName, "AVAssetExportPresetPassthrough")
    }
    
    func testVideoQualityLow() async throws {
        let testBundle = Bundle(for: VideoConversationHelperTests.self)
        let testVideoURL = try XCTUnwrap(testBundle.url(forResource: "Video-1", withExtension: "mp4"))
        let asset = AVAsset(url: testVideoURL)
        
        let userSettingsMock = UserSettingsMock(videoQuality: "low")
        let videoConversionHelper = makeSUT(userSettings: userSettingsMock)

        let exportSession = try await videoConversionHelper.getAVAssetExportSession(
            from: asset,
            outputURL: FileManager.default.temporaryDirectory
        )
        
        XCTAssertEqual((exportSession as? AVAssetExportSession)?.presetName, "AVAssetExportPresetLowQuality")
    }
    
    func testVideoQualityHigh() async throws {
        let testBundle = Bundle(for: VideoConversationHelperTests.self)
        let testVideoURL = try XCTUnwrap(testBundle.url(forResource: "Video-1", withExtension: "mp4"))
        let asset = AVAsset(url: testVideoURL)
        
        let userSettingsMock = UserSettingsMock(videoQuality: "high")
        let videoConversionHelper = makeSUT(userSettings: userSettingsMock)

        let exportSession = try await videoConversionHelper.getAVAssetExportSession(
            from: asset,
            outputURL: FileManager.default.temporaryDirectory
        )

        // High quality uses the fixed medium-quality preset (classic behavior).
        XCTAssertEqual((exportSession as? AVAssetExportSession)?.presetName, "AVAssetExportPresetMediumQuality")
    }

    // MARK: - Helpers
    
    private func makeSUT(
        userSettings: UserSettingsProtocol,
        outputDirectoryURL: URL = FileManager.default.temporaryDirectory
    ) -> VideoConversionHelper {
        VideoConversionHelper(
            userSettings: userSettings,
            outputDirectoryURL: outputDirectoryURL
        )
    }
}
