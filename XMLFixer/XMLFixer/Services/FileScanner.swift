import Foundation

enum FileScanner {

    /// Recursively scans a directory for files, building a dictionary keyed by lowercased filename stem (no extension).
    /// Each key maps to an array of ScannedFile entries found on disk.
    /// - Parameters:
    ///   - directory: Root directory to scan recursively
    ///   - extensionFilter: If non-nil and non-empty, only include files with this extension (case-insensitive)
    /// - Returns: Dictionary of [lowercased stem: [ScannedFile]]
    static func scan(directory: URL, extensionFilter: String?) async -> [String: [ScannedFile]] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = performScan(directory: directory, extensionFilter: extensionFilter)
                continuation.resume(returning: result)
            }
        }
    }

    private static func performScan(directory: URL, extensionFilter: String?) -> [String: [ScannedFile]] {
        var fileMap: [String: [ScannedFile]] = [:]
        let fm = FileManager.default

        // Need security-scoped access for sandboxed apps
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return fileMap
        }

        let extFilter = extensionFilter?.trimmingCharacters(in: .whitespaces).lowercased()
        let hasExtFilter = extFilter != nil && !extFilter!.isEmpty

        // Regex for R3D split segments: filename ending with _NNN.R3D (case insensitive)
        let r3dSegmentPattern = try? NSRegularExpression(pattern: "_\\d{3}$", options: [])

        var r3dSyntheticEntries: [String: ScannedFile] = [:] // base name → first segment

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true else { continue }

            let filename = fileURL.lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            let stem = (filename as NSString).deletingPathExtension
            let stemLower = stem.lowercased()

            // Apply extension filter
            if hasExtFilter && ext != extFilter! { continue }

            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let scannedFile = ScannedFile(url: fileURL, fileSize: fileSize, fileExtension: ext, isR3DSplit: false)

            fileMap[stemLower, default: []].append(scannedFile)

            // R3D split handling: if stem matches *_NNN and extension is r3d
            if ext == "r3d" {
                let stemNS = stemLower as NSString
                let range = NSRange(location: 0, length: stemNS.length)
                if let match = r3dSegmentPattern?.firstMatch(in: stemLower, options: [], range: range) {
                    // This is a segment file — extract base name without _NNN
                    let baseName = String(stemLower[stemLower.startIndex..<stemLower.index(stemLower.startIndex, offsetBy: match.range.location)])

                    // Register synthetic entry under the base name if not already present
                    if r3dSyntheticEntries[baseName] == nil {
                        r3dSyntheticEntries[baseName] = ScannedFile(
                            url: fileURL,
                            fileSize: fileSize,
                            fileExtension: ext,
                            isR3DSplit: true
                        )
                    }
                }
            }
        }

        // Add synthetic R3D entries for base names that don't already have a direct match
        for (baseName, syntheticFile) in r3dSyntheticEntries {
            let existing = fileMap[baseName] ?? []
            // Only add if there's no non-synthetic file already matching the base name
            let hasDirectMatch = existing.contains { !$0.isR3DSplit }
            if !hasDirectMatch {
                fileMap[baseName, default: []].append(syntheticFile)
            }
        }

        return fileMap
    }
}
