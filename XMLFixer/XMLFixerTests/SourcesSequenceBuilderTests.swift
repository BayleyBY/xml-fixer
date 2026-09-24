import XCTest
@testable import XML_Fixer

final class SourcesSequenceBuilderTests: XCTestCase {

    var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "sample_sequence", withExtension: "xml")
            ?? URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures/sample_sequence.xml")
    }

    // MARK: - SourceRange Tests

    func testSourceRangeMerging() {
        XCTAssertTrue(
            SourceRange(inPoint: 100, outPoint: 200)
                .mergeableWith(SourceRange(inPoint: 150, outPoint: 300))
        )
        XCTAssertFalse(
            SourceRange(inPoint: 100, outPoint: 200)
                .mergeableWith(SourceRange(inPoint: 300, outPoint: 400))
        )
    }

    func testSourceRangeMerged() {
        let a = SourceRange(inPoint: 100, outPoint: 200)
        let b = SourceRange(inPoint: 150, outPoint: 300)
        let merged = a.merged(with: b)
        XCTAssertEqual(merged.inPoint, 100)
        XCTAssertEqual(merged.outPoint, 300)
    }

    // MARK: - MediaUsageSummary Tests

    func testMergeRangesWithHandles() {
        var summary = MediaUsageSummary(
            filename: "test.mov",
            pathURL: nil,
            sourceDuration: 1000,
            timebase: 24,
            ntsc: false,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [
                SourceRange(inPoint: 100, outPoint: 200),
                SourceRange(inPoint: 500, outPoint: 600)
            ]
        )
        summary.mergeRanges(handles: 10)

        XCTAssertEqual(summary.mergedRanges.count, 2)
        XCTAssertEqual(summary.mergedRanges[0].inPoint, 90)
        XCTAssertEqual(summary.mergedRanges[0].outPoint, 210)
        XCTAssertEqual(summary.mergedRanges[1].inPoint, 490)
        XCTAssertEqual(summary.mergedRanges[1].outPoint, 610)
    }

    func testMergeRangesWithUnknownSourceDuration() {
        // Slugs ("Black Video") and ID-only <file> stubs parse as duration 0; handles
        // must not clamp the out point down to it and invert the range.
        var summary = MediaUsageSummary(
            filename: "Black Video",
            pathURL: nil,
            sourceDuration: 0,
            timebase: 30,
            ntsc: true,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [SourceRange(inPoint: 86_289, outPoint: 86_349)]
        )
        summary.mergeRanges(handles: 24, mergeThreshold: 96)

        XCTAssertEqual(summary.mergedRanges.count, 1)
        let range = summary.mergedRanges[0]
        XCTAssertEqual(range.inPoint, 86_265)
        XCTAssertEqual(range.outPoint, 86_373)
        XCTAssertGreaterThan(range.length, 0)
    }

    func testBuildXMLLaysOutClipsForwardWithUnknownDurations() throws {
        var known = MediaUsageSummary(
            filename: "A_0012_001_h3F2A.mov",
            pathURL: "file://localhost/tmp/A_0012_001_h3F2A.mov",
            sourceDuration: 1000,
            timebase: 24,
            ntsc: false,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [SourceRange(inPoint: 100, outPoint: 200)]
        )
        var slug = MediaUsageSummary(
            filename: "Black Video",
            pathURL: nil,
            sourceDuration: 0,
            timebase: 30,
            ntsc: true,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [SourceRange(inPoint: 86_289, outPoint: 86_349)]
        )
        known.mergeRanges(handles: 24, mergeThreshold: 96)
        slug.mergeRanges(handles: 24, mergeThreshold: 96)

        let xmlDoc = SourcesSequenceBuilder.buildXML(from: [known, slug], options: SourcesExportOptions())
        let root = try XCTUnwrap(xmlDoc.rootElement())

        let sequenceDuration = try XCTUnwrap((try root.nodes(forXPath: "//sequence/duration")).first?.stringValue.flatMap(Int.init))
        XCTAssertGreaterThan(sequenceDuration, 0)

        let clips = try root.nodes(forXPath: "//sequence/media/video/track/clipitem").compactMap { $0 as? XMLElement }
        XCTAssertEqual(clips.count, 2)
        var previousEnd = 0
        for clip in clips {
            let start = try XCTUnwrap(clip.singleIntValue(forXPath: "start"))
            let end = try XCTUnwrap(clip.singleIntValue(forXPath: "end"))
            let inPoint = try XCTUnwrap(clip.singleIntValue(forXPath: "in"))
            let outPoint = try XCTUnwrap(clip.singleIntValue(forXPath: "out"))
            let duration = try XCTUnwrap(clip.singleIntValue(forXPath: "duration"))
            XCTAssertEqual(start, previousEnd)
            XCTAssertGreaterThan(end, start)
            XCTAssertGreaterThan(outPoint, inPoint)
            XCTAssertGreaterThanOrEqual(duration, outPoint)
            previousEnd = end
        }
    }

    func testMergeRangesHandlesCausesMerge() {
        var summary = MediaUsageSummary(
            filename: "test.mov",
            pathURL: nil,
            sourceDuration: 1000,
            timebase: 24,
            ntsc: false,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [
                SourceRange(inPoint: 100, outPoint: 200),
                SourceRange(inPoint: 215, outPoint: 300)
            ]
        )
        // With 10 handles: [90,210] and [205,310] overlap -> merge to [90,310]
        summary.mergeRanges(handles: 10)

        XCTAssertEqual(summary.mergedRanges.count, 1)
        XCTAssertEqual(summary.mergedRanges[0].inPoint, 90)
        XCTAssertEqual(summary.mergedRanges[0].outPoint, 310)
    }

    func testMergeRangesClampToZero() {
        var summary = MediaUsageSummary(
            filename: "test.mov",
            pathURL: nil,
            sourceDuration: 500,
            timebase: 24,
            ntsc: false,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [SourceRange(inPoint: 5, outPoint: 100)]
        )
        summary.mergeRanges(handles: 10)

        XCTAssertEqual(summary.mergedRanges[0].inPoint, 0) // clamped from -5
        XCTAssertEqual(summary.mergedRanges[0].outPoint, 110)
    }

    func testMergeRangesClampToSourceDuration() {
        var summary = MediaUsageSummary(
            filename: "test.mov",
            pathURL: nil,
            sourceDuration: 500,
            timebase: 24,
            ntsc: false,
            hasVideo: true,
            hasAudio: false,
            audioChannelCount: 0,
            rawRanges: [SourceRange(inPoint: 490, outPoint: 500)]
        )
        summary.mergeRanges(handles: 10)

        XCTAssertEqual(summary.mergedRanges[0].inPoint, 480)
        XCTAssertEqual(summary.mergedRanges[0].outPoint, 500) // clamped from 510
    }

    // MARK: - Integration Tests

    func testCollectUsagesFromFixture() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let summaries = SourcesSequenceBuilder.collectUsages(from: [doc])
        XCTAssertFalse(summaries.isEmpty)

        // Should have entries for media files that have valid in/out points
        let a0012 = summaries.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertNotNil(a0012)
        XCTAssertFalse(a0012!.rawRanges.isEmpty)
    }

    func testBuildXMLProducesValidStructure() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        var summaries = SourcesSequenceBuilder.collectUsages(from: [doc])
        SourcesSequenceBuilder.applyHandlesAndMerge(summaries: &summaries, handles: 10)

        let options = SourcesExportOptions()
        let xmlDoc = SourcesSequenceBuilder.buildXML(from: summaries, options: options)

        let root = xmlDoc.rootElement()!
        XCTAssertEqual(root.name, "xmeml")

        let sequences = try root.nodes(forXPath: "//sequence")
        XCTAssertEqual(sequences.count, 1)

        let clipitems = try root.nodes(forXPath: "//sequence/media/video/track/clipitem")
        XCTAssertGreaterThan(clipitems.count, 0)

        // Verify clips have proper start/end/in/out
        if let firstClip = clipitems.first as? XMLElement {
            XCTAssertNotNil(firstClip.singleIntValue(forXPath: "start"))
            XCTAssertNotNil(firstClip.singleIntValue(forXPath: "end"))
            XCTAssertNotNil(firstClip.singleIntValue(forXPath: "in"))
            XCTAssertNotNil(firstClip.singleIntValue(forXPath: "out"))
        }
    }
}
