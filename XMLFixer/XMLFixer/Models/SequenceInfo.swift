import Foundation

/// Parsed sequence metadata from an FCP XML file.
struct SequenceInfo: Identifiable {
    let id: UUID
    let sequenceElementID: String?
    var name: String
    let duration: Int?
    let timebase: Int?
    let videoTrackCount: Int
    let audioTrackCount: Int
    let parentDocumentID: UUID

    // Extended sequence metadata (Wave 1)
    var fps: Double?              // computed from sequence rate timebase + ntsc
    var audioChannelInfo: String? // "Mono" / "Stereo" / "Mixed" from track premiereTrackType attrs
    var hasNestedSequences: Bool = false
    var nestedSequenceCount: Int = 0

    // Timecode metadata
    var startTimecodeString: String?
    var startTimecodeFrame: Int?
    var startTimecodeDisplayFormat: String? // "NDF" or "DF"
    var ntsc: Bool = false

    init(id: UUID = UUID(), sequenceElementID: String?, name: String, duration: Int?, timebase: Int?, videoTrackCount: Int, audioTrackCount: Int, parentDocumentID: UUID, fps: Double? = nil, audioChannelInfo: String? = nil, hasNestedSequences: Bool = false, nestedSequenceCount: Int = 0, startTimecodeString: String? = nil, startTimecodeFrame: Int? = nil, startTimecodeDisplayFormat: String? = nil, ntsc: Bool = false) {
        self.id = id
        self.sequenceElementID = sequenceElementID
        self.name = name
        self.duration = duration
        self.timebase = timebase
        self.videoTrackCount = videoTrackCount
        self.audioTrackCount = audioTrackCount
        self.parentDocumentID = parentDocumentID
        self.fps = fps
        self.audioChannelInfo = audioChannelInfo
        self.hasNestedSequences = hasNestedSequences
        self.nestedSequenceCount = nestedSequenceCount
        self.startTimecodeString = startTimecodeString
        self.startTimecodeFrame = startTimecodeFrame
        self.startTimecodeDisplayFormat = startTimecodeDisplayFormat
        self.ntsc = ntsc
    }
}
