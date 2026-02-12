import SwiftUI

struct KeyframeView: View {
    let keyframes: [ClipKeyframe]
    let clipDurationFrames: Int

    private let barHeight: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(0.04))
                    .frame(height: barHeight)

                // Gradient fill
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.12), .purple.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    )
                    .frame(height: barHeight)

                // Keyframe diamonds
                ForEach(keyframes) { kf in
                    let xPos = keyframePosition(when: kf.when, totalWidth: geo.size.width)
                    VStack(spacing: 0) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)

                        if let val = Double(kf.value) {
                            Text(String(format: "%.0f", val))
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .position(x: xPos, y: barHeight / 2)
                }
            }
        }
        .frame(height: barHeight + 10)
    }

    private func keyframePosition(when: String, totalWidth: CGFloat) -> CGFloat {
        guard clipDurationFrames > 0 else { return 0 }
        let frame = Int(when) ?? 0
        let fraction = CGFloat(frame) / CGFloat(clipDurationFrames)
        let clamped = max(0, min(1, fraction))
        return clamped * totalWidth
    }
}
