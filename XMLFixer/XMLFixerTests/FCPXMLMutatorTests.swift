import XCTest
@testable import XML_Fixer

final class FCPXMLMutatorTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "sample_sequence", withExtension: "xml")
            ?? URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures/sample_sequence.xml")
    }

    // MARK: - Remove Audio Tracks

    func testRemoveAllAudioTracks() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let removed = FCPXMLMutator.removeAllAudioTracks(in: doc)
        XCTAssertGreaterThan(removed, 0)
        XCTAssertTrue(doc.isDirty)

        // Verify audio tracks are gone
        let root = doc.xmlDocument.rootElement()!
        let audioTracks = try root.nodes(forXPath: "//sequence/media/audio/track")
        XCTAssertEqual(audioTracks.count, 0)
    }

    // MARK: - Remove Clipitems

    func testRemoveClipitemsByFilename() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let fileMap = FCPXMLMutator.buildFileMap(from: doc.xmlDocument)
        let removed = FCPXMLMutator.removeClipitems(
            matching: ["logo.png"],
            in: doc,
            fileMap: fileMap
        )
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(doc.isDirty)

        // Verify logo.png clipitem is gone
        let mediaRefs = FCPXMLParser.extractMediaReferences(from: [doc])
        let filenames = Set(mediaRefs.map(\.filename))
        XCTAssertFalse(filenames.contains("logo.png"))
        XCTAssertTrue(filenames.contains("A_0012_001_h3F2A.mov"))
    }

    // MARK: - Rename Sequences

    func testRenameSequences() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let renamed = FCPXMLMutator.renameSequences(in: doc, to: "New Name")
        // Fixture has main sequence + nested sequence, so 2 renames
        XCTAssertEqual(renamed, 2)

        let root = doc.xmlDocument.rootElement()!
        let seqNames = try root.nodes(forXPath: "//sequence/name")
        XCTAssertTrue(seqNames.allSatisfy { $0.stringValue == "New Name" })
    }

    // MARK: - File Map

    func testBuildFileMap() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let fileMap = FCPXMLMutator.buildFileMap(from: doc.xmlDocument)

        XCTAssertEqual(fileMap["file1"], "A_0012_001_h3F2A.mov")
        XCTAssertEqual(fileMap["file2"], "logo.png")
        XCTAssertEqual(fileMap["file3"], "BRT_0021.mov")
    }

    // MARK: - Reel Metadata Repair

    func testReelMetadataRepair() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let repaired = ReelMetadataRepairer.repairReelMetadata(in: doc.xmlDocument)
        XCTAssertEqual(repaired, 1)

        // Verify reel was inserted
        let root = doc.xmlDocument.rootElement()!
        let reelName = try root.nodes(forXPath: "//file[@id='file1']/timecode/reel/name").first?.stringValue
        XCTAssertEqual(reelName, "A_0012_3F2A")
    }

    // MARK: - Count Clipitems To Remove

    func testCountClipitemsToRemove() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let counts = FCPXMLMutator.countClipitemsToRemove(
            matching: ["logo.png", "audio_mix.wav"],
            in: [doc]
        )
        XCTAssertEqual(counts.clipCount, 2) // 1 video + 1 audio
        XCTAssertEqual(counts.documentCount, 1)
    }

    // MARK: - Update Filename Tests

    func testUpdateFilename() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let updated = FCPXMLMutator.updateFilename(from: "logo.png", to: "new_logo.png", in: [doc])
        XCTAssertGreaterThan(updated, 0)
        XCTAssertTrue(doc.isDirty)

        // Verify the change persisted in the DOM
        let fileMap = FCPXMLMutator.buildFileMap(from: doc.xmlDocument)
        XCTAssertTrue(fileMap.values.contains("new_logo.png"))
        XCTAssertFalse(fileMap.values.contains("logo.png"))
    }

    func testUpdateReelName() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let updated = FCPXMLMutator.updateReelName(for: "A_0012_001_h3F2A.mov", to: "TEST_REEL", in: [doc])
        XCTAssertGreaterThan(updated, 0)
        XCTAssertTrue(doc.isDirty)

        // Verify the reel name was set
        guard let root = doc.xmlDocument.rootElement() else { XCTFail(); return }
        let reelNames = try root.nodes(forXPath: "//file[@id='file1']/timecode/reel/name")
        XCTAssertEqual(reelNames.first?.stringValue, "TEST_REEL")
    }

    func testUpdatePathURL() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)
        let updated = FCPXMLMutator.updatePathURL(for: "A_0012_001_h3F2A.mov", to: "file://localhost/new/path.mov", in: [doc])
        XCTAssertGreaterThan(updated, 0)

        guard let root = doc.xmlDocument.rootElement() else { XCTFail(); return }
        let paths = try root.nodes(forXPath: "//file[@id='file1']/pathurl")
        XCTAssertEqual(paths.first?.stringValue, "file://localhost/new/path.mov")
    }

    // MARK: - Denest Tests

    func testDenestSequences() throws {
        let doc = try FCPXMLParser.parse(url: fixtureURL)

        // Verify nested sequence exists before denesting
        guard let root = doc.xmlDocument.rootElement() else { XCTFail(); return }
        let nestedBefore = try root.nodes(forXPath: "//sequence/media/video/track/clipitem/sequence")
        XCTAssertFalse(nestedBefore.isEmpty, "Should have nested sequences before denesting")

        let denested = FCPXMLMutator.denestSequences(in: doc)
        XCTAssertGreaterThan(denested, 0)
        XCTAssertTrue(doc.isDirty)

        // Verify no nested sequences remain
        let nestedAfter = try root.nodes(forXPath: "//sequence[@id='seq1']/media/video/track/clipitem/sequence")
        XCTAssertTrue(nestedAfter.isEmpty, "Should have no nested sequences after denesting")
    }
}
