import SwiftUI

struct TimelineRulerView: View {
    let totalFrames: Int
    let timebase: Int
    let pixelsPerFrame: CGFloat
    let playheadFrame: Int

    private var totalWidth: CGFloat {
        CGFloat(totalFrames) * pixelsPerFrame
    }

    var body: some View {
        Canvas { context, size in
            let effectiveTimebase = max(1, timebase)

            // Dark ruler background
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.white.opacity(0.04))
            )

            // Bottom border
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 0.5))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            context.stroke(baseline, with: .color(.white.opacity(0.08)), lineWidth: 0.5)

            // Tick spacing based on zoom
            let secondWidth = CGFloat(effectiveTimebase) * pixelsPerFrame
            let majorTickInterval: Int
            if secondWidth > 100 {
                majorTickInterval = 1
            } else if secondWidth > 20 {
                majorTickInterval = 5
            } else if secondWidth > 8 {
                majorTickInterval = 10
            } else if secondWidth > 3 {
                majorTickInterval = 30
            } else if secondWidth > 1 {
                majorTickInterval = 60
            } else if secondWidth > 0.4 {
                majorTickInterval = 300
            } else if secondWidth > 0.1 {
                majorTickInterval = 600
            } else {
                majorTickInterval = 1800
            }

            let totalSeconds = totalFrames / max(1, effectiveTimebase) + 1

            // Minor ticks
            let minorInterval = max(1, majorTickInterval / 5)
            if minorInterval < majorTickInterval {
                for sec in stride(from: 0, through: totalSeconds, by: minorInterval) {
                    if sec % majorTickInterval == 0 { continue }
                    let x = CGFloat(sec * effectiveTimebase) * pixelsPerFrame
                    guard x <= size.width else { break }

                    var tickPath = Path()
                    tickPath.move(to: CGPoint(x: x, y: size.height - 4))
                    tickPath.addLine(to: CGPoint(x: x, y: size.height - 1))
                    context.stroke(tickPath, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
                }
            }

            // Major ticks + labels
            for sec in stride(from: 0, through: totalSeconds, by: majorTickInterval) {
                let x = CGFloat(sec * effectiveTimebase) * pixelsPerFrame
                guard x <= size.width else { break }

                var tickPath = Path()
                tickPath.move(to: CGPoint(x: x, y: size.height - 9))
                tickPath.addLine(to: CGPoint(x: x, y: size.height - 1))
                context.stroke(tickPath, with: .color(.white.opacity(0.25)), lineWidth: 1)

                let mins = sec / 60
                let secs = sec % 60
                let label = String(format: "%d:%02d", mins, secs)
                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
                context.draw(text, at: CGPoint(x: x + 3, y: 4), anchor: .topLeading)
            }

            // Playhead marker on ruler
            if playheadFrame > 0 {
                let phX = CGFloat(playheadFrame) * pixelsPerFrame
                if phX >= 0 && phX <= size.width {
                    var marker = Path()
                    marker.move(to: CGPoint(x: phX - 4, y: size.height))
                    marker.addLine(to: CGPoint(x: phX + 4, y: size.height))
                    marker.addLine(to: CGPoint(x: phX, y: size.height - 6))
                    marker.closeSubpath()
                    context.fill(marker, with: .color(Color.red))
                }
            }
        }
        .frame(width: totalWidth, height: 24)
    }
}
