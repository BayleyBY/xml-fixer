import AppKit
import SwiftUI

extension View {
    /// SwiftUI sheets on macOS 14 are fixed-size. This adds `.resizable` to the sheet's
    /// window, which cannot shrink below `minSize`. Pair it with a flexible
    /// `.frame(minWidth:…maxWidth: .infinity…)` so the content follows the window.
    func resizableSheet(minSize: CGSize) -> some View {
        background(ResizableSheetEnabler(minSize: minSize))
    }
}

private struct ResizableSheetEnabler: NSViewRepresentable {
    let minSize: CGSize

    func makeNSView(context: Context) -> NSView { ResizableWindowView(minSize: minSize) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ResizableWindowView: NSView {
    private let minSize: CGSize
    private var observations: [NSKeyValueObservation] = []

    init(minSize: CGSize) {
        self.minSize = minSize
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observations = []
        guard let window else { return }
        let minSize = minSize
        Self.apply(to: window, minSize: minSize)
        // SwiftUI rewrites the sheet's style mask while presenting it and resets its minimum
        // size on every layout; put both back whenever they change.
        let reapply: (NSWindow) -> Void = { window in
            DispatchQueue.main.async { Self.apply(to: window, minSize: minSize) }
        }
        observations = [
            window.observe(\.styleMask) { window, _ in reapply(window) },
            window.observe(\.contentMinSize) { window, _ in reapply(window) },
        ]
    }

    private static func apply(to window: NSWindow, minSize: CGSize) {
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        if window.contentMinSize != minSize {
            window.contentMinSize = minSize
        }
    }
}
