import SwiftUI

struct BatchRenameSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var targetField: BatchField = .filename
    @State private var operationType: OperationType = .findReplace
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var appendText = ""
    @State private var prependText = ""
    @State private var setValue = ""
    @State private var useRegex = false

    enum OperationType: String, CaseIterable {
        case findReplace = "Find & Replace"
        case prepend = "Prepend"
        case append = "Append"
        case setValue = "Set Value"
    }

    var selectedMedia: [MediaReference] {
        appState.mediaReferences.filter { appState.selectedMediaIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Batch Rename")
                .font(.headline)

            Form {
                Picker("Target Field", selection: $targetField) {
                    ForEach(BatchField.allCases, id: \.self) { field in
                        Text(field.rawValue).tag(field)
                    }
                }

                Picker("Operation", selection: $operationType) {
                    ForEach(OperationType.allCases, id: \.self) { op in
                        Text(op.rawValue).tag(op)
                    }
                }

                switch operationType {
                case .findReplace:
                    TextField("Find", text: $findText)
                    TextField("Replace with", text: $replaceText)
                    Toggle("Use Regex", isOn: $useRegex)
                        .toggleStyle(.checkbox)
                case .prepend:
                    TextField("Prepend text", text: $prependText)
                case .append:
                    TextField("Append text", text: $appendText)
                case .setValue:
                    TextField("New value", text: $setValue)
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)

            // Preview
            GroupBox("Preview (first \(min(selectedMedia.count, 15)) of \(selectedMedia.count))") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(selectedMedia.prefix(15).enumerated()), id: \.offset) { _, media in
                            let oldValue = currentValue(for: media)
                            let newValue = currentOperation.apply(to: oldValue)
                            HStack {
                                Text(oldValue)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                Text(newValue)
                                    .lineLimit(1)
                                    .foregroundStyle(newValue != oldValue ? .primary : .tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 200)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(selectedMedia.count) items selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button("Apply") {
                    appState.batchRename(
                        field: targetField,
                        operation: currentOperation,
                        selectedIDs: appState.selectedMediaIDs
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 550)
    }

    private func currentValue(for media: MediaReference) -> String {
        switch targetField {
        case .filename: return media.filename
        case .reelName: return media.reelName ?? ""
        case .pathURL: return media.pathURL ?? ""
        }
    }

    private var currentOperation: BatchOperation {
        switch operationType {
        case .findReplace: return .findReplace(find: findText, replace: replaceText, useRegex: useRegex)
        case .prepend: return .prepend(prependText)
        case .append: return .append(appendText)
        case .setValue: return .setValue(setValue)
        }
    }
}
