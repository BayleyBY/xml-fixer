import Foundation

/// Represents a unique media file referenced by one or more loaded XMLs.
/// Identified by its filename (deduplicated across all loaded XMLs).
struct MediaReference: Identifiable, Hashable {

    /// A reference to a specific sequence within a specific document.
    struct SequenceRef: Hashable {
        let documentID: UUID
        let sequenceName: String
    }

    let id: UUID
    let filename: String
    let fileExtension: String
    let pathURL: String?
    var fileElementIDs: Set<String>
    var referencingDocuments: Set<UUID>
    var clipCount: Int

    // Rich metadata (Feature 2)
    var reelName: String?
    var timecodeString: String?
    var timecodeFrame: Int?
    var displayFormat: String?

    // Extended media metadata (Wave 1)
    var fps: Double?              // computed from timebase + ntsc (e.g. 23.976, 25.0)
    var resolution: String?       // "1920x1080" or "1920x1318"
    var codec: String?            // "Apple ProRes 422"
    var audioChannels: Int?       // 1=mono, 2=stereo
    var sourceDurationFrames: Int? // total source frames from <file><duration>
    var isTimewarped: Bool = false // true if any clipitem referencing this file has speed/variablespeed effect

    // Sequence back-references (Feature 5)
    var referencingSequences: Set<SequenceRef> = []

    var hasAPrefix: Bool { filename.hasPrefix("A_") }

    // Sort-safe computed properties for Table column sorting
    var xmlCount: Int { referencingDocuments.count }
    var sortableReelName: String { reelName ?? "" }
    var sortableTimecodeFrame: Int { timecodeFrame ?? Int.max }
    var sortableFPS: Double { fps ?? 0 }
    var sortableResolution: String { resolution ?? "" }
    var sortableSpeed: Int { isTimewarped ? 0 : 1 }
    var sortablePath: String { pathURL ?? "" }

    init(
        id: UUID = UUID(),
        filename: String,
        pathURL: String?,
        fileElementIDs: Set<String>,
        referencingDocuments: Set<UUID>,
        clipCount: Int,
        reelName: String? = nil,
        timecodeString: String? = nil,
        timecodeFrame: Int? = nil,
        displayFormat: String? = nil,
        referencingSequences: Set<SequenceRef> = [],
        fps: Double? = nil,
        resolution: String? = nil,
        codec: String? = nil,
        audioChannels: Int? = nil,
        sourceDurationFrames: Int? = nil,
        isTimewarped: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.fileExtension = (filename as NSString).pathExtension.lowercased()
        self.pathURL = pathURL
        self.fileElementIDs = fileElementIDs
        self.referencingDocuments = referencingDocuments
        self.clipCount = clipCount
        self.reelName = reelName
        self.timecodeString = timecodeString
        self.timecodeFrame = timecodeFrame
        self.displayFormat = displayFormat
        self.referencingSequences = referencingSequences
        self.fps = fps
        self.resolution = resolution
        self.codec = codec
        self.audioChannels = audioChannels
        self.sourceDurationFrames = sourceDurationFrames
        self.isTimewarped = isTimewarped
    }

    // Hashing and equality are based solely on `id`.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MediaReference, rhs: MediaReference) -> Bool {
        lhs.id == rhs.id
    }
}
