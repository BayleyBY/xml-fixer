import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 16) {
            Text("Export Cleaned XMLs")
                .font(.headline)

            Form {
                LabeledContent("Output Folder") {
                    HStack {
                        Text(appState.exportOptions.outputDirectory?.path(percentEncoded: false) ?? "Not selected")
                            .lineLimit(1)
                            .foregroundStyle(
                                appState.exportOptions.outputDirectory == nil ? .secondary : .primary
                            )
                        Spacer()
                        Button("Choose...") {
                            showFolderPicker = true
                        }
                    }
                }

                TextField("Filename Suffix", text: $appState.exportOptions.filenameSuffix)
                    .help("Appended to each filename before .xml (e.g. '_clean')")

                Toggle("Repair Reel Metadata (A_ files)",
                       isOn: $appState.exportOptions.shouldRepairReelMetadata)
            }
            .formStyle(.grouped)
            .frame(width: 450)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export \(appState.documents.count) Files") {
                    appState.exportAll()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.exportOptions.outputDirectory == nil)
            }
        }
        .padding()
        .frame(width: 500)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                appState.exportOptions.outputDirectory = url
            }
        }
    }
}
