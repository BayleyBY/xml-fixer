import SwiftUI
import AppKit

struct RelinkSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var conformDirectory: URL? = nil
    @State private var scannedFiles: [String: [ScannedFile]] = [:]
    @State private var matches: [RelinkMatch] = []
    @State private var isScanning = false
    @State private var strictMode = true
    @State private var minChars: Double = 8
    @State private var extensionFilter = ""
    @State private var scanTask: Task<Void, Never>? = nil

    // Computed stats
    private var matchedCount: Int { matches.filter { $0.status == .matched || ($0.status == .multipleFound && $0.userConfirmed) }.count }
    private var multipleCount: Int { matches.filter { $0.status == .multipleFound && !$0.userConfirmed }.count }
    private var unlinkedCount: Int { matches.filter { $0.status == .unlinked }.count }
    private var hasAnyMatch: Bool { matches.contains { $0.selectedCandidateIndex != nil } }

    // Max stem length for slider range
    private var maxStemLength: Int {
        let maxLen = appState.mediaReferences.map {
            ($0.filename as NSString).deletingPathExtension.count
        }.max() ?? 20
        return max(maxLen, 3)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            Text("Relink Media Paths")
                .font(.headline)

            // Conform location
            HStack {
                Text("Conform Location:")
                    .foregroundStyle(.secondary)
                if let dir = conformDirectory {
                    Text(dir.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(dir.path)
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Browse...") {
                    browseForFolder()
                }
            }

            // Matching options
            GroupBox("Matching Options") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Strict (exact filename match)", isOn: $strictMode)
                        .toggleStyle(.checkbox)
                        .onChange(of: strictMode) { runMatching() }

                    if !strictMode {
                        HStack {
                            Text("Min matching chars:")
                            Slider(value: $minChars, in: 3...Double(maxStemLength), step: 1)
                                .onChange(of: minChars) { runMatching() }
                            Text("\(Int(minChars))")
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                    }

                    HStack {
                        Text("Match extension:")
                        TextField("e.g. mxf", text: $extensionFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                            .onChange(of: extensionFilter) { triggerRescan() }
                        Text("(blank = any)")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
                .padding(4)
            }

            // Results list
            if isScanning {
                ProgressView("Scanning directory...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if matches.isEmpty && conformDirectory != nil {
                Text("No media to match. Load XML files first.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !matches.isEmpty {
                List {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        RelinkMatchRow(match: match) { candidateIndex in
                            // User picked a candidate from context menu
                            matches[index].selectedCandidateIndex = candidateIndex
                            matches[index].userConfirmed = true
                            matches[index].status = .matched
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            } else {
                Text("Select a conform location to begin scanning.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Summary bar
            if !matches.isEmpty {
                HStack(spacing: 16) {
                    Label("\(matchedCount) linked", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if multipleCount > 0 {
                        Label("\(multipleCount) need selection", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    if unlinkedCount > 0 {
                        Label("\(unlinkedCount) unlinked", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            // Action buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !matches.isEmpty {
                    Text("\(matches.count) media files")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
                Button("Apply Relink") {
                    appState.applyRelink(matches)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasAnyMatch)
            }
        }
        .padding()
        .frame(minWidth: 700, idealWidth: 700, maxWidth: .infinity,
               minHeight: 550, idealHeight: 550, maxHeight: .infinity)
        .resizableSheet(minSize: CGSize(width: 700, height: 550))
    }

    // MARK: - Actions

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder containing your raw/conform media"
        panel.prompt = "Select Folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            conformDirectory = url
            triggerRescan()
        }
    }

    private func triggerRescan() {
        guard let directory = conformDirectory else { return }

        scanTask?.cancel()
        scanTask = Task {
            isScanning = true
            let filter = extensionFilter.trimmingCharacters(in: .whitespaces)
            let files = await FileScanner.scan(
                directory: directory,
                extensionFilter: filter.isEmpty ? nil : filter
            )
            scannedFiles = files
            isScanning = false
            runMatching()
        }
    }

    private func runMatching() {
        guard !scannedFiles.isEmpty else {
            matches = []
            return
        }

        let mediaFilenames = appState.mediaReferences.map { (id: $0.id, filename: $0.filename) }

        // Preserve user confirmations
        let previousConfirmations: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: matches
                .filter { $0.userConfirmed }
                .compactMap { match in
                    guard let idx = match.selectedCandidateIndex else { return nil }
                    guard idx < match.candidates.count else { return nil }
                    return (match.mediaID, idx)
                }
        )

        var newMatches = RelinkEngine.match(
            mediaFilenames: mediaFilenames,
            against: scannedFiles,
            strictMode: strictMode,
            minChars: Int(minChars)
        )

        // Restore user confirmations where possible
        for i in newMatches.indices {
            if let prevIdx = previousConfirmations[newMatches[i].mediaID],
               prevIdx < newMatches[i].candidates.count {
                newMatches[i].selectedCandidateIndex = prevIdx
                newMatches[i].userConfirmed = true
                newMatches[i].status = .matched
            }
        }

        matches = newMatches
    }
}

// MARK: - Row View

struct RelinkMatchRow: View {
    let match: RelinkMatch
    let onSelectCandidate: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Media filename
            Text(match.mediaFilename)
                .font(.body)
                .frame(width: 180, alignment: .leading)
                .lineLimit(1)

            // Candidate picker or status
            if match.candidates.count > 1 {
                Menu {
                    ForEach(Array(match.candidates.enumerated()), id: \.element.id) { index, candidate in
                        Button {
                            onSelectCandidate(index)
                        } label: {
                            HStack {
                                if index == match.selectedCandidateIndex {
                                    Image(systemName: "checkmark")
                                }
                                Text("\(candidate.displayFilename) — \(candidate.displaySize)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedLabel)
                            .font(.caption)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(match.userConfirmed ? .green : .orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(match.userConfirmed ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let path = match.selectedPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(path)
            } else {
                Text("Unlinked")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectedLabel: String {
        if let idx = match.selectedCandidateIndex, idx < match.candidates.count {
            let c = match.candidates[idx]
            return "\(c.displayFilename) — \(c.displaySize)"
        }
        return "\(match.candidates.count) matches — pick one"
    }

    private var statusColor: Color {
        switch match.status {
        case .matched: return .green
        case .multipleFound: return match.userConfirmed ? .green : .orange
        case .unlinked: return .red
        }
    }
}
