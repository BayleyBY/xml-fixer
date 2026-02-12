import Foundation

enum ReferenceMatchEngine {
    /// Match sequences to scanned reference files.
    /// Matches sequence names against reference file stems (not media filenames).
    static func match(
        sequences: [(id: UUID, name: String, parentDocumentID: UUID)],
        against scannedFiles: [String: [ScannedFile]],
        strictMode: Bool,
        minChars: Int
    ) -> [ReferenceMatch] {
        sequences.map { seq in
            let stem = (seq.name as NSString).deletingPathExtension.lowercased()

            var candidates: [ReferenceCandidate] = []

            if strictMode {
                if let files = scannedFiles[stem] {
                    candidates = files.map { makeCandidate(from: $0) }
                }
            } else {
                let prefix = String(stem.prefix(max(1, minChars)))
                for (key, files) in scannedFiles where key.hasPrefix(prefix) {
                    candidates.append(contentsOf: files.map { makeCandidate(from: $0) })
                }
            }

            // Sort by file size descending (largest first)
            candidates.sort { $0.fileSize > $1.fileSize }

            let status: ReferenceMatchStatus
            let selectedIndex: Int?

            switch candidates.count {
            case 0:
                status = .unmatched
                selectedIndex = nil
            case 1:
                status = .matched
                selectedIndex = 0
            default:
                status = .multipleFound
                selectedIndex = 0
            }

            return ReferenceMatch(
                sequenceID: seq.id,
                sequenceName: seq.name,
                parentDocumentID: seq.parentDocumentID,
                candidates: candidates,
                selectedCandidateIndex: selectedIndex,
                status: status,
                userConfirmed: false
            )
        }
    }

    private static func makeCandidate(from file: ScannedFile) -> ReferenceCandidate {
        let stem = (file.url.deletingPathExtension().lastPathComponent)
        return ReferenceCandidate(
            url: file.url,
            filenameStem: stem,
            fileExtension: file.fileExtension,
            fileSize: file.fileSize
        )
    }
}
