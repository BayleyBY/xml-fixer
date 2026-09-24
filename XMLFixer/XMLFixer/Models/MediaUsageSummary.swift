import Foundation

struct MediaUsageSummary: Identifiable {
    let id: UUID
    let filename: String
    let pathURL: String?
    let sourceDuration: Int
    let timebase: Int
    let ntsc: Bool
    let hasVideo: Bool
    let hasAudio: Bool
    let audioChannelCount: Int
    let videoWidth: Int?
    let videoHeight: Int?
    let timecodeString: String?
    let reelName: String?

    var rawRanges: [SourceRange]
    var mergedRanges: [SourceRange] = []
    var fileElement: XMLElement?

    init(id: UUID = UUID(), filename: String, pathURL: String?, sourceDuration: Int, timebase: Int, ntsc: Bool, hasVideo: Bool, hasAudio: Bool, audioChannelCount: Int, videoWidth: Int? = nil, videoHeight: Int? = nil, timecodeString: String? = nil, reelName: String? = nil, rawRanges: [SourceRange], fileElement: XMLElement? = nil) {
        self.id = id
        self.filename = filename
        self.pathURL = pathURL
        self.sourceDuration = sourceDuration
        self.timebase = timebase
        self.ntsc = ntsc
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.audioChannelCount = audioChannelCount
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.timecodeString = timecodeString
        self.reelName = reelName
        self.rawRanges = rawRanges
        self.fileElement = fileElement
    }

    mutating func mergeRanges(handles: Int, mergeThreshold: Int = 0) {
        guard !rawRanges.isEmpty else {
            mergedRanges = []
            return
        }

        // Expand each range by speed-adjusted handles
        var expanded = rawRanges.map { range in
            let adjustedHandles = Int(ceil(Double(handles) * range.speedFactor))
            let inPoint = max(0, range.inPoint - adjustedHandles)
            // Slugs and ID-only file stubs report a duration of 0, so clamping the out
            // point to it would invert the range. Only clamp a duration we actually know.
            let extended = range.outPoint + adjustedHandles
            let clamped = sourceDuration > 0 ? min(sourceDuration, extended) : extended
            return SourceRange(
                inPoint: inPoint,
                outPoint: max(inPoint + 1, clamped),
                speedFactor: range.speedFactor
            )
        }
        expanded.sort()

        // Merge overlapping/touching ranges (using merge threshold as tolerance)
        var result: [SourceRange] = [expanded[0]]
        for i in 1..<expanded.count {
            let current = expanded[i]
            let last = result[result.count - 1]
            if last.mergeableWith(current, tolerance: mergeThreshold) {
                result[result.count - 1] = last.merged(with: current)
            } else {
                result.append(current)
            }
        }
        mergedRanges = result
    }
}
