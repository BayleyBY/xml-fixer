import SwiftUI

struct XMLFileRow: View {
    let document: FCPXMLDocument
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(document.filename)
                    .font(.body)
                    .lineLimit(1)
                if document.isDirty {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .help("Modified")
                }
            }

            HStack(spacing: 8) {
                Label("\(document.sequences.count) seq", systemImage: "film")

                // Audio info from first sequence
                if let firstSeq = document.sequences.first {
                    Label("\(firstSeq.audioTrackCount) audio", systemImage: "speaker.wave.2")
                    if let channelInfo = firstSeq.audioChannelInfo {
                        Text("(\(channelInfo))")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(document.sequences) { seq in
                HStack(spacing: 4) {
                    if appState.sidebarEditingSequenceID == seq.id {
                        TextField("Sequence Name", text: $appState.sidebarEditName)
                            .font(.caption)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                appState.renameSequence(sequenceID: seq.id, to: appState.sidebarEditName)
                                appState.sidebarEditingSequenceID = nil
                            }
                            .onExitCommand {
                                appState.sidebarEditingSequenceID = nil
                            }
                    } else {
                        Button {
                            appState.selectedSequenceID = seq.id
                            appState.refreshTimelineData()
                        } label: {
                            Text(seq.name)
                                .font(.caption)
                                .foregroundColor(
                                    appState.selectedSequenceID == seq.id
                                        ? Color.accentColor
                                        : Color.secondary
                                )
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Rename...") {
                                appState.sidebarEditName = seq.name
                                appState.sidebarEditingSequenceID = seq.id
                            }

                            Divider()

                            Button("Edit Start Timecode...") {
                                appState.timecodeEditTargetSequenceID = seq.id
                                appState.isShowingTimecodeEditSheet = true
                            }

                            if appState.referenceMatches[seq.id] != nil {
                                Button("Open Reference Player") {
                                    appState.openVideoPlayer(for: seq.id)
                                }
                                Button("Match TC to Reference") {
                                    appState.matchTimecodeToReference(sequenceID: seq.id)
                                }
                            }
                        }
                    }

                    if let fps = seq.fps {
                        Text(String(format: "%.1ffps", fps))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                    if let tc = seq.startTimecodeString {
                        Text(tc)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    if seq.hasNestedSequences {
                        Label("\(seq.nestedSequenceCount) nested", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
