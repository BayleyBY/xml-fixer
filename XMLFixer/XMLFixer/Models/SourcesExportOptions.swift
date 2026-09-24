import Foundation

struct SourcesExportOptions {
    var handles: Int = 24
    var mergeThreshold: Int = 96      // frames — ranges within this distance merge together
    var sequenceName: String = "Sources"
    var sequenceTimebase: Int = 24    // with ntsc = true → 23.976 fps
    var ntsc: Bool = true
    var includeAudio: Bool = false
    var replaceLoadedXMLs: Bool = false   // clear the loaded XMLs and open the exported one
    var outputDirectory: URL?
    var outputFilename: String = "Sources_Sequence.xml"
}
