import XCTest
import AVFoundation
@testable import XML_Fixer

/// Whole pipeline on the sample fixture: XML → usage ranges → match originals on disk → plan → trim.
final class TrimWorkflowTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "sample_sequence", withExtension: "xml")
            ?? URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures/sample_sequence.xml")
    }

    func testFixtureTrimsAgainstSyntheticOriginals() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("trim-workflow", isDirectory: true)
        try? fm.removeItem(at: tmp)
        let raw = tmp.appendingPathComponent("RAW/A001", isDirectory: true)
        let dest = tmp.appendingPathComponent("TRIMMED", isDirectory: true)
        try fm.createDirectory(at: raw, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        // Originals named like the XML's media. A_0012 shares the XML's 01:00:00:00 start TC;
        // BRT starts at 00:00:00:00 like the XML says.
        try await QuickTimeTrimEngineTests.writeSyntheticMovie(
            to: raw.appendingPathComponent("A_0012_001_h3F2A.mov"), codec: .proRes422, frames: 300, fps: 24, keyframeInterval: 1, startTimecodeFrame: 24 * 3600)
        try await QuickTimeTrimEngineTests.writeSyntheticMovie(
            to: raw.appendingPathComponent("BRT_0021.mov"), codec: .proRes422, frames: 200, fps: 24, keyframeInterval: 1, startTimecodeFrame: 0)
        try Data(repeating: 7, count: 64).write(to: raw.appendingPathComponent("logo.png"))
        try Data(repeating: 9, count: 128).write(to: raw.appendingPathComponent("audio_mix.wav"))

        // XML → merged usage ranges (handles 10, no gap merging)
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        var summaries = SourcesSequenceBuilder.collectUsages(from: [doc])
        SourcesSequenceBuilder.applyHandlesAndMerge(summaries: &summaries, handles: 10, mergeThreshold: 0)

        var options = TrimOptions()
        options.sourceRoot = tmp.appendingPathComponent("RAW")
        options.destinationRoot = dest
        options.handles = 10
        let registry = TrimEngineRegistry(options: options, sandboxed: true)

        let scanned = await FileScanner.scan(directory: options.sourceRoot!, extensionFilter: nil)
        var items = OriginalMediaMatcher.match(summaries: summaries, scanned: scanned)
        for i in items.indices {
            await TrimPlanner.resolve(item: &items[i], registry: registry)
        }

        func item(_ name: String) throws -> TrimPlanItem {
            try XCTUnwrap(items.first { $0.xmlFilename == name }, name)
        }

        let a = try item("A_0012_001_h3F2A.mov")
        XCTAssertEqual(a.status, .ready)
        XCTAssertEqual(a.basis, .timecode)
        XCTAssertEqual(a.trimRanges.map { [$0.originalIn, $0.originalOut] }, [[40, 160], [190, 260]])

        let brt = try item("BRT_0021.mov")
        XCTAssertEqual(brt.status, .ready)
        XCTAssertEqual(brt.trimRanges.map { [$0.originalIn, $0.originalOut] }, [[0, 170]])

        XCTAssertEqual(try item("logo.png").status, .copyWhole("Still image"))
        // audio_mix.wav only appears on audio tracks; usage collection scans video clips, so it is not a source.
        XCTAssertNil(items.first { $0.xmlFilename == "audio_mix.wav" })

        // Run
        let results = await TrimRunner.run(items: items, options: options, registry: registry, progress: { _ in })
        XCTAssertEqual(results.count, 3)
        XCTAssertFalse(results.contains { $0.status.isFailure }, results.map(\.status.label).joined(separator: ", "))

        let outDir = dest.appendingPathComponent("A001")
        let written = try fm.contentsOfDirectory(atPath: outDir.path).sorted()
        XCTAssertEqual(written, ["A_0012_001_h3F2A_trim01.mov", "A_0012_001_h3F2A_trim02.mov", "BRT_0021.mov", "logo.png"])

        let trim1 = try await QuickTimeTrimEngineTests.inspect(outDir.appendingPathComponent("A_0012_001_h3F2A_trim01.mov"))
        XCTAssertEqual(trim1.frameCount, 120)
        XCTAssertEqual(trim1.startTimecode?.description, "01:00:01:16")
        let trim2 = try await QuickTimeTrimEngineTests.inspect(outDir.appendingPathComponent("A_0012_001_h3F2A_trim02.mov"))
        XCTAssertEqual(trim2.frameCount, 70)
        XCTAssertEqual(trim2.startTimecode?.description, "01:00:07:22")
        let brtOut = try await QuickTimeTrimEngineTests.inspect(outDir.appendingPathComponent("BRT_0021.mov"))
        XCTAssertEqual(brtOut.frameCount, 170)
        XCTAssertEqual(brtOut.startTimecode?.description, "00:00:00:00")

        let aResult = try XCTUnwrap(results.first { $0.xmlFilename == "A_0012_001_h3F2A.mov" })
        XCTAssertEqual(aResult.status, .trimmed)
        XCTAssertEqual(aResult.framesWritten, 190)
        XCTAssertEqual(aResult.extraFrames, 0)

        // Second run without overwrite skips everything that exists
        let again = await TrimRunner.run(items: items, options: options, registry: registry, progress: { _ in })
        XCTAssertTrue(again.allSatisfy { $0.status == .skippedExisting }, again.map(\.status.label).joined(separator: ", "))
    }
}
