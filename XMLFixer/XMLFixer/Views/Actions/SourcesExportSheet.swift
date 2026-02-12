import SwiftUI
import UniformTypeIdentifiers

struct SourcesExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @State private var rawSummaries: [MediaUsageSummary] = []

    private var previewSummaries: [MediaUsageSummary] {
        var result = rawSummaries
        SourcesSequenceBuilder.applyHandlesAndMerge(
            summaries: &result,
            handles: appState.sourcesExportOptions.handles,
            mergeThreshold: appState.sourcesExportOptions.mergeThreshold
        )
        return result
    }

    private var totalMergedRanges: Int {
        previewSummaries.reduce(0) { $0 + $1.mergedRanges.count }
    }

    private var totalMergedDuration: Int {
        previewSummaries.reduce(0) { $0 + $1.mergedRanges.reduce(0) { $0 + $1.length } }
    }

    private var timewarped: Int {
        rawSummaries.filter { $0.rawRanges.contains { $0.speedFactor != 1.0 } }.count
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            // Header
            Text("Export Sources Sequence")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            HSplitView {
                // Left: controls
                VStack(spacing: 0) {
                    Form {
                        LabeledContent("Output Folder") {
                            HStack {
                                Text(appState.sourcesExportOptions.outputDirectory?.path(percentEncoded: false) ?? "Not selected")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(
                                        appState.sourcesExportOptions.outputDirectory == nil ? .secondary : .primary
                                    )
                                Spacer()
                                Button("Choose...") {
                                    showFolderPicker = true
                                }
                            }
                        }

                        TextField("Sequence Name", text: $appState.sourcesExportOptions.sequenceName)

                        TextField("Output Filename", text: $appState.sourcesExportOptions.outputFilename)

                        Section("Range Controls") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Handles")
                                    Spacer()
                                    Text("\(appState.sourcesExportOptions.handles) frames")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(appState.sourcesExportOptions.handles) },
                                        set: { appState.sourcesExportOptions.handles = Int($0) }
                                    ),
                                    in: 0...200,
                                    step: 1
                                )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Merge Threshold")
                                    Spacer()
                                    Text("\(appState.sourcesExportOptions.mergeThreshold) frames")
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(appState.sourcesExportOptions.mergeThreshold) },
                                        set: { appState.sourcesExportOptions.mergeThreshold = Int($0) }
                                    ),
                                    in: 0...500,
                                    step: 1
                                )
                                Text("Merge clips within this distance even if they don't overlap")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Section("Output") {
                            Picker("Sequence Timebase", selection: $appState.sourcesExportOptions.sequenceTimebase) {
                                Text("23.976 fps").tag(24)
                                Text("25 fps").tag(25)
                                Text("29.97 fps").tag(30)
                            }

                            Toggle("Include Audio Tracks", isOn: $appState.sourcesExportOptions.includeAudio)
                                .toggleStyle(.checkbox)
                        }
                    }
                    .formStyle(.grouped)

                    // Summary stats
                    VStack(spacing: 2) {
                        HStack {
                            Text("\(rawSummaries.count) files")
                            Text("·")
                            Text("\(totalMergedRanges) clips")
                            if timewarped > 0 {
                                Text("·")
                                Text("\(timewarped) timewarped")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Text("Total: \(formatFrames(totalMergedDuration, timebase: appState.sourcesExportOptions.sequenceTimebase))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .frame(minWidth: 300, idealWidth: 340)

                // Right: live timeline preview
                VStack(spacing: 0) {
                    HStack {
                        Text("Timeline Preview")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(previewSummaries.filter { !$0.mergedRanges.isEmpty }.count) sources")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.bar)

                    Divider()

                    SourcesTimelinePreview(summaries: previewSummaries)
                }
                .frame(minWidth: 300)
            }

            Divider()

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export Sources XML") {
                    appState.exportSourcesSequence()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.sourcesExportOptions.outputDirectory == nil)
            }
            .padding(16)
        }
        .frame(width: 900, height: 560)
        .onAppear {
            rawSummaries = SourcesSequenceBuilder.collectUsages(from: appState.documents)
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                appState.sourcesExportOptions.outputDirectory = url
            }
        }
    }

    private func formatFrames(_ frames: Int, timebase: Int) -> String {
        let tb = max(1, timebase)
        let totalSeconds = frames / tb
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let remainFrames = frames % tb
        return String(format: "%02d:%02d:%02d", mins, secs, remainFrames)
    }
}

// MARK: - Timeline Preview

struct SourcesTimelinePreview: View {
    let summaries: [MediaUsageSummary]

    private let trackHeight: CGFloat = 20
    private let labelWidth: CGFloat = 120

    private var activeSummaries: [MediaUsageSummary] {
        summaries.filter { !$0.mergedRanges.isEmpty }
    }

    // Color palette for sources
    private static let colors: [Color] = [
        .blue, .green, .orange, .purple, .cyan, .pink, .yellow, .mint, .indigo, .teal
    ]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(activeSummaries.enumerated()), id: \.element.id) { idx, summary in
                    let color = Self.colors[idx % Self.colors.count]

                    HStack(spacing: 0) {
                        // Filename label
                        Text(summary.filename)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: labelWidth, alignment: .trailing)
                            .padding(.trailing, 4)

                        // Range blocks
                        ZStack(alignment: .leading) {
                            // Track background
                            Rectangle()
                                .fill(Color.gray.opacity(idx % 2 == 0 ? 0.1 : 0.07))
                                .frame(height: trackHeight)

                            // Source duration indicator (full width, very subtle)
                            GeometryReader { geo in
                                let totalWidth = geo.size.width

                                // Merged range blocks
                                ForEach(Array(summary.mergedRanges.enumerated()), id: \.offset) { _, range in
                                    let maxDur = max(1, Double(summary.sourceDuration))
                                    let x = totalWidth * Double(range.inPoint) / maxDur
                                    let w = max(3, totalWidth * Double(range.length) / maxDur)

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(color.opacity(0.7))
                                        .overlay(alignment: .leading) {
                                            if w > 40 {
                                                Text(formatRange(range, timebase: summary.timebase))
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundStyle(.white.opacity(0.8))
                                                    .lineLimit(1)
                                                    .padding(.leading, 3)
                                            }
                                        }
                                        .frame(width: w, height: trackHeight - 4)
                                        .offset(x: x, y: 2)

                                    // Speed indicator
                                    if range.speedFactor != 1.0 {
                                        let speedLabel = String(format: "%.0f%%", range.speedFactor * 100)
                                        Text(speedLabel)
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(.orange)
                                            .offset(x: x + w - 20, y: -1)
                                    }
                                }
                            }
                            .frame(height: trackHeight)
                        }
                        .frame(width: 400, height: trackHeight)
                    }
                    .frame(height: trackHeight)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color.gray.opacity(0.08))
    }

    private func formatRange(_ range: SourceRange, timebase: Int) -> String {
        let tb = max(1, timebase)
        let inSec = range.inPoint / tb
        let outSec = range.outPoint / tb
        return String(format: "%d:%02d–%d:%02d", inSec / 60, inSec % 60, outSec / 60, outSec % 60)
    }
}
