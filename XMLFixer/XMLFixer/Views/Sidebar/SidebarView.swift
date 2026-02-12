import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedDocumentIDs) {
            Section("Loaded XMLs (\(appState.documents.count))") {
                ForEach(appState.documents) { doc in
                    XMLFileRow(document: doc)
                        .tag(doc.id)
                        .contextMenu {
                            contextMenuItems(for: doc)
                        }
                }
            }

            if appState.hasNestedSequences {
                Section {
                    Button(role: .destructive) {
                        appState.showDenestAlert = true
                    } label: {
                        Label("Denest All Sequences", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onChange(of: appState.selectedDocumentIDs) { _, newIDs in
            // Auto-select first sequence of the most recently selected document
            guard let docID = newIDs.first,
                  let doc = appState.documents.first(where: { $0.id == docID }),
                  let firstSeq = doc.sequences.first
            else { return }
            appState.selectedSequenceID = firstSeq.id
            appState.refreshTimelineData()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("XML Fixer \(XMLFixerApp.buildVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.isShowingImportPanel = true
                } label: {
                    Label("Add XMLs", systemImage: "plus")
                }
            }
        }
        .alert("Denest All Sequences?", isPresented: $appState.showDenestAlert) {
            Button("Denest", role: .destructive) {
                appState.denestAllSequences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let preview = appState.denestPreview
            Text("Flatten \(preview.sequenceCount) nested sequences across \(preview.documentCount) XMLs?\n\nThis replaces nested sequence clips with their contained clips.")
        }
    }

    @ViewBuilder
    private func contextMenuItems(for doc: FCPXMLDocument) -> some View {
        let selectedCount = appState.selectedDocumentIDs.count

        if selectedCount > 1 {
            // Multiple documents selected — batch rename
            Button("Batch Rename \(selectedCount) Timelines...") {
                appState.isShowingBatchTimelineRename = true
            }
        } else {
            // Single document
            if doc.sequences.count == 1, let seq = doc.sequences.first {
                Button("Rename Timeline...") {
                    appState.sidebarEditingSequenceID = seq.id
                    appState.sidebarEditName = seq.name
                }
            } else {
                ForEach(doc.sequences) { seq in
                    Button("Rename \"\(seq.name)\"...") {
                        appState.sidebarEditingSequenceID = seq.id
                        appState.sidebarEditName = seq.name
                    }
                }
            }
            if doc.sequences.count > 1 {
                Button("Batch Rename All in \"\(doc.filename)\"...") {
                    appState.selectedDocumentIDs = [doc.id]
                    appState.isShowingBatchTimelineRename = true
                }
            }
        }

        Divider()

        if selectedCount > 1 {
            Button("Remove \(selectedCount) XMLs", role: .destructive) {
                for id in appState.selectedDocumentIDs {
                    appState.removeDocument(id)
                }
            }
        } else {
            Button("Remove", role: .destructive) {
                appState.removeDocument(doc.id)
            }
        }
    }
}
