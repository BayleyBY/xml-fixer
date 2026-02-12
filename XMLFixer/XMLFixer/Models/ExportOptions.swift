import Foundation

/// Configuration for exporting cleaned XML files.
struct ExportOptions {
    var outputDirectory: URL?
    var filenameSuffix: String = "_clean"
    var shouldRepairReelMetadata: Bool = true
}
