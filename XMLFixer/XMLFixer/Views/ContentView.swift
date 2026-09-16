import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.hasDocuments {
                VSplitView {
                    // Top area: media list + embedded player (NLE-style)
                    HSplitView {
                        MediaListView()

                        if appState.isPlayerEmbedded {
                            VideoPlayerContent(isEmbedded: true)
                                .frame(minWidth: 200, idealWidth: 360)
                        }
                    }

                    // Bottom: timeline (full width)
                    TimelinePanel()
                }
            } else {
                DropZoneView()
            }
        }
        .overlay {
            if appState.isProcessing {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                ProgressView("Processing...")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            }
        }
        .toolbar {
            ToolbarActions()
        }
        .sheet(isPresented: $appState.isShowingExportSheet) {
            ExportSheet()
        }
        .sheet(isPresented: $appState.isShowingSourcesExportSheet) {
            SourcesExportSheet()
        }
        .sheet(isPresented: $appState.isShowingScaleCalculator) {
            ScaleCalculatorSheet()
        }
        .sheet(isPresented: $appState.isShowingRelinkSheet) {
            RelinkSheet()
        }
        .sheet(isPresented: $appState.isShowingCollectSheet) {
            CollectMediaSheet()
        }
        .sheet(isPresented: $appState.isShowingTrimMediaSheet) {
            TrimMediaSheet()
        }
        .sheet(isPresented: $appState.isShowingBatchTimelineRename) {
            BatchRenameTimelinesSheet()
        }
        .sheet(isPresented: $appState.isShowingReferenceMatchSheet) {
            ReferenceMatchSheet()
        }
        .sheet(isPresented: $appState.isShowingTimecodeEditSheet) {
            TimecodeEditSheet()
        }
        .fileImporter(
            isPresented: $appState.isShowingImportPanel,
            allowedContentTypes: [.xml, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                appState.importFiles(urls: urls)
            case .failure(let error):
                appState.statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
        .onOpenURL { url in
            appState.importFiles(urls: [url])
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            appState.importFiles(urls: [url])
                        }
                    }
                }
            }
            return true
        }
        .onChange(of: appState.selectedSequenceID) { _, _ in
            appState.autoLoadReferencePlayer()
        }
    }
}
