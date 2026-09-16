import Foundation

/// Trims numbered image sequences (EXR, DPX, DNG, ARRIRAW .ari …) by copying only the frames in range.
struct ImageSequenceTrimEngine: TrimEngine {
    let kind: TrimSourceKind = .imageSequence

    func trim(
        item: TrimPlanItem,
        candidate: TrimCandidate,
        range: TrimRange,
        rangeIndex: Int,
        rangeCount: Int,
        outputDirectory: URL,
        options: TrimOptions,
        progress: @escaping (Double) -> Void
    ) async throws -> TrimEngineOutput {
        guard let seq = candidate.sequence else {
            throw TrimEngineError.unreadable("Not an image sequence")
        }
        let lo = max(0, range.originalIn)
        let hi = min(seq.frames.count, range.originalOut)
        guard hi > lo else {
            throw TrimEngineError.unreadable("Range outside sequence")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var output = TrimEngineOutput()
        let frames = seq.frames[lo..<hi]
        let total = Double(frames.count)

        for (i, frame) in frames.enumerated() {
            if Task.isCancelled { throw TrimEngineError.cancelled }
            let dest = outputDirectory.appendingPathComponent(frame.url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                if options.overwriteExisting {
                    try fm.removeItem(at: dest)
                } else {
                    output.outputs.append(dest)
                    output.framesWritten += 1
                    continue
                }
            }
            try fm.copyItem(at: frame.url, to: dest)
            output.outputs.append(dest)
            output.framesWritten += 1
            output.bytesWritten += frame.fileSize
            progress(Double(i + 1) / total)
        }
        return output
    }
}
