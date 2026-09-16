import XCTest
import AVFoundation
@testable import XML_Fixer

/// End-to-end trims on synthetic media generated with AVAssetWriter (no external tools or fixtures).
final class QuickTimeTrimEngineTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        // Kept on disk (one folder per test) so failures can be inspected with ffprobe/QuickTime.
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("qt-trim-tests", isDirectory: true)
            .appendingPathComponent(name.replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression))
        try? FileManager.default.removeItem(at: tmp)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    // MARK: - Tests

    func testProResTrimIsFrameAccurateAndKeepsCodec() async throws {
        let source = tmp.appendingPathComponent("prores.mov")
        try await Self.writeSyntheticMovie(to: source, codec: .proRes422, frames: 48, fps: 24, keyframeInterval: 1, startTimecodeFrame: 24 * 3600)

        let output = tmp.appendingPathComponent("prores_trim.mov")
        let result = try await QuickTimeTrimEngine.passthroughTrim(
            sourceURL: source, outputURL: output, inFrame: 10, outFrame: 30, startFrameNumber: 24 * 3600, progress: { _ in }
        )
        XCTAssertEqual(result.framesWritten, 20)
        XCTAssertEqual(result.snappedInFrame, 10)
        XCTAssertEqual(result.snappedOutFrame, 30)

        let info = try await Self.inspect(output)
        let sourceInfo = try await Self.inspect(source)
        XCTAssertEqual(info.frameCount, 20)
        XCTAssertEqual(info.codec, sourceInfo.codec)
        XCTAssertEqual(info.startTimecode?.description, "01:00:00:10")
    }

    func testH264TrimSnapsOutwardToKeyframes() async throws {
        let source = tmp.appendingPathComponent("h264.mov")
        try await Self.writeSyntheticMovie(to: source, codec: .h264, frames: 48, fps: 24, keyframeInterval: 12, startTimecodeFrame: 0)

        let output = tmp.appendingPathComponent("h264_trim.mov")
        let result = try await QuickTimeTrimEngine.passthroughTrim(
            sourceURL: source, outputURL: output, inFrame: 15, outFrame: 30, startFrameNumber: 0, progress: { _ in }
        )
        // Keyframes at 0, 12, 24, 36 → [15, 30) snaps to [12, 36)
        XCTAssertEqual(result.snappedInFrame, 12)
        XCTAssertEqual(result.snappedOutFrame, 36)
        XCTAssertEqual(result.framesWritten, 24)
        XCTAssertTrue(result.messages.contains { $0.contains("snapped") })

        let info = try await Self.inspect(output)
        XCTAssertEqual(info.frameCount, 24)
        XCTAssertEqual(info.startTimecode?.description, "00:00:00:12")
        XCTAssertEqual(info.codec, kCMVideoCodecType_H264)
    }

    func testProbeReadsRateFramesAndTimecode() async throws {
        let source = tmp.appendingPathComponent("probe.mov")
        try await Self.writeSyntheticMovie(to: source, codec: .proRes422, frames: 30, fps: 25, keyframeInterval: 1, startTimecodeFrame: 25 * 60)
        let probe = try await QuickTimeTrimEngine().probe(url: source)
        XCTAssertEqual(probe.timebase, 25)
        XCTAssertFalse(probe.ntsc)
        XCTAssertEqual(probe.frameCount, 30)
        XCTAssertEqual(probe.startTimecode?.description, "00:01:00:00")
        XCTAssertEqual(probe.isAllIntra, true)
    }

    func testEngineTrimRespectsExistingOutput() async throws {
        let source = tmp.appendingPathComponent("exists.mov")
        try await Self.writeSyntheticMovie(to: source, codec: .proRes422, frames: 12, fps: 24, keyframeInterval: 1, startTimecodeFrame: 0)
        let outDir = tmp.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        try Data([0]).write(to: outDir.appendingPathComponent("exists.mov"))

        var item = TrimPlanItem(xmlFilename: "exists.mov", xmlTimebase: 24, xmlNtsc: false, xmlStartTimecode: nil, xmlSourceDuration: 12,
                                mergedRanges: [SourceRange(inPoint: 0, outPoint: 6)])
        item.probe = TrimSourceProbe(timebase: 24, ntsc: false, frameCount: 12, startTimecode: nil)
        let candidate = TrimCandidate(url: source, kind: .quickTime, fileSize: 1)
        let range = TrimRange(originalIn: 0, originalOut: 6, xmlIn: 0, xmlOut: 6)

        do {
            _ = try await QuickTimeTrimEngine().trim(item: item, candidate: candidate, range: range, rangeIndex: 0, rangeCount: 1,
                                                     outputDirectory: outDir, options: TrimOptions(), progress: { _ in })
            XCTFail("Expected outputExists")
        } catch TrimEngineError.outputExists { }

        var overwrite = TrimOptions()
        overwrite.overwriteExisting = true
        let out = try await QuickTimeTrimEngine().trim(item: item, candidate: candidate, range: range, rangeIndex: 0, rangeCount: 1,
                                                       outputDirectory: outDir, options: overwrite, progress: { _ in })
        XCTAssertEqual(out.framesWritten, 6)
        XCTAssertGreaterThan(out.bytesWritten, 1)
    }

    // MARK: - Synthetic media

    struct Inspection {
        let frameCount: Int
        let codec: CMVideoCodecType
        let startTimecode: Timecode?
    }

    static func inspect(_ url: URL) async throws -> Inspection {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let range = try await video.load(.timeRange)
        let frameDuration = try await video.load(.minFrameDuration)
        let frames = Int((range.duration.seconds / frameDuration.seconds).rounded())
        let formats = try await video.load(.formatDescriptions)
        let desc = try XCTUnwrap(formats.first)
        let codec = CMFormatDescriptionGetMediaSubType(desc)
        let fps = Int((1.0 / frameDuration.seconds).rounded())
        let tc = await AVAssetTimecodeReader.readStartTimecode(from: url, timebase: fps)
        return Inspection(frameCount: frames, codec: codec, startTimecode: tc)
    }

    /// Writes a small movie with a solid-colour video track and a timecode track.
    static func writeSyntheticMovie(to url: URL, codec: AVVideoCodecType, frames: Int, fps: Int, keyframeInterval: Int, startTimecodeFrame: Int) async throws {
        let width = 320, height = 180
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        var settings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        if codec == .h264 {
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoMaxKeyFrameIntervalKey: keyframeInterval,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoAverageBitRateKey: 800_000,
            ]
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(videoInput)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let tcFormat = try XCTUnwrap(try QuickTimeTrimEngine.makeTimecodeFormat(source: nil, frameDuration: frameDuration))
        let tcInput = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: tcFormat)
        writer.add(tcInput)
        videoInput.addTrackAssociation(withTrackOf: tcInput, type: AVAssetTrack.AssociationType.timecode.rawValue)

        XCTAssertTrue(writer.startWriting(), writer.error?.localizedDescription ?? "")
        writer.startSession(atSourceTime: .zero)

        let tcSample = try QuickTimeTrimEngine.makeTimecodeSample(
            format: tcFormat, frameNumber: Int32(startTimecodeFrame), pts: .zero,
            duration: CMTimeMultiply(frameDuration, multiplier: Int32(frames))
        )
        XCTAssertTrue(tcInput.append(tcSample))
        tcInput.markAsFinished()

        for i in 0..<frames {
            while !videoInput.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &pixelBuffer)
            let pb = try XCTUnwrap(pixelBuffer)
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let bytes = CVPixelBufferGetBytesPerRow(pb) * height
                memset(base, Int32(truncatingIfNeeded: (i * 5) & 0xFF), bytes)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            XCTAssertTrue(adaptor.append(pb, withPresentationTime: CMTimeMultiply(frameDuration, multiplier: Int32(i))))
        }
        videoInput.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }
}
