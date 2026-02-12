import Foundation

struct ExportService {

    struct ExportResult {
        let outputURL: URL
        let repairedReels: Int
        let success: Bool
        let error: Error?
    }

    /// Export a single document to the output directory with the configured options.
    static func export(
        document: FCPXMLDocument,
        options: ExportOptions
    ) throws -> ExportResult {
        guard let outputDir = options.outputDirectory else {
            throw ExportError.noOutputDirectory
        }

        // Build output filename: original_name + suffix + .xml
        let baseName = document.sourceURL.deletingPathExtension().lastPathComponent
        let outputName = baseName + options.filenameSuffix + ".xml"
        let outputURL = outputDir.appendingPathComponent(outputName)

        // Repair reel metadata if enabled
        let repairedCount = options.shouldRepairReelMetadata
            ? ReelMetadataRepairer.repairReelMetadata(in: document.xmlDocument)
            : 0

        // Serialize preserving original formatting (DOM was parsed with .nodePreserveAll)
        let xmlData = document.xmlDocument.xmlData(options: [])
        try xmlData.write(to: outputURL)

        return ExportResult(
            outputURL: outputURL,
            repairedReels: repairedCount,
            success: true,
            error: nil
        )
    }

    /// Batch export all documents.
    static func exportAll(
        documents: [FCPXMLDocument],
        options: ExportOptions
    ) -> [ExportResult] {
        documents.map { doc in
            do {
                return try export(document: doc, options: options)
            } catch {
                return ExportResult(
                    outputURL: doc.sourceURL,
                    repairedReels: 0,
                    success: false,
                    error: error
                )
            }
        }
    }

    enum ExportError: LocalizedError {
        case noOutputDirectory

        var errorDescription: String? {
            switch self {
            case .noOutputDirectory:
                return "No output directory selected."
            }
        }
    }
}
