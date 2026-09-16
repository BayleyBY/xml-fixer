import XCTest
@testable import XML_Fixer

final class ImageSequenceTrimEngineTests: XCTestCase {

    func testCopiesOnlyFramesInRange() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("seq-trim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("src")
        let out = tmp.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)

        var frames: [ImageSequenceInfo.Frame] = []
        for n in 1001...1020 {
            let url = src.appendingPathComponent("plate.\(n).exr")
            try Data(repeating: UInt8(n & 0xFF), count: 8).write(to: url)
            frames.append(.init(number: n, url: url, fileSize: 8))
        }
        let seq = ImageSequenceInfo(directory: src, prefix: "plate.", suffix: ".exr", frames: frames)
        let candidate = TrimCandidate(url: frames[0].url, kind: .imageSequence, fileSize: 160, sequence: seq)
        let item = TrimPlanItem(xmlFilename: "plate.1001.exr", xmlTimebase: 24, xmlNtsc: false, xmlStartTimecode: nil,
                                xmlSourceDuration: 20, mergedRanges: [SourceRange(inPoint: 5, outPoint: 9)])
        let range = TrimRange(originalIn: 5, originalOut: 9, xmlIn: 5, xmlOut: 9)

        let result = try await ImageSequenceTrimEngine().trim(
            item: item, candidate: candidate, range: range, rangeIndex: 0, rangeCount: 1,
            outputDirectory: out, options: TrimOptions(), progress: { _ in }
        )
        XCTAssertEqual(result.framesWritten, 4)
        XCTAssertEqual(result.bytesWritten, 32)
        let written = try FileManager.default.contentsOfDirectory(atPath: out.path).sorted()
        XCTAssertEqual(written, ["plate.1006.exr", "plate.1007.exr", "plate.1008.exr", "plate.1009.exr"])
    }

    func testCopyWholeSequenceViaRunner() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("seq-whole-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let src = tmp.appendingPathComponent("src")
        let out = tmp.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        var frames: [ImageSequenceInfo.Frame] = []
        for n in 1...3 {
            let url = src.appendingPathComponent("p.\(String(format: "%04d", n)).dpx")
            try Data([1]).write(to: url)
            frames.append(.init(number: n, url: url, fileSize: 1))
        }
        let seq = ImageSequenceInfo(directory: src, prefix: "p.", suffix: ".dpx", frames: frames)
        let candidate = TrimCandidate(url: frames[0].url, kind: .imageSequence, fileSize: 3, sequence: seq)
        var options = TrimOptions()
        options.destinationRoot = out
        options.sourceRoot = tmp
        let copied = try TrimRunner.copyWhole(candidate: candidate, to: out.appendingPathComponent("src"), options: options, progress: { _ in })
        XCTAssertEqual(copied.outputs.count, 3)
        XCTAssertEqual(copied.bytes, 3)
        XCTAssertFalse(copied.skippedExisting)
    }
}
