import XCTest
@testable import XML_Fixer

final class AppWorkflowSmokeTests: XCTestCase {

    private var fixtureURL: URL {
        Bundle(for: type(of: self)).url(forResource: "sample_sequence", withExtension: "xml")
            ?? URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures/sample_sequence.xml")
    }

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RepublicWashCutSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    func testPrimaryAppWorkflowWithFixture() async throws {
        let appState = AppState()

        appState.importFiles(urls: [fixtureURL])
        waitUntil("XML import") { !appState.isProcessing }

        XCTAssertEqual(appState.documents.count, 1)
        XCTAssertEqual(appState.mediaReferences.count, 4)

        let sequence = try XCTUnwrap(appState.documents.first?.sequences.first { $0.name == "Test Timeline" })
        appState.selectedSequenceID = sequence.id
        appState.refreshTimelineData()
        XCTAssertNotNil(appState.currentTimelineData)

        try exerciseRelink(appState: appState)
        try exerciseCleanXMLExport(appState: appState)
        try exerciseSourcesXMLExport(appState: appState)
        try await exerciseReferenceMatching(appState: appState, sequence: sequence)
    }

    func testSourcesExportCanReplaceTheLoadedXMLs() throws {
        let appState = AppState()
        appState.importFiles(urls: [fixtureURL])
        waitUntil("XML import") { !appState.isProcessing }
        XCTAssertEqual(appState.documents.count, 1)

        let originalDocumentID = try XCTUnwrap(appState.documents.first?.id)
        appState.selectedMediaIDs = Set(appState.mediaReferences.map(\.id))

        let outputDir = tempRoot.appendingPathComponent("SourcesReplace", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        appState.sourcesExportOptions.outputDirectory = outputDir
        appState.sourcesExportOptions.outputFilename = "Sources_Replace.xml"
        appState.sourcesExportOptions.replaceLoadedXMLs = true

        appState.exportSourcesSequence()
        waitUntil("Sources XML export and reload") { !appState.isProcessing }
        waitUntil("loaded document swap") { appState.documents.first?.id != originalDocumentID }

        XCTAssertEqual(appState.documents.count, 1)
        let loaded = try XCTUnwrap(appState.documents.first)
        XCTAssertEqual(loaded.sourceURL.lastPathComponent, "Sources_Replace.xml")
        XCTAssertFalse(appState.mediaReferences.isEmpty)
        XCTAssertEqual(appState.selectedSequenceID, loaded.sequences.first?.id)
        XCTAssertNotNil(appState.currentTimelineData)
        XCTAssertTrue(appState.selectedMediaIDs.isEmpty)
        XCTAssertFalse(appState.canUndo)
    }

    private func exerciseRelink(appState: AppState) throws {
        let conformDir = tempRoot.appendingPathComponent("Conform", isDirectory: true)
        try FileManager.default.createDirectory(at: conformDir, withIntermediateDirectories: true)

        let conformFile = conformDir.appendingPathComponent("A_0012_001_h3F2A.mov")
        try Data("dummy media".utf8).write(to: conformFile)

        let media = try XCTUnwrap(appState.mediaReferences.first { $0.filename == "A_0012_001_h3F2A.mov" })
        let match = RelinkMatch(
            mediaFilename: media.filename,
            mediaID: media.id,
            candidates: [
                RelinkCandidate(
                    url: conformFile,
                    filenameStem: conformFile.deletingPathExtension().lastPathComponent,
                    fileExtension: conformFile.pathExtension,
                    fileSize: 11
                )
            ],
            selectedCandidateIndex: 0,
            status: .matched,
            userConfirmed: true
        )

        appState.applyRelink([match])

        let relinked = try XCTUnwrap(appState.mediaReferences.first { $0.filename == media.filename })
        XCTAssertEqual(relinked.pathURL, URL(fileURLWithPath: conformFile.path).absoluteString)
    }

    private func exerciseCleanXMLExport(appState: AppState) throws {
        let outputDir = tempRoot.appendingPathComponent("CleanExports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        appState.exportOptions.outputDirectory = outputDir
        appState.exportOptions.filenameSuffix = "_qa"
        appState.exportOptions.shouldRepairReelMetadata = false
        appState.exportAll()
        waitUntil("clean XML export") { !appState.isProcessing }

        let exported = outputDir.appendingPathComponent("sample_sequence_qa.xml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
        let contents = try String(contentsOf: exported)
        XCTAssertTrue(contents.contains("<xmeml"))
    }

    private func exerciseSourcesXMLExport(appState: AppState) throws {
        let outputDir = tempRoot.appendingPathComponent("SourcesExports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        appState.sourcesExportOptions.outputDirectory = outputDir
        appState.sourcesExportOptions.outputFilename = "Sources_QA.xml"
        appState.exportSourcesSequence()
        waitUntil("Sources XML export") { !appState.isProcessing }

        let exported = outputDir.appendingPathComponent("Sources_QA.xml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.path))
        let contents = try String(contentsOf: exported)
        XCTAssertTrue(contents.contains("<!DOCTYPE xmeml>"))
        XCTAssertTrue(contents.contains("<sequence"))
    }

    private func exerciseReferenceMatching(appState: AppState, sequence: SequenceInfo) async throws {
        let referenceDir = tempRoot.appendingPathComponent("References", isDirectory: true)
        try FileManager.default.createDirectory(at: referenceDir, withIntermediateDirectories: true)

        let referenceFile = referenceDir.appendingPathComponent("Test Timeline.mov")
        try Data("dummy reference".utf8).write(to: referenceFile)

        let scanned = await FileScanner.scan(directory: referenceDir, extensionFilter: "mov")
        var matches = ReferenceMatchEngine.match(
            sequences: [(id: sequence.id, name: sequence.name, parentDocumentID: sequence.parentDocumentID)],
            against: scanned,
            strictMode: true,
            minChars: 6
        )
        for index in matches.indices {
            matches[index].accessScopeURL = referenceDir
        }

        XCTAssertEqual(matches.first?.selectedURL?.lastPathComponent, "Test Timeline.mov")
        appState.applyReferenceMatches(matches)

        XCTAssertNotNil(appState.referenceMatches[sequence.id])
        XCTAssertNotNil(appState.playbackCoordinator)
        appState.closeVideoPlayer()
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        condition: @escaping () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTFail("Timed out waiting for \(description)")
    }
}
