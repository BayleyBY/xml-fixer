import SwiftUI

struct TimelineTrackView: View {
    let track: TimelineTrack
    let totalTimelineWidth: CGFloat
    let colorMap: [String: Color]
    let pixelsPerFrame: CGFloat
    let trackHeight: CGFloat
    let trackLabelWidth: CGFloat
    let selectedFilenames: Set<String>
    let isEven: Bool
    @Binding var hoveredClipID: UUID?
    let onClipTap: (TimelineClip, NSEvent.ModifierFlags) -> Void
    var onBackgroundTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Track label
            ZStack {
                Color.white.opacity(isEven ? 0.05 : 0.035)

                Text(track.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        track.trackType == .video
                            ? Color.white.opacity(0.5)
                            : Color(hue: 0.58, saturation: 0.4, brightness: 0.7)
                    )
            }
            .frame(width: trackLabelWidth, height: trackHeight)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            }

            // Track clip area — gestures handled at ZStack level for reliable hit-testing
            ZStack(alignment: .topLeading) {
                // Track background
                Color.white.opacity(isEven ? 0.03 : 0.015)

                // Clips (visual only — hit-testing done via clipAt())
                ForEach(track.clips) { clip in
                    let clipWidth = max(2, CGFloat(clip.durationFrames) * pixelsPerFrame)
                    let xOffset = CGFloat(clip.startFrame) * pixelsPerFrame
                    let isSelected = selectedFilenames.contains(clip.filename)

                    TimelineClipView(
                        clip: clip,
                        color: colorMap[clip.filename] ?? .gray,
                        pixelsPerFrame: pixelsPerFrame,
                        trackHeight: trackHeight,
                        isSelected: isSelected,
                        isHovered: hoveredClipID == clip.id
                    )
                    .frame(width: clipWidth, height: trackHeight - 4)
                    .offset(x: xOffset, y: 2)
                    .zIndex(isSelected ? 1 : 0)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: totalTimelineWidth, height: trackHeight)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let clip = clipAt(location) {
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? []
                    onClipTap(clip, modifiers)
                } else {
                    onBackgroundTap?()
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let newID = clipAt(location)?.id
                    if hoveredClipID != newID {
                        if hoveredClipID != nil { NSCursor.pop() }
                        hoveredClipID = newID
                        if newID != nil { NSCursor.pointingHand.push() }
                    }
                case .ended:
                    if hoveredClipID != nil {
                        NSCursor.pop()
                        hoveredClipID = nil
                    }
                }
            }
        }
        // Subtle track separator
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.04))
                .frame(height: 1)
        }
    }

    private func clipAt(_ location: CGPoint) -> TimelineClip? {
        track.clips.first { clip in
            let x0 = CGFloat(clip.startFrame) * pixelsPerFrame
            let x1 = x0 + max(2, CGFloat(clip.durationFrames) * pixelsPerFrame)
            return location.x >= x0 && location.x < x1
                && location.y >= 2 && location.y < trackHeight - 2
        }
    }
}
