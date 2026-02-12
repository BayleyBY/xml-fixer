import Foundation

enum TimecodeUtil {
    /// Format a frame count as timecode string "HH:MM:SS:FF"
    static func format(frames: Int, timebase: Int) -> String {
        let tc = Timecode.fromFrames(frames, timebase: timebase)
        return tc.description
    }

    /// Validate a timecode string format
    static func isValid(_ string: String, timebase: Int) -> Bool {
        Timecode.parse(string, timebase: timebase) != nil
    }

    /// Convert timeline frame position to absolute timecode
    static func timelineFrameToAbsoluteTC(frame: Int, startTC: Timecode) -> Timecode {
        startTC.adding(frames: frame)
    }

    /// Convert absolute timecode to timeline frame position
    static func absoluteTCToTimelineFrame(absoluteTC: Timecode, startTC: Timecode) -> Int {
        absoluteTC.framesDifference(from: startTC)
    }
}
