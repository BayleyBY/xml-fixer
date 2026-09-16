import Foundation

/// Executes a trim plan item by item, sequentially (disk-bound work), reporting progress.
enum TrimRunner {

    static func run(
        items: [TrimPlanItem],
        options: TrimOptions,
        registry: TrimEngineRegistry,
        progress: @escaping (TrimProgress) -> Void
    ) async -> [TrimResultItem] {
        let actionable = items.filter { $0.status.isActionable && $0.selectedCandidate != nil }
        var results: [TrimResultItem] = []
        var state = TrimProgress(itemIndex: 0, itemCount: actionable.count)

        for (index, item) in actionable.enumerated() {
            if Task.isCancelled { break }
            state.itemIndex = index
            state.currentFilename = item.xmlFilename
            state.currentFraction = 0
            progress(state)

            let result = await process(item: item, options: options, registry: registry) { fraction in
                state.currentFraction = fraction
                progress(state)
            }
            results.append(result)
        }
        state.itemIndex = actionable.count
        state.currentFraction = 0
        progress(state)
        return results
    }

    static func process(
        item: TrimPlanItem,
        options: TrimOptions,
        registry: TrimEngineRegistry,
        progress: @escaping (Double) -> Void
    ) async -> TrimResultItem {
        guard let candidate = item.selectedCandidate else {
            return TrimResultItem(planItemID: item.id, xmlFilename: item.xmlFilename, originalURL: nil, status: .skipped("Unmatched"))
        }
        var result = TrimResultItem(planItemID: item.id, xmlFilename: item.xmlFilename, originalURL: candidate.url, status: .trimmed)
        guard let outputDir = TrimNaming.destinationDirectory(for: candidate.url, options: options) else {
            result.status = .failed("No destination folder")
            return result
        }

        switch item.status {
        case .copyWhole(let reason):
            result.messages.append(reason)
            do {
                let copied = try copyWhole(candidate: candidate, to: outputDir, options: options, progress: progress)
                result.outputs = copied.outputs
                result.bytesWritten = copied.bytes
                result.status = copied.skippedExisting ? .skippedExisting : .copiedWhole
            } catch {
                result.status = .failed(error.localizedDescription)
            }
        case .ready:
            let (engine, reason) = registry.engine(for: candidate.kind)
            guard let engine else {
                result.status = .skipped(reason ?? "No engine")
                return result
            }
            let rangeCount = item.trimRanges.count
            var anyWritten = false
            var allExisting = true
            for (i, range) in item.trimRanges.enumerated() {
                if Task.isCancelled { result.status = .failed("Cancelled"); return result }
                do {
                    let out = try await engine.trim(
                        item: item, candidate: candidate, range: range, rangeIndex: i, rangeCount: rangeCount,
                        outputDirectory: outputDir, options: options
                    ) { fraction in
                        progress((Double(i) + fraction) / Double(max(1, rangeCount)))
                    }
                    result.outputs.append(contentsOf: out.outputs)
                    result.framesWritten += out.framesWritten
                    result.extraFrames += out.extraFrames
                    result.bytesWritten += out.bytesWritten
                    result.messages.append(contentsOf: out.messages)
                    if result.commandLine == nil { result.commandLine = out.commandLine }
                    anyWritten = true
                    allExisting = false
                } catch TrimEngineError.outputExists(let url) {
                    result.messages.append("Exists: \(url.lastPathComponent)")
                    result.outputs.append(url)
                } catch {
                    result.status = .failed(error.localizedDescription)
                    return result
                }
            }
            if !anyWritten && allExisting { result.status = .skippedExisting }
        case .unmatched:
            result.status = .skipped("Unmatched")
        case .invalid(let why):
            result.status = .skipped(why)
        }
        return result
    }

    /// Copy an original untrimmed: a single file, every R3D segment, or every frame of a sequence.
    static func copyWhole(candidate: TrimCandidate, to outputDir: URL, options: TrimOptions, progress: @escaping (Double) -> Void) throws -> (outputs: [URL], bytes: Int64, skippedExisting: Bool) {
        let fm = FileManager.default
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        var sources: [URL] = []
        if let seq = candidate.sequence {
            sources = seq.frames.map(\.url)
        } else if candidate.isR3DSplit || candidate.kind == .r3d {
            sources = r3dSegments(for: candidate.url)
        } else {
            sources = [candidate.url]
        }

        var outputs: [URL] = []
        var bytes: Int64 = 0
        var skipped = 0
        for (i, src) in sources.enumerated() {
            if Task.isCancelled { throw TrimEngineError.cancelled }
            let dest = outputDir.appendingPathComponent(src.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                if options.overwriteExisting {
                    try fm.removeItem(at: dest)
                } else {
                    outputs.append(dest)
                    skipped += 1
                    continue
                }
            }
            try fm.copyItem(at: src, to: dest)
            outputs.append(dest)
            bytes += (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
            progress(Double(i + 1) / Double(sources.count))
        }
        return (outputs, bytes, skipped == sources.count && !sources.isEmpty)
    }

    /// All segment files belonging to a RED clip: `clip_001.R3D`, `clip_002.R3D` … plus the file itself.
    static func r3dSegments(for url: URL) -> [URL] {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var base = stem
        if let regex = try? NSRegularExpression(pattern: "_\\d{3}$"),
           let m = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
           let r = Range(m.range, in: stem) {
            base = String(stem[..<r.lowerBound])
        }
        let siblings = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let matches = siblings.filter { sibling in
            guard sibling.pathExtension.lowercased() == "r3d" else { return false }
            let s = sibling.deletingPathExtension().lastPathComponent
            if s.lowercased() == stem.lowercased() { return true }
            guard s.lowercased().hasPrefix(base.lowercased() + "_") else { return false }
            let tail = s.dropFirst(base.count + 1)
            return tail.count == 3 && tail.allSatisfy(\.isNumber)
        }
        return matches.isEmpty ? [url] : matches.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
