import SwiftUI

struct PlayheadOverlay: View {
    let playheadFrame: Int
    let pixelsPerFrame: CGFloat
    let totalHeight: CGFloat
    let trackLabelWidth: CGFloat

    private var xPosition: CGFloat {
        trackLabelWidth + CGFloat(playheadFrame) * pixelsPerFrame
    }

    var body: some View {
        Canvas { context, size in
            let x = xPosition
            guard x >= trackLabelWidth && x <= size.width else { return }

            // Soft glow behind the line
            var glow = Path()
            glow.move(to: CGPoint(x: x, y: 0))
            glow.addLine(to: CGPoint(x: x, y: totalHeight))
            context.stroke(glow, with: .color(Color.red.opacity(0.12)), lineWidth: 5)

            // Crisp red line
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: totalHeight))
            context.stroke(line, with: .color(Color.red.opacity(0.9)), lineWidth: 1)

            // Playhead head — rounded top, pointed bottom
            let headWidth: CGFloat = 10
            let headHeight: CGFloat = 12
            let cr: CGFloat = 2.5

            var head = Path()
            head.move(to: CGPoint(x: x - headWidth / 2 + cr, y: 0))
            head.addLine(to: CGPoint(x: x + headWidth / 2 - cr, y: 0))
            head.addQuadCurve(
                to: CGPoint(x: x + headWidth / 2, y: cr),
                control: CGPoint(x: x + headWidth / 2, y: 0)
            )
            head.addLine(to: CGPoint(x: x + headWidth / 2, y: headHeight * 0.55))
            head.addLine(to: CGPoint(x: x, y: headHeight))
            head.addLine(to: CGPoint(x: x - headWidth / 2, y: headHeight * 0.55))
            head.addLine(to: CGPoint(x: x - headWidth / 2, y: cr))
            head.addQuadCurve(
                to: CGPoint(x: x - headWidth / 2 + cr, y: 0),
                control: CGPoint(x: x - headWidth / 2, y: 0)
            )
            head.closeSubpath()

            // Head fill
            context.fill(head, with: .color(Color(red: 0.92, green: 0.12, blue: 0.12)))

            // Top highlight
            var highlight = Path()
            highlight.move(to: CGPoint(x: x - headWidth / 2 + cr + 1, y: 0.5))
            highlight.addLine(to: CGPoint(x: x + headWidth / 2 - cr - 1, y: 0.5))
            context.stroke(highlight, with: .color(.white.opacity(0.25)), lineWidth: 0.5)

            // Head outline
            context.stroke(head, with: .color(Color(red: 0.6, green: 0.0, blue: 0.0)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}
