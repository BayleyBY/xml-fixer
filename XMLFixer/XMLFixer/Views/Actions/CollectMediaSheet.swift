import SwiftUI
import AppKit

struct CollectMediaSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var sourceAccessURL: URL? = nil
    @State private var destinationURL: URL? = nil
    @State private var keepPaths = true
    @State private var stripLevels: Double = 0
    @State private var isCopying = false
    @State private var copyProgress: Double = 0
    @State private var copiedCount = 0
    @State private var errorMessages: [String] = []

    /// Media that have a pathURL pointing to an existing file on disk.
    private var linkedMedia: [MediaReference] {
        withSourceAccess {
            appState.mediaReferences.filter { media in
                guard let pathStr = media.pathURL else { return false }
                let path: String
                if pathStr.hasPrefix("file://") {
                    path = URL(string: pathStr)?.path ?? pathStr
                } else {
                    path = pathStr
                }
                return FileManager.default.fileExists(atPath: path)
            }
        }
    }

    /// Total file size of all linked media in bytes.
    private var totalFileSize: Int64 {
        withSourceAccess {
            linkedMedia.reduce(into: Int64(0)) { total, media in
                guard let path = resolvedPath(for: media) else { return }
                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
                total += size
            }
        }
    }

    /// Max path depth across all linked media (for slider range).
    private var maxPathDepth: Int {
        withSourceAccess {
            let depths = linkedMedia.compactMap { media -> Int? in
                guard let resolved = resolvedPath(for: media) else { return nil }
                // Count directory components (exclude filename itself)
                return URL(fileURLWithPath: resolved).pathComponents.dropFirst().dropLast().count
            }
            return depths.max() ?? 1
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Collect Linked Media")
                .font(.headline)

            // Source access
            HStack {
                Text("Source folder:")
                    .foregroundStyle(.secondary)
                if let source = sourceAccessURL {
                    Text(source.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(source.path)
                } else {
                    Text("Use current file access")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Grant Access...") { browseForSourceAccess() }
            }

            // Destination
            HStack {
                Text("Copy to:")
                    .foregroundStyle(.secondary)
                if let dest = destinationURL {
                    Text(dest.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(dest.path)
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Browse...") { browseForDestination() }
            }

            // Path options
            GroupBox("Path Options") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keep folder structure", isOn: $keepPaths)
                        .toggleStyle(.checkbox)

                    if keepPaths {
                        HStack {
                            Text("Strip path levels:")
                            Slider(
                                value: $stripLevels,
                                in: 0...Double(max(maxPathDepth, 1)),
                                step: 1
                            )
                            Text("\(Int(stripLevels))")
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                    }
                }
                .padding(4)
            }

            // Live preview
            GroupBox("Preview (first \(min(linkedMedia.count, 10)) of \(linkedMedia.count) files)") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if linkedMedia.isEmpty {
                            Text("No linked media found. Relink media paths first.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(Array(linkedMedia.prefix(10).enumerated()), id: \.element.id) { _, media in
                                let dest = previewDestination(for: media)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(media.filename)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                    Text(dest)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
            }

            // Progress
            if isCopying {
                VStack(spacing: 4) {
                    ProgressView(value: copyProgress)
                    Text("Copying \(copiedCount) of \(linkedMedia.count) files...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Errors
            if !errorMessages.isEmpty {
                GroupBox {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(errorMessages.prefix(5).enumerated()), id: \.offset) { _, msg in
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                            if errorMessages.count > 5 {
                                Text("...and \(errorMessages.count - 5) more errors")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(4)
                    }
                    .frame(height: 60)
                }
            }

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(linkedMedia.count) linked files · \(formattedSize(totalFileSize))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button("Copy Files") { startCopy() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(destinationURL == nil || linkedMedia.isEmpty || isCopying)
            }
        }
        .padding()
        .frame(minWidth: 650, idealWidth: 650, maxWidth: .infinity,
               minHeight: 520, idealHeight: 520, maxHeight: .infinity)
        .resizableSheet(minSize: CGSize(width: 650, height: 520))
    }

    // MARK: - Helpers

    private func withSourceAccess<T>(_ work: () -> T) -> T {
        let url = sourceAccessURL
        let accessing = url?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessing {
                url?.stopAccessingSecurityScopedResource()
            }
        }
        return work()
    }

    private func resolvedPath(for media: MediaReference) -> String? {
        guard let pathStr = media.pathURL else { return nil }
        if pathStr.hasPrefix("file://") {
            return URL(string: pathStr)?.path
        }
        return pathStr
    }

    private func destinationPath(for media: MediaReference, destRoot: URL) -> URL {
        guard let sourcePath = resolvedPath(for: media) else {
            return destRoot.appendingPathComponent(media.filename)
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)

        if !keepPaths {
            // Flat — use the actual filename from the source path (preserves extension)
            return destRoot.appendingPathComponent(sourceURL.lastPathComponent)
        }

        // Keep paths with stripping
        // pathComponents: ["/", "Volumes", "Raw", "Project", "Day1", "file.mov"]
        var components = sourceURL.pathComponents
        // Drop the leading "/" and the filename
        if components.first == "/" { components.removeFirst() }
        let filename = components.removeLast()

        // Strip N levels from the front
        let strip = min(Int(stripLevels), components.count)
        let kept = Array(components.dropFirst(strip))

        var result = destRoot
        for comp in kept {
            result = result.appendingPathComponent(comp)
        }
        result = result.appendingPathComponent(filename)
        return result
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func previewDestination(for media: MediaReference) -> String {
        let destRoot = destinationURL ?? URL(fileURLWithPath: "/target/directory")
        return destinationPath(for: media, destRoot: destRoot).path
    }

    // MARK: - Actions

    private func browseForSourceAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder that contains the linked source media"
        panel.prompt = "Grant Access"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            sourceAccessURL = url
        }
    }

    private func browseForDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Select destination folder for collected media"
        panel.prompt = "Select Folder"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            destinationURL = url
        }
    }

    private func startCopy() {
        guard let destRoot = destinationURL else { return }
        let media = linkedMedia
        isCopying = true
        copyProgress = 0
        copiedCount = 0
        errorMessages = []

        let sourceRoot = sourceAccessURL
        let sourceAccessing = sourceRoot?.startAccessingSecurityScopedResource() ?? false
        let destinationAccessing = destRoot.startAccessingSecurityScopedResource()

        let totalCount = media.count
        Task.detached(priority: .userInitiated) {
            defer {
                if sourceAccessing {
                    sourceRoot?.stopAccessingSecurityScopedResource()
                }
                if destinationAccessing {
                    destRoot.stopAccessingSecurityScopedResource()
                }
            }

            let fm = FileManager.default
            var errors: [String] = []
            var copied = 0

            var processed = 0
            for item in media {
                defer {
                    processed += 1
                    let currentCopied = copied
                    let progress = Double(processed) / Double(totalCount)
                    Task { @MainActor in
                        copiedCount = currentCopied
                        copyProgress = progress
                    }
                }

                guard let sourcePath = await resolvedPath(for: item) else { continue }
                let sourceURL = URL(fileURLWithPath: sourcePath)
                let destURL = await destinationPath(for: item, destRoot: destRoot)

                // Create intermediate directories
                let destDir = destURL.deletingLastPathComponent()
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                } catch {
                    errors.append("\(item.filename): mkdir failed — \(error.localizedDescription)")
                    continue
                }

                // Copy file (skip if already exists)
                if !fm.fileExists(atPath: destURL.path) {
                    do {
                        try fm.copyItem(at: sourceURL, to: destURL)
                        copied += 1
                    } catch {
                        errors.append("\(item.filename): \(error.localizedDescription)")
                    }
                } else {
                    copied += 1
                }
            }

            await MainActor.run {
                isCopying = false
                copyProgress = 1.0
                copiedCount = copied
                errorMessages = errors
                if errors.isEmpty {
                    appState.statusMessage = "Collected \(copied) files to \(destRoot.lastPathComponent)"
                } else {
                    appState.statusMessage = "Collected \(copied) files with \(errors.count) errors"
                }
            }
        }
    }
}
