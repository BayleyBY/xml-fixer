import Foundation
import AppKit
import UniformTypeIdentifiers

struct CSVExporter {
    static func export(mediaReferences: [MediaReference]) -> String {
        var lines: [String] = []
        lines.append(["Filename", "Clips", "XMLs", "Reel", "TC In", "FPS", "Res", "Speed", "Path"].joined(separator: ","))
        for media in mediaReferences {
            let row = [
                escapeCSV(media.filename),
                "\(media.clipCount)",
                "\(media.referencingDocuments.count)",
                escapeCSV(media.reelName ?? ""),
                escapeCSV(media.timecodeString ?? ""),
                media.fps.map { String(format: "%.2f", $0) } ?? "",
                escapeCSV(media.resolution ?? ""),
                media.isTimewarped ? "TW" : "",
                escapeCSV(media.pathURL ?? "")
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func showSavePanelAndExport(csv: String, completion: ((Result<URL, Error>) -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "media_export.csv"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                completion?(.success(url))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
