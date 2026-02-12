import SwiftUI

struct TimelineClipView: View {
    let clip: TimelineClip
    let color: Color
    let pixelsPerFrame: CGFloat
    let trackHeight: CGFloat
    let isSelected: Bool
    let isHovered: Bool

    private var clipWidth: CGFloat {
        max(2, CGFloat(clip.durationFrames) * pixelsPerFrame)
    }

    private var isTiny: Bool {
        clipWidth < 6
    }

    private let cornerRadius: CGFloat = 5

    var body: some View {
        ZStack(alignment: .leading) {
            if isTiny {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(isSelected ? 1.0 : 0.7))
            } else {
                // Clip body — rich gradient
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                isSelected ? color : color.opacity(0.72),
                                isSelected ? color.opacity(0.75) : color.opacity(0.4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Top-edge highlight for depth
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(isSelected ? 0.22 : 0.1), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // Subtle inner shadow at bottom
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                // Selection state
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white, lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: cornerRadius + 2)
                        .strokeBorder(color.opacity(0.5), lineWidth: 3)
                        .blur(radius: 3)
                }

                // Hover state
                if isHovered && !isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }

                // Clip name
                if clipWidth > 40 {
                    Text(clip.clipName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 1.5, x: 0, y: 1)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 5)
                        .padding(.top, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(height: trackHeight - 4)
        .brightness(isHovered ? 0.08 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .help("\(clip.clipName)\n\(clip.filename)\nFrames: \(clip.startFrame)-\(clip.endFrame) (\(clip.durationFrames)f)")
    }
}
