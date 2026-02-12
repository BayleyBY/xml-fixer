import SwiftUI

struct ToolbarActions: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        @Bindable var appState = appState

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                appState.showRemoveMediaAlert = true
            } label: {
                ToolbarLabel("Remove", systemImage: "trash")
            }
            .disabled(appState.selectedMediaIDs.isEmpty)
            .help("Remove selected media from all loaded XMLs")
            .tint(.red)

            Button {
                appState.showStripAudioAlert = true
            } label: {
                ToolbarLabel("Strip Audio", systemImage: "speaker.slash")
            }
            .disabled(!appState.hasDocuments)
            .help("Remove all audio tracks from all loaded XMLs")

            Button {
                appState.showRenameTimelinesAlert = true
            } label: {
                ToolbarLabel("Rename TLs", systemImage: "pencil")
            }
            .disabled(!appState.hasDocuments)
            .help("Set sequence names to match filenames")

            if appState.hasNestedSequences {
                Button {
                    appState.showDenestAlert = true
                } label: {
                    ToolbarLabel("Denest", systemImage: "rectangle.on.rectangle.slash")
                }
                .tint(.red)
                .help("Flatten all nested sequences")
            }

            Button {
                appState.isShowingRelinkSheet = true
            } label: {
                ToolbarLabel("Relink", systemImage: "link")
            }
            .disabled(!appState.hasDocuments)
            .help("Relink media file paths to a conform location")

            Button {
                appState.isShowingCollectSheet = true
            } label: {
                ToolbarLabel("Collect", systemImage: "folder.badge.plus")
            }
            .disabled(!appState.hasDocuments)
            .help("Copy linked media files to a new location")

            Button {
                appState.isShowingReferenceMatchSheet = true
            } label: {
                ToolbarLabel("Refs", systemImage: "play.rectangle")
            }
            .disabled(!appState.hasDocuments)
            .help("Match reference video files to timelines")

            Button {
                appState.timecodeEditTargetSequenceID = nil
                appState.isShowingTimecodeEditSheet = true
            } label: {
                ToolbarLabel("Edit TC", systemImage: "clock")
            }
            .disabled(!appState.hasDocuments)
            .help("Edit timeline start timecodes")

            Divider()

            Button {
                appState.isShowingSourcesExportSheet = true
            } label: {
                ToolbarLabel("Sources XML", systemImage: "film.stack")
            }
            .disabled(!appState.hasDocuments)
            .help("Export Sources Sequence XML with best-length clips")

            Button {
                appState.exportCSV()
            } label: {
                ToolbarLabel("CSV", systemImage: "tablecells")
            }
            .disabled(!appState.hasDocuments)
            .help("Export media list as CSV")

            Button {
                appState.isShowingScaleCalculator = true
            } label: {
                ToolbarLabel("Scale", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Open scale / resize calculator")

            Button {
                appState.isShowingExportSheet = true
            } label: {
                ToolbarLabel("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(!appState.hasDocuments)
        }

        // Alerts
        ToolbarItem(placement: .status) {
            Text("")
                .alert("Strip All Audio Tracks?", isPresented: $appState.showStripAudioAlert) {
                    Button("Strip Audio", role: .destructive) {
                        appState.removeAllAudioTracks()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Strip all audio tracks from \(appState.documents.count) XMLs?")
                }
                .alert("Rename Timelines?", isPresented: $appState.showRenameTimelinesAlert) {
                    Button("Rename") {
                        appState.renameTimelines()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    let lines = appState.documents.flatMap { doc in
                        doc.sequences.map { "\($0.name) → \(doc.filenameWithoutExtension)" }
                    }.joined(separator: "\n")
                    Text("Rename sequences in \(appState.documents.count) XMLs to match their filenames?\n\n\(lines)")
                }
        }
    }
}

// MARK: - Toolbar icon + text label

private struct ToolbarLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: 14))
            Text(title)
                .font(.system(size: 9))
        }
        .frame(minWidth: 32)
    }
}
