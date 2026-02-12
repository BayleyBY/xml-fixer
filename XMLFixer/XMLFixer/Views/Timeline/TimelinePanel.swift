import SwiftUI

struct TimelinePanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            if let timeline = appState.currentTimelineData {
                HStack(spacing: 0) {
                    TimelineView(timeline: timeline)

                    if let clip = appState.selectedTimelineClip {
                        Rectangle()
                            .fill(.white.opacity(0.06))
                            .frame(width: 1)
                        ClipInspectorView(clip: clip)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "timeline.selection")
                        .font(.system(size: 28, weight: .thin))
                        .foregroundStyle(.white.opacity(0.2))
                    Text("Select a sequence to view its timeline")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.08))
        .environment(\.colorScheme, .dark)
        .frame(minHeight: 140, idealHeight: 220)
    }
}
