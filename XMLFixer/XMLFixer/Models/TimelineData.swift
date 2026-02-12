import Foundation

struct TimelineData: Identifiable {
    let id: UUID
    let sequenceName: String
    let documentID: UUID
    let sequenceID: UUID
    let totalDurationFrames: Int
    let timebase: Int
    let videoTracks: [TimelineTrack]
    let audioTracks: [TimelineTrack]
    let uniqueFilenames: Set<String>
    let startTimecodeFrame: Int
    let startTimecodeString: String?
    let ntsc: Bool

    var durationSeconds: Double {
        guard timebase > 0 else { return 0 }
        return Double(totalDurationFrames) / Double(timebase)
    }

    init(id: UUID = UUID(), sequenceName: String, documentID: UUID, sequenceID: UUID, totalDurationFrames: Int, timebase: Int, videoTracks: [TimelineTrack], audioTracks: [TimelineTrack], uniqueFilenames: Set<String>, startTimecodeFrame: Int = 0, startTimecodeString: String? = nil, ntsc: Bool = false) {
        self.id = id
        self.sequenceName = sequenceName
        self.documentID = documentID
        self.sequenceID = sequenceID
        self.totalDurationFrames = totalDurationFrames
        self.timebase = timebase
        self.videoTracks = videoTracks
        self.audioTracks = audioTracks
        self.uniqueFilenames = uniqueFilenames
        self.startTimecodeFrame = startTimecodeFrame
        self.startTimecodeString = startTimecodeString
        self.ntsc = ntsc
    }
}
