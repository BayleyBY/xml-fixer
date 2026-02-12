import Foundation

struct TimelineTrack: Identifiable {
    let id: UUID
    let index: Int
    let trackType: TimelineClip.TrackType
    let clips: [TimelineClip]

    var label: String {
        let prefix = trackType == .video ? "V" : "A"
        return "\(prefix)\(index + 1)"
    }

    init(id: UUID = UUID(), index: Int, trackType: TimelineClip.TrackType, clips: [TimelineClip]) {
        self.id = id
        self.index = index
        self.trackType = trackType
        self.clips = clips
    }
}
