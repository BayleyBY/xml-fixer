import Foundation

enum RelinkEngine {

    /// Matches media references against scanned files.
    /// - Parameters:
    ///   - mediaFilenames: Array of (mediaID, filename) tuples from MediaReference list
    ///   - scannedFiles: Dictionary from FileScanner.scan()
    ///   - strictMode: If true, only exact stem matches. If false, uses prefix matching with minChars.
    ///   - minChars: Minimum number of characters from the start of the filename stem for fuzzy matching
    /// - Returns: Array of RelinkMatch for each media file
    static func match(
        mediaFilenames: [(id: UUID, filename: String)],
        against scannedFiles: [String: [ScannedFile]],
        strictMode: Bool,
        minChars: Int
    ) -> [RelinkMatch] {
        var results: [RelinkMatch] = []

        for (mediaID, filename) in mediaFilenames {
            let stem = ((filename as NSString).deletingPathExtension as String).lowercased()

            var foundFiles: [ScannedFile] = []

            if strictMode {
                // Exact stem match
                foundFiles = scannedFiles[stem] ?? []
            } else {
                // Fuzzy prefix match: take first minChars of the stem
                let charCount = min(minChars, stem.count)
                guard charCount > 0 else {
                    results.append(RelinkMatch(mediaFilename: filename, mediaID: mediaID, candidates: [], status: .unlinked))
                    continue
                }
                let prefix = String(stem.prefix(charCount))

                for (key, files) in scannedFiles {
                    if key.hasPrefix(prefix) {
                        foundFiles.append(contentsOf: files)
                    }
                }
            }

            // Build candidates sorted by file size descending (largest first)
            let candidates = foundFiles
                .sorted { $0.fileSize > $1.fileSize }
                .map { file in
                    RelinkCandidate(
                        url: file.url,
                        filenameStem: (file.url.deletingPathExtension().lastPathComponent),
                        fileExtension: file.fileExtension,
                        fileSize: file.fileSize,
                        isR3DSplit: file.isR3DSplit
                    )
                }

            let status: RelinkStatus
            let selectedIndex: Int?

            switch candidates.count {
            case 0:
                status = .unlinked
                selectedIndex = nil
            case 1:
                status = .matched
                selectedIndex = 0
            default:
                status = .multipleFound
                selectedIndex = 0 // auto-select largest (first after sort)
            }

            results.append(RelinkMatch(
                mediaFilename: filename,
                mediaID: mediaID,
                candidates: candidates,
                selectedCandidateIndex: selectedIndex,
                status: status
            ))
        }

        return results
    }
}
