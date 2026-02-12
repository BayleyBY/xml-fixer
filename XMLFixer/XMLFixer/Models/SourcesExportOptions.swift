import Foundation

struct SourcesExportOptions {
    var handles: Int = 10
    var mergeThreshold: Int = 0       // frames — ranges within this distance merge together
    var sequenceName: String = "Sources"
    var sequenceTimebase: Int = 25
    var ntsc: Bool = false
    var includeAudio: Bool = true
    var outputDirectory: URL?
    var outputFilename: String = "Sources_Sequence.xml"
}
