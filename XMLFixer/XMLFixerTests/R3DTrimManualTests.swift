import XCTest
@testable import XML_Fixer

/// Runs the whole trim pipeline against a real folder of RED clips when `XMLFIXER_R3D_DIR` is set
/// (pass `TEST_RUNNER_XMLFIXER_R3D_DIR=/path` to xcodebuild). Requires REDline. Reads the originals
/// only; writes to `$TMPDIR/r3d-trim-manual-out`.
final class R3DTrimManualTests: XCTestCase {

    func testTrimsFirstREDClipThroughThePipeline() async throws {
        guard let dirPath = ProcessInfo.processInfo.environment["XMLFIXER_R3D_DIR"], !dirPath.isEmpty else {
            throw XCTSkip("XMLFIXER_R3D_DIR not set")
        }
        var options = TrimOptions()
        options.sourceRoot = URL(fileURLWithPath: dirPath, isDirectory: true)
        options.destinationRoot = FileManager.default.temporaryDirectory.appendingPathComponent("r3d-trim-manual-out", isDirectory: true)
        options.overwriteExisting = true
        try? FileManager.default.removeItem(at: options.destinationRoot!)
        let registry = TrimEngineRegistry(options: options, sandboxed: false)
        guard let redline = registry.redline else { throw XCTSkip("REDline not found") }

        let scanned = await FileScanner.scan(directory: options.sourceRoot!, extensionFilter: nil)
        let r3dStems = scanned.filter { $0.value.contains { $0.fileExtension == "r3d" && $0.isR3DSplit } }.keys.sorted()
        let base = try XCTUnwrap(r3dStems.first, "no split RED clips found")
        let firstSegment = try XCTUnwrap(scanned[base]?.first { $0.isR3DSplit }?.url)

        // Probe the real clip so the synthetic "edit" references its absolute TC.
        let probe = await redline.probe(url: firstSegment, fallbackTimebase: 24)
        let startTC = try XCTUnwrap(probe.startTimecode)
        XCTAssertGreaterThan(probe.frameCount, 200)

        // A proxy named after the clip, used twice: [100,148) and [400,424) → two _trimNN clips
        var summary = MediaUsageSummary(
            filename: "\(base.uppercased()).mov", pathURL: nil, sourceDuration: probe.frameCount,
            timebase: probe.timebase, ntsc: probe.ntsc, hasVideo: true, hasAudio: false, audioChannelCount: 0,
            timecodeString: startTC.description,
            rawRanges: [SourceRange(inPoint: 100, outPoint: 148), SourceRange(inPoint: 400, outPoint: 424)]
        )
        summary.mergeRanges(handles: 0)

        var items = OriginalMediaMatcher.match(summaries: [summary], scanned: scanned)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].selectedCandidate?.kind, .r3d)
        await TrimPlanner.resolve(item: &items[0], registry: registry)
        XCTAssertEqual(items[0].status, .ready, items[0].warnings.joined(separator: "; "))
        XCTAssertEqual(items[0].basis, .timecode)
        XCTAssertEqual(items[0].trimRanges.map { [$0.originalIn, $0.originalOut] }, [[100, 148], [400, 424]])

        let results = await TrimRunner.run(items: items, options: options, registry: registry, progress: { _ in })
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.status, .trimmed, result.messages.joined(separator: "; "))
        XCTAssertEqual(result.outputs.filter { $0.pathExtension.lowercased() == "r3d" }.count, 2)
        print("MANUAL R3D outputs:", result.outputs.map(\.path))
        print("MANUAL R3D cmd:", result.commandLine ?? "-")

        // Verify each trimmed clip with REDline itself
        let expected: [(frames: Int, start: Int)] = [(48, 100), (24, 400)]
        for (i, url) in result.outputs.filter({ $0.pathExtension.lowercased() == "r3d" }).enumerated() {
            let outProbe = await redline.probe(url: url, fallbackTimebase: probe.timebase)
            XCTAssertEqual(outProbe.frameCount, expected[i].frames, url.lastPathComponent)
            XCTAssertEqual(outProbe.startTimecode?.totalFrames, startTC.totalFrames + expected[i].start, url.lastPathComponent)
            XCTAssertTrue(url.deletingLastPathComponent().pathExtension.lowercased() == "rdc", "not inside an .RDC folder: \(url.path)")
        }
    }
}
