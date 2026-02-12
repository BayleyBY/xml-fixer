import SwiftUI

struct MediaListView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: [KeyPathComparator<MediaReference>] = [
        .init(\.filename, order: .forward)
    ]

    private static let audioExtensions: Set<String> = ["wav", "mp3", "aac", "aif", "aiff"]

    private var sortedMedia: [MediaReference] {
        let sorted = appState.filteredMedia.sorted(using: sortOrder)
        if appState.groupByExtension {
            var byExt: [String: [MediaReference]] = [:]
            for item in sorted {
                byExt[item.fileExtension, default: []].append(item)
            }
            var grouped: [MediaReference] = []
            for ext in byExt.keys.sorted() {
                grouped.append(contentsOf: byExt[ext]!)
            }
            return grouped
        }
        return sorted
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            filterBar

            Divider()

            mediaTable

            statusBar
        }
        .navigationTitle("Media References")
        .onDeleteCommand {
            if !appState.selectedMediaIDs.isEmpty {
                appState.showRemoveMediaAlert = true
            }
        }
        .alert("Remove Selected Media?", isPresented: $appState.showRemoveMediaAlert) {
            Button("Remove", role: .destructive) {
                appState.removeSelectedMedia()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let preview = appState.removeMediaPreview
            Text("Remove \(preview.mediaCount) media items (\(preview.clipCount) clips) from \(preview.docCount) XMLs?")
        }
        .sheet(isPresented: Binding(get: { appState.editingMediaID != nil }, set: { if !$0 { appState.editingMediaID = nil } })) {
            if let media = appState.editingMedia {
                MediaEditPopover(media: media)
            }
        }
        .sheet(isPresented: $appState.isShowingBatchRename) {
            BatchRenameSheet()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        @Bindable var appState = appState
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.caption)

            TextField("Search media...", text: $appState.mediaSearchText)
                .textFieldStyle(.plain)
                .frame(maxWidth: 220)

            Divider().frame(height: 14)

            TextField("Filter (e.g. A_*, *.mov)", text: $appState.mediaFilterPattern)
                .textFieldStyle(.plain)
                .frame(maxWidth: 180)

            if !appState.mediaFilterPattern.isEmpty {
                Button {
                    appState.mediaFilterPattern = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
            }

            Toggle("Group by ext", isOn: $appState.groupByExtension)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            Spacer()

            if appState.selectedMediaCount > 0 {
                Text("\(appState.selectedMediaCount) selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Media Table

    private var mediaTable: some View {
        @Bindable var appState = appState
        return Table(sortedMedia, selection: $appState.selectedMediaIDs, sortOrder: $sortOrder) {
            TableColumn("Filename", value: \.filename) { media in
                HStack {
                    Image(systemName: iconName(for: media))
                        .foregroundStyle(iconColor(for: media))
                        .font(.caption)
                    Text(media.filename)
                        .lineLimit(1)
                }
            }
            .width(min: 200, ideal: 350)

            TableColumn("Clips", value: \.clipCount) { media in
                Text("\(media.clipCount)")
                    .monospacedDigit()
            }
            .width(50)

            TableColumn("XMLs", value: \.xmlCount) { media in
                Text("\(media.xmlCount)")
                    .monospacedDigit()
            }
            .width(50)

            TableColumn("Reel", value: \.sortableReelName) { media in
                MediaReelCell(media: media)
            }
            .width(min: 80, ideal: 120)

            TableColumn("TC In", value: \.sortableTimecodeFrame) { media in
                Text(media.timecodeString ?? "\u{2014}")
                    .monospacedDigit()
                    .foregroundStyle(media.timecodeString == nil ? .tertiary : .primary)
            }
            .width(min: 80, ideal: 110)

            TableColumn("FPS", value: \.sortableFPS) { media in
                MediaFPSCell(media: media, sequenceFPS: sequenceFPS(for: media))
            }
            .width(50)

            TableColumn("Res", value: \.sortableResolution) { media in
                Text(media.resolution ?? "\u{2014}")
                    .foregroundStyle(media.resolution == nil ? .tertiary : .primary)
            }
            .width(80)

            TableColumn("Speed", value: \.sortableSpeed) { media in
                if media.isTimewarped {
                    Text("TW")
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                } else {
                    Text("\u{2014}")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(45)

            TableColumn("Path", value: \.sortablePath) { media in
                Text(media.pathURL ?? "--")
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .help(media.pathURL ?? "No path")
            }
            .width(min: 100, ideal: 200)
        }
        .contextMenu(forSelectionType: MediaReference.ID.self) { selection in
            contextMenuContent(selection: selection)
        } primaryAction: { selection in
            if let first = selection.first {
                appState.editingMediaID = first
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuContent(selection: Set<MediaReference.ID>) -> some View {
        if selection.count == 1 {
            Button("Edit...") {
                appState.editingMediaID = selection.first
            }
        }
        if selection.count == 1,
           let mediaRef = appState.filteredMedia.first(where: { selection.contains($0.id) }) {
            if !mediaRef.referencingSequences.isEmpty {
                Menu("Show Timelines") {
                    ForEach(Array(mediaRef.referencingSequences).sorted(by: { $0.sequenceName < $1.sequenceName }), id: \.self) { seqRef in
                        let docName = appState.documents.first(where: { $0.id == seqRef.documentID })?.filename ?? "?"
                        Button("\(seqRef.sequenceName) \u{2014} \(docName)") {
                            appState.selectedDocumentIDs = [seqRef.documentID]
                        }
                    }
                }
            }
        }
        if selection.count > 1 {
            Button("Batch Rename...") {
                appState.selectedMediaIDs = selection
                appState.isShowingBatchRename = true
            }
        }
        if !selection.isEmpty {
            Divider()
            Button("Remove Selected from All XMLs", role: .destructive) {
                appState.selectedMediaIDs = selection
                appState.showRemoveMediaAlert = true
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("\(appState.filteredMedia.count) media items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.bar)
    }

    // MARK: - Helpers

    private func sequenceFPS(for media: MediaReference) -> Double? {
        if let firstSeqRef = media.referencingSequences.sorted(by: { $0.sequenceName < $1.sequenceName }).first {
            for doc in appState.documents where doc.id == firstSeqRef.documentID {
                if let seq = doc.sequences.first(where: { $0.name == firstSeqRef.sequenceName }) {
                    return seq.fps
                }
            }
        }
        return nil
    }

    private func iconName(for media: MediaReference) -> String {
        if media.hasAPrefix {
            return "film"
        } else if Self.audioExtensions.contains(media.fileExtension) {
            return "waveform"
        } else {
            return "doc"
        }
    }

    private func iconColor(for media: MediaReference) -> Color {
        if media.hasAPrefix {
            return .blue
        } else if Self.audioExtensions.contains(media.fileExtension) {
            return .green
        } else {
            return .secondary
        }
    }
}

// MARK: - Cell Views

private struct MediaReelCell: View {
    let media: MediaReference

    var body: some View {
        if let reel = media.reelName {
            Text(reel)
                .foregroundStyle(media.hasAPrefix ? .green : .primary)
        } else if media.hasAPrefix {
            Text("Missing")
                .foregroundStyle(.red)
        } else {
            Text("\u{2014}")
                .foregroundStyle(.tertiary)
        }
    }
}

private struct MediaFPSCell: View {
    let media: MediaReference
    let sequenceFPS: Double?

    var body: some View {
        if let fps = media.fps {
            Text(String(format: "%.2f", fps))
                .monospacedDigit()
                .foregroundStyle(fpsColor)
        } else {
            Text("\u{2014}")
                .foregroundStyle(.tertiary)
        }
    }

    private var fpsColor: Color {
        guard let mediaFPS = media.fps else { return .primary }
        if let seqFPS = sequenceFPS, abs(mediaFPS - seqFPS) > 0.01 {
            return .orange
        }
        return .primary
    }
}
