import SwiftUI
import AppKit
import AVKit

/// Manages the floating reference video player panel (pop-out mode).
/// When the user closes the panel via the close button, the player re-embeds
/// in the main window instead of being destroyed.
class VideoPlayerWindow: NSObject, NSWindowDelegate {
    static var shared = VideoPlayerWindow()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private weak var appState: AppState?

    func open(appState: AppState) {
        dismiss()
        self.appState = appState

        let content = VideoPlayerContent(isEmbedded: false)
            .environment(appState)

        let hosting = NSHostingView(rootView: AnyView(content))

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.title = "Reference Player"
        panel.setFrameAutosaveName("ReferencePlayerPanel")
        panel.minSize = NSSize(width: 360, height: 240)
        panel.contentView = hosting
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.hostingView = hosting
    }

    /// Programmatic close — does NOT trigger re-embed (used by embedPlayer()).
    func close() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    /// Internal dismiss without clearing delegate (used before re-open).
    private func dismiss() {
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // User clicked the close button on the floating panel.
        // Re-embed the player in the main window instead of destroying it.
        panel = nil
        hostingView = nil
        DispatchQueue.main.async { [weak self] in
            self?.appState?.isPlayerEmbedded = true
        }
    }
}
