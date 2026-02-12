import XCTest
@testable import XML_Fixer

final class FCPXMLParserTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "sample_sequence", withExtension: "xml")
            ?? URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures/sample_sequence.xml")
    }

    // MARK: - Sequence Parsing

    func testParseExtractsSequenceInfo() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        // Fixture has main sequence + nested sequence
        XCTAssertGreaterThanOrEqual(doc.sequences.count, 1)
        let mainSeq = doc.sequences.first { $0.name == "Test Timeline" }
        XCTAssertNotNil(mainSeq)
        XCTAssertEqual(mainSeq?.timebase, 24)
        XCTAssertEqual(mainSeq?.duration, 1800)
        XCTAssertEqual(mainSeq?.videoTrackCount, 2)
        XCTAssertEqual(mainSeq?.audioTrackCount, 1)
    }

    // MARK: - Media Reference Extraction

    func testExtractMediaReferencesDeduplicates() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let mediaRefs = FCPXMLParser.extractMediaReferences(from: [doc])

        // Should have 4 unique media files
        XCTAssertEqual(mediaRefs.count, 4)

        let filenames = Set(mediaRefs.map(\.filename))
        XCTAssertTrue(filenames.contains("A_0012_001_h3F2A.mov"))
        XCTAssertTrue(filenames.contains("logo.png"))
        XCTAssertTrue(filenames.contains("BRT_0021.mov"))
        XCTAssertTrue(filenames.contains("audio_mix.wav"))
    }

    func testExtractMediaReferencesAcrossMultipleDocuments() throws {
        let doc1 = try FCPXMLParser.parse(url: fixtureURL)
        let doc2 = try FCPXMLParser.parse(url: fixtureURL)
        let mediaRefs = FCPXMLParser.extractMediaReferences(from: [doc1, doc2])

        // Same 4 filenames, but each should reference 2 documents
        XCTAssertEqual(mediaRefs.count, 4)

        let logoRef = mediaRefs.first { $0.filename == "logo.png" }
        XCTAssertNotNil(logoRef)
        XCTAssertEqual(logoRef?.referencingDocuments.count, 2)
        XCTAssertEqual(logoRef?.clipCount, 2)
    }

    // MARK: - Rich Metadata & Sequence Back-References

    func testExtractMediaReferencesIncludesTimecodeMetadata() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let mediaRefs = FCPXMLParser.extractMediaReferences(from: [doc])

        // A_0012_001_h3F2A.mov has full timecode metadata in the fixture
        let movRef = mediaRefs.first { $0.filename == "A_0012_001_h3F2A.mov" }
        XCTAssertNotNil(movRef)
        XCTAssertEqual(movRef?.timecodeString, "01:00:00:00")
        XCTAssertEqual(movRef?.timecodeFrame, 86400)
        XCTAssertEqual(movRef?.displayFormat, "NDF")
        XCTAssertNil(movRef?.reelName, "No reel element exists in the fixture for this file")

        // logo.png has no timecode block at all
        let pngRef = mediaRefs.first { $0.filename == "logo.png" }
        XCTAssertNotNil(pngRef)
        XCTAssertNil(pngRef?.timecodeString)
        XCTAssertNil(pngRef?.timecodeFrame)
        XCTAssertNil(pngRef?.displayFormat)
        XCTAssertNil(pngRef?.reelName)

        // All media in the fixture live inside "Test Timeline"
        let sequenceNames = movRef?.referencingSequences.map(\.sequenceName) ?? []
        XCTAssertTrue(sequenceNames.contains("Test Timeline"),
                      "Expected referencingSequences to include 'Test Timeline', got: \(sequenceNames)")

        let pngSequenceNames = pngRef?.referencingSequences.map(\.sequenceName) ?? []
        XCTAssertTrue(pngSequenceNames.contains("Test Timeline"),
                      "Expected referencingSequences to include 'Test Timeline', got: \(pngSequenceNames)")
    }

    // MARK: - FPS + Rich Metadata Tests

    func testComputeFPS() {
        XCTAssertEqual(FCPXMLParser.computeFPS(timebase: 24, ntsc: false), 24.0)
        XCTAssertEqual(FCPXMLParser.computeFPS(timebase: 25, ntsc: false), 25.0)
        XCTAssertEqual(FCPXMLParser.computeFPS(timebase: 30, ntsc: false), 30.0)

        // NTSC rates
        let fps24ntsc = FCPXMLParser.computeFPS(timebase: 24, ntsc: true)
        XCTAssertEqual(fps24ntsc, 24.0 * 1000.0 / 1001.0, accuracy: 0.001)

        let fps30ntsc = FCPXMLParser.computeFPS(timebase: 30, ntsc: true)
        XCTAssertEqual(fps30ntsc, 30.0 * 1000.0 / 1001.0, accuracy: 0.001)
    }

    func testExtractMediaReferencesIncludesFPS() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let refs = FCPXMLParser.extractMediaReferences(from: [doc])

        let a0012 = refs.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertNotNil(a0012)
        XCTAssertEqual(a0012?.fps, 24.0)
    }

    func testExtractMediaReferencesIncludesResolution() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let refs = FCPXMLParser.extractMediaReferences(from: [doc])

        let a0012 = refs.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertEqual(a0012?.resolution, "1920x1080")

        let logo = refs.first(where: { $0.filename == "logo.png" })
        XCTAssertEqual(logo?.resolution, "800x600")
    }

    func testExtractMediaReferencesIncludesCodec() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let refs = FCPXMLParser.extractMediaReferences(from: [doc])

        let a0012 = refs.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertEqual(a0012?.codec, "Apple ProRes 422")
    }

    func testExtractMediaReferencesIncludesAudioChannels() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let refs = FCPXMLParser.extractMediaReferences(from: [doc])

        let a0012 = refs.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertEqual(a0012?.audioChannels, 2)

        let logo = refs.first(where: { $0.filename == "logo.png" })
        XCTAssertNil(logo?.audioChannels)
    }

    func testExtractMediaReferencesDetectsTimewarp() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let refs = FCPXMLParser.extractMediaReferences(from: [doc])

        // logo.png has a speed filter
        let logo = refs.first(where: { $0.filename == "logo.png" })
        XCTAssertEqual(logo?.isTimewarped, true)

        // A_0012 does not
        let a0012 = refs.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertEqual(a0012?.isTimewarped, false)
    }

    func testExtractMediaReferencesIncludesSourceDuration() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let refs = FCPXMLParser.extractMediaReferences(from: [doc])

        let a0012 = refs.first(where: { $0.filename == "A_0012_001_h3F2A.mov" })
        XCTAssertEqual(a0012?.sourceDurationFrames, 500)
    }

    // MARK: - Sequence Info Enhanced Tests

    func testParseExtractsSequenceFPS() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        XCTAssertEqual(doc.sequences.first?.fps, 24.0)
    }

    func testParseDetectsNestedSequences() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let seq = doc.sequences.first
        XCTAssertEqual(seq?.hasNestedSequences, true)
        XCTAssertEqual(seq?.nestedSequenceCount, 1)
    }

    func testParseExtractsAudioChannelInfo() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let seq = doc.sequences.first
        XCTAssertEqual(seq?.audioChannelInfo, "Stereo")
    }
}
