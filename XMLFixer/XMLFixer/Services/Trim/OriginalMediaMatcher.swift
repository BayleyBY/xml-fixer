import Foundation

/// Finds camera originals on disk for the sources used in the loaded XMLs.
enum OriginalMediaMatcher {

    /// Extension preference when several files share a stem: camera formats first, proxies last.
    static func rank(_ kind: TrimSourceKind) -> Int {
        switch kind {
        case .r3d: return 0
        case .imageSequence: return 1
        case .mxf: return 2
        case .quickTime: return 3
        case .stillImage: return 4
        case .unsupported: return 5
        }
    }

    /// Group scanned files into numbered image sequences keyed by directory + prefix + suffix (lowercased).
    static func buildSequences(from scanned: [String: [ScannedFile]]) -> [ImageSequenceInfo] {
        struct Key: Hashable { let dir: String; let prefix: String; let suffix: String }
        var groups: [Key: [ImageSequenceInfo.Frame]] = [:]
        var display: [Key: (prefix: String, suffix: String)] = [:]

        for files in scanned.values {
            for file in files where !file.isR3DSplit {
                guard TrimSourceKind.classify(extension: file.fileExtension) == .imageSequence,
                      let parsed = ImageSequenceInfo.parse(filename: file.url.lastPathComponent)
                else { continue }
                let key = Key(
                    dir: file.url.deletingLastPathComponent().path,
                    prefix: parsed.prefix.lowercased(),
                    suffix: parsed.suffix.lowercased()
                )
                groups[key, default: []].append(.init(number: parsed.number, url: file.url, fileSize: file.fileSize))
                if display[key] == nil { display[key] = (parsed.prefix, parsed.suffix) }
            }
        }

        return groups.compactMap { key, frames in
            guard frames.count > 1, let names = display[key] else { return nil }
            return ImageSequenceInfo(
                directory: URL(fileURLWithPath: key.dir, isDirectory: true),
                prefix: names.prefix,
                suffix: names.suffix,
                frames: frames.sorted { $0.number < $1.number }
            )
        }
    }

    /// Strip trailing separators so "a001c001." and "a001c001_" compare equal to the stem "a001c001".
    private static func normalizedPrefix(_ prefix: String) -> String {
        var s = prefix.lowercased()
        while let last = s.last, "._- ".contains(last) { s.removeLast() }
        return s
    }

    /// Build plan items with candidate originals for each usage summary.
    /// Total bytes of every segment of a RED clip, keyed by "<directory>|<base name lowercased>".
    static func r3dClipSizes(from scanned: [String: [ScannedFile]]) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for files in scanned.values {
            for file in files where !file.isR3DSplit && file.fileExtension == "r3d" {
                let base = REDlineTrimEngine.clipBaseName(for: file.url).lowercased()
                sizes[file.url.deletingLastPathComponent().path + "|" + base, default: 0] += file.fileSize
            }
        }
        return sizes
    }

    static func match(summaries: [MediaUsageSummary], scanned: [String: [ScannedFile]]) -> [TrimPlanItem] {
        let sequences = buildSequences(from: scanned)
        let r3dSizes = r3dClipSizes(from: scanned)
        var sequencesByPrefix: [String: [ImageSequenceInfo]] = [:]
        for seq in sequences {
            sequencesByPrefix[normalizedPrefix(seq.prefix), default: []].append(seq)
        }

        return summaries.map { summary in
            var item = TrimPlanItem(
                xmlFilename: summary.filename,
                xmlTimebase: summary.timebase,
                xmlNtsc: summary.ntsc,
                xmlStartTimecode: summary.timecodeString,
                xmlSourceDuration: summary.sourceDuration,
                mergedRanges: summary.mergedRanges
            )

            let stem = ((summary.filename as NSString).deletingPathExtension).lowercased()
            var candidates: [TrimCandidate] = []
            var usedSequenceDirs: Set<String> = []

            // 1. Sequence match on the XML filename's own sequence key (clip.1001.exr, clip.[1001-1100].exr …)
            if let key = ImageSequenceInfo.sequenceKey(fromXMLFilename: summary.filename) {
                for seq in sequencesByPrefix[normalizedPrefix(key.prefix)] ?? [] where seq.suffix.lowercased() == key.suffix {
                    candidates.append(TrimCandidate(url: seq.frames[0].url, kind: .imageSequence, fileSize: seq.totalBytes, sequence: seq))
                    usedSequenceDirs.insert(seq.directory.path + "|" + seq.prefix.lowercased() + seq.suffix.lowercased())
                }
            }

            // 2. Exact stem match (proxy "clip.mov" → original "clip.R3D" / "clip.mxf" / "clip.mov")
            for file in scanned[stem] ?? [] {
                let kind = TrimSourceKind.classify(extension: file.fileExtension)
                if kind == .imageSequence {
                    // A single frame matched by name — promote to its whole sequence
                    if let parsed = ImageSequenceInfo.parse(filename: file.url.lastPathComponent),
                       let seq = sequences.first(where: {
                           $0.directory.path == file.url.deletingLastPathComponent().path &&
                           $0.prefix.lowercased() == parsed.prefix.lowercased() &&
                           $0.suffix.lowercased() == parsed.suffix.lowercased()
                       }) {
                        let dedupe = seq.directory.path + "|" + seq.prefix.lowercased() + seq.suffix.lowercased()
                        if !usedSequenceDirs.contains(dedupe) {
                            candidates.append(TrimCandidate(url: seq.frames[0].url, kind: .imageSequence, fileSize: seq.totalBytes, sequence: seq))
                            usedSequenceDirs.insert(dedupe)
                        }
                        continue
                    }
                    // Image extension but no frame numbering / no siblings: a still
                    candidates.append(TrimCandidate(url: file.url, kind: .stillImage, fileSize: file.fileSize))
                    continue
                }
                var size = file.fileSize
                if kind == .r3d {
                    let key = file.url.deletingLastPathComponent().path + "|" + REDlineTrimEngine.clipBaseName(for: file.url).lowercased()
                    size = r3dSizes[key] ?? size
                }
                candidates.append(TrimCandidate(url: file.url, kind: kind, fileSize: size, isR3DSplit: file.isR3DSplit))
            }

            // 3. Stem matches a sequence prefix (proxy "clip.mov" → "clip.0001001.exr")
            for seq in sequencesByPrefix[stem] ?? [] {
                let dedupe = seq.directory.path + "|" + seq.prefix.lowercased() + seq.suffix.lowercased()
                if !usedSequenceDirs.contains(dedupe) {
                    candidates.append(TrimCandidate(url: seq.frames[0].url, kind: .imageSequence, fileSize: seq.totalBytes, sequence: seq))
                    usedSequenceDirs.insert(dedupe)
                }
            }

            candidates.sort {
                let r0 = rank($0.kind), r1 = rank($1.kind)
                if r0 != r1 { return r0 < r1 }
                return $0.fileSize > $1.fileSize
            }

            item.candidates = candidates
            item.selectedCandidateIndex = candidates.isEmpty ? nil : 0
            item.status = candidates.isEmpty ? .unmatched : .ready
            return item
        }
    }
}
