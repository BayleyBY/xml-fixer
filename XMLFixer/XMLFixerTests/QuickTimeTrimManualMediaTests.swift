import XCTest
import AVFoundation
@testable import XML_Fixer

/// Trims every movie found in `$TMPDIR/qt-trim-manual/` through the real engine and checks the
/// output keeps codec, audio tracks and timecode. Drop real camera files there to exercise them;
/// the test is skipped when the folder is empty.
final class QuickTimeTrimManualMediaTests: XCTestCase {

    private var manualDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("qt-trim-manual", isDirectory: true)
    }

    func testTrimsEveryManualMovie() async throws {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: manualDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["mov", "mp4", "m4v"].contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.contains("_trim") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else {
            throw XCTSkip("No media in \(manualDir.path)")
        }

        for source in files {
            let asset = AVURLAsset(url: source)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let sourceVideo = try XCTUnwrap(videoTracks.first, source.lastPathComponent)
            let sourceAudioCount = try await asset.loadTracks(withMediaType: .audio).count
            let sourceFormats = try await sourceVideo.load(.formatDescriptions)
            let sourceCodec = CMFormatDescriptionGetMediaSubType(try XCTUnwrap(sourceFormats.first))

            let probe = try await QuickTimeTrimEngine().probe(url: source)
            XCTAssertGreaterThan(probe.frameCount, 60, source.lastPathComponent)
            let startFrames = probe.startTimecode?.totalFrames

            let output = source.deletingLastPathComponent()
                .appendingPathComponent(source.deletingPathExtension().lastPathComponent + "_trim." + source.pathExtension)
            try? fm.removeItem(at: output)

            let result = try await QuickTimeTrimEngine.passthroughTrim(
                sourceURL: source, outputURL: output, inFrame: 25, outFrame: 60,
                startFrameNumber: startFrames, progress: { _ in }
            )
            XCTAssertGreaterThanOrEqual(result.framesWritten, 35, source.lastPathComponent)
            XCTAssertLessThanOrEqual(result.snappedInFrame, 25, source.lastPathComponent)
            XCTAssertGreaterThanOrEqual(result.snappedOutFrame, 60, source.lastPathComponent)

            let outAsset = AVURLAsset(url: output)
            let outVideoTracks = try await outAsset.loadTracks(withMediaType: .video)
            let outVideo = try XCTUnwrap(outVideoTracks.first, source.lastPathComponent)
            let outFormats = try await outVideo.load(.formatDescriptions)
            XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(outFormats.first)), sourceCodec, "codec changed for \(source.lastPathComponent)")
            let outAudioCount = try await outAsset.loadTracks(withMediaType: .audio).count
            if outVideo.canProvideSampleCursors, let cursor = outVideo.makeSampleCursorAtFirstSampleInDecodeOrder() {
                XCTAssertTrue(cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue, "output does not start on a keyframe: \(source.lastPathComponent)")
            }
            let outRange = try await outVideo.load(.timeRange)
            let outFrameDuration = try await outVideo.load(.minFrameDuration)
            let outFrames = Int((outRange.duration.seconds / outFrameDuration.seconds).rounded())
            XCTAssertEqual(outFrames, result.snappedOutFrame - result.snappedInFrame, "duration mismatch for \(source.lastPathComponent)")
            XCTAssertEqual(outAudioCount, sourceAudioCount, "audio tracks lost for \(source.lastPathComponent)")

            if let startFrames {
                let outTC = await AVAssetTimecodeReader.readStartTimecode(from: output, timebase: probe.timebase)
                if output.pathExtension.lowercased() == "mov" {
                    XCTAssertEqual(outTC?.totalFrames, startFrames + result.snappedInFrame, "timecode wrong for \(source.lastPathComponent)")
                } else {
                    XCTAssertTrue(result.messages.contains { $0.contains("timecode track") }, "MP4 output should report the missing timecode track")
                }
            }
            print("MANUAL \(source.lastPathComponent): frames=\(result.framesWritten) in=\(result.snappedInFrame) out=\(result.snappedOutFrame) audio=\(outAudioCount) msgs=\(result.messages)")
        }
    }
}
