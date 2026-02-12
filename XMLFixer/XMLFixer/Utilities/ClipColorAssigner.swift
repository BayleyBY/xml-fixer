import SwiftUI

struct ClipColorAssigner {
    static let palette: [Color] = [
        Color(hue: 0.58, saturation: 0.65, brightness: 0.85),  // Blue
        Color(hue: 0.35, saturation: 0.60, brightness: 0.75),  // Green
        Color(hue: 0.08, saturation: 0.70, brightness: 0.90),  // Orange
        Color(hue: 0.75, saturation: 0.55, brightness: 0.80),  // Purple
        Color(hue: 0.50, saturation: 0.60, brightness: 0.80),  // Teal
        Color(hue: 0.95, saturation: 0.60, brightness: 0.85),  // Pink
        Color(hue: 0.15, saturation: 0.65, brightness: 0.85),  // Yellow-Orange
        Color(hue: 0.65, saturation: 0.50, brightness: 0.75),  // Indigo
        Color(hue: 0.42, saturation: 0.55, brightness: 0.70),  // Olive-Green
        Color(hue: 0.85, saturation: 0.50, brightness: 0.80),  // Mauve
    ]

    static let audioPalette: [Color] = [
        Color(hue: 0.58, saturation: 0.30, brightness: 0.60),
        Color(hue: 0.35, saturation: 0.30, brightness: 0.55),
        Color(hue: 0.08, saturation: 0.35, brightness: 0.65),
        Color(hue: 0.75, saturation: 0.25, brightness: 0.55),
        Color(hue: 0.50, saturation: 0.30, brightness: 0.55),
        Color(hue: 0.95, saturation: 0.30, brightness: 0.60),
        Color(hue: 0.15, saturation: 0.35, brightness: 0.60),
        Color(hue: 0.65, saturation: 0.25, brightness: 0.55),
        Color(hue: 0.42, saturation: 0.25, brightness: 0.50),
        Color(hue: 0.85, saturation: 0.25, brightness: 0.55),
    ]

    static func buildColorMap(from filenames: Set<String>, trackType: TimelineClip.TrackType = .video) -> [String: Color] {
        let pal = trackType == .video ? palette : audioPalette
        let sorted = filenames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var map: [String: Color] = [:]
        for (i, name) in sorted.enumerated() {
            map[name] = pal[i % pal.count]
        }
        return map
    }
}
