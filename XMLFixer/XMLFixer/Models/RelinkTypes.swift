import Foundation

enum RelinkStatus {
    case unlinked           // Red — no match found
    case matched            // Green — single match or user-confirmed pick
    case multipleFound      // Orange — multiple candidates, largest auto-selected
}

struct ScannedFile {
    let url: URL
    let fileSize: Int64
    let fileExtension: String
    let isR3DSplit: Bool
}

struct RelinkCandidate: Identifiable {
    let id: UUID
    let url: URL
    let filenameStem: String
    let fileExtension: String
    let fileSize: Int64
    let isR3DSplit: Bool

    init(id: UUID = UUID(), url: URL, filenameStem: String, fileExtension: String, fileSize: Int64, isR3DSplit: Bool = false) {
        self.id = id
        self.url = url
        self.filenameStem = filenameStem
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.isR3DSplit = isR3DSplit
    }

    var displaySize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var displayFilename: String {
        let name = filenameStem + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        return isR3DSplit ? "\(name) (R3D split)" : name
    }
}

struct RelinkMatch: Identifiable {
    let id: UUID
    let mediaFilename: String
    let mediaID: UUID
    var candidates: [RelinkCandidate]
    var selectedCandidateIndex: Int?
    var status: RelinkStatus
    var userConfirmed: Bool

    init(id: UUID = UUID(), mediaFilename: String, mediaID: UUID, candidates: [RelinkCandidate], selectedCandidateIndex: Int? = nil, status: RelinkStatus = .unlinked, userConfirmed: Bool = false) {
        self.id = id
        self.mediaFilename = mediaFilename
        self.mediaID = mediaID
        self.candidates = candidates
        self.selectedCandidateIndex = selectedCandidateIndex
        self.status = status
        self.userConfirmed = userConfirmed
    }

    var selectedPath: String? {
        guard let idx = selectedCandidateIndex, idx < candidates.count else { return nil }
        return candidates[idx].url.path
    }
}
