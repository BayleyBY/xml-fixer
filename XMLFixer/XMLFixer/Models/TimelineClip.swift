import Foundation

struct TimelineClip: Identifiable, Hashable {
    let id: UUID
    let startFrame: Int
    let endFrame: Int
    let sourceInFrame: Int
    let sourceOutFrame: Int
    let sourceDuration: Int
    let fileStartTimecodeFrame: Int
    let clipName: String
    let filename: String
    let fileElementID: String?
    let clipElementID: String?
    let trackIndex: Int
    let trackType: TrackType
    var effects: [ClipEffect]

    var durationFrames: Int { endFrame - startFrame }

    enum TrackType: String, Hashable {
        case video
        case audio
    }

    init(id: UUID = UUID(), startFrame: Int, endFrame: Int, sourceInFrame: Int, sourceOutFrame: Int, sourceDuration: Int, fileStartTimecodeFrame: Int = 0, clipName: String, filename: String, fileElementID: String?, clipElementID: String?, trackIndex: Int, trackType: TrackType, effects: [ClipEffect] = []) {
        self.id = id
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.sourceInFrame = sourceInFrame
        self.sourceOutFrame = sourceOutFrame
        self.sourceDuration = sourceDuration
        self.fileStartTimecodeFrame = fileStartTimecodeFrame
        self.clipName = clipName
        self.filename = filename
        self.fileElementID = fileElementID
        self.clipElementID = clipElementID
        self.trackIndex = trackIndex
        self.trackType = trackType
        self.effects = effects
    }
}
