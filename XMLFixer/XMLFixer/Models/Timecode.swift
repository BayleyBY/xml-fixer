import Foundation

/// Frame-accurate timecode value type for FCP XML timecodes.
struct Timecode: Equatable, CustomStringConvertible {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int
    let timebase: Int
    let isDropFrame: Bool

    var totalFrames: Int {
        (hours * 3600 + minutes * 60 + seconds) * timebase + frames
    }

    var description: String {
        let sep = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", hours, minutes, seconds, sep, frames)
    }

    /// Parse "HH:MM:SS:FF" or "HH:MM:SS;FF" string
    static func parse(_ string: String, timebase: Int, dropFrame: Bool = false) -> Timecode? {
        let cleaned = string.replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else { return nil }
        return Timecode(hours: parts[0], minutes: parts[1], seconds: parts[2], frames: parts[3], timebase: timebase, isDropFrame: dropFrame)
    }

    /// Create from total frame count
    static func fromFrames(_ totalFrames: Int, timebase: Int, dropFrame: Bool = false) -> Timecode {
        guard timebase > 0 else {
            return Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, timebase: timebase, isDropFrame: dropFrame)
        }
        let f = totalFrames % timebase
        let totalSeconds = totalFrames / timebase
        let s = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let m = totalMinutes % 60
        let h = totalMinutes / 60
        return Timecode(hours: h, minutes: m, seconds: s, frames: f, timebase: timebase, isDropFrame: dropFrame)
    }

    /// Add frame offset
    func adding(frames offset: Int) -> Timecode {
        Timecode.fromFrames(totalFrames + offset, timebase: timebase, dropFrame: isDropFrame)
    }

    /// Frame difference (self - other), can be negative
    func framesDifference(from other: Timecode) -> Int {
        totalFrames - other.totalFrames
    }
}
