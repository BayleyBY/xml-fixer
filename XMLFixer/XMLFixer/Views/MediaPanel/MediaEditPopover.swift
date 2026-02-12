import SwiftUI

struct MediaEditPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let media: MediaReference

    @State private var editedFilename: String = ""
    @State private var editedReel: String = ""
    @State private var editedPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Media")
                .font(.headline)

            Form {
                LabeledContent("Filename") {
                    TextField("Filename", text: $editedFilename)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Reel Name") {
                    TextField("Reel Name", text: $editedReel)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Path URL") {
                    TextField("Path", text: $editedPath)
                        .textFieldStyle(.roundedBorder)
                }

                Divider()

                // Read-only fields
                LabeledContent("Extension") {
                    Text(media.fileExtension.isEmpty ? "--" : ".\(media.fileExtension)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Clips") {
                    Text("\(media.clipCount)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("FPS") {
                    Text(media.fps.map { String(format: "%.2f", $0) } ?? "--")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Resolution") {
                    Text(media.resolution ?? "--")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Codec") {
                    Text(media.codec ?? "--")
                        .foregroundStyle(.secondary)
                }
                if media.isTimewarped {
                    LabeledContent("Speed") {
                        Text("Timewarped")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    applyChanges()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges)
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            editedFilename = media.filename
            editedReel = media.reelName ?? ""
            editedPath = media.pathURL ?? ""
        }
    }

    private var hasChanges: Bool {
        editedFilename != media.filename ||
        editedReel != (media.reelName ?? "") ||
        editedPath != (media.pathURL ?? "")
    }

    private func applyChanges() {
        if editedFilename != media.filename {
            appState.updateMediaFilename(mediaID: media.id, newFilename: editedFilename)
        }
        if editedReel != (media.reelName ?? "") {
            appState.updateMediaReelName(mediaID: media.id, newReel: editedReel)
        }
        if editedPath != (media.pathURL ?? "") {
            appState.updateMediaPath(mediaID: media.id, newPath: editedPath)
        }
    }
}
