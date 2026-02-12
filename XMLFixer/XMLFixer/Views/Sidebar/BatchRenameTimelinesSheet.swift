import SwiftUI

struct BatchRenameTimelinesSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

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

    private var targetSequences: [(docName: String, seqName: String)] {
        let targetDocs = appState.selectedDocumentIDs.isEmpty
            ? appState.documents
            : appState.documents.filter { appState.selectedDocumentIDs.contains($0.id) }
        return targetDocs.flatMap { doc in
            doc.sequences.map { (docName: doc.filename, seqName: $0.name) }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Batch Rename Timelines")
                .font(.headline)

            Form {
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
            GroupBox("Preview (first \(min(targetSequences.count, 15)) of \(targetSequences.count))") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(targetSequences.prefix(15).enumerated()), id: \.offset) { _, item in
                            let newName = currentOperation.apply(to: item.seqName)
                            HStack {
                                Text(item.seqName)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                Text(newName)
                                    .lineLimit(1)
                                    .foregroundStyle(newName != item.seqName ? .primary : .tertiary)
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
                Text("\(targetSequences.count) timelines")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button("Apply") {
                    appState.batchRenameTimelines(
                        operation: currentOperation,
                        documentIDs: appState.selectedDocumentIDs
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 550)
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
