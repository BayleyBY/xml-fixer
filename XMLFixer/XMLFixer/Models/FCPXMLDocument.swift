import Foundation
import SwiftUI

/// Wraps a single loaded FCP XML (xmeml) file.
/// Owns the live XMLDocument for in-place mutation.
@Observable
class FCPXMLDocument: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var displayName: String
    let xmlDocument: XMLDocument
    var sequences: [SequenceInfo]
    var isDirty: Bool

    var filename: String { sourceURL.lastPathComponent }
    var filenameWithoutExtension: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    init(id: UUID = UUID(), sourceURL: URL, displayName: String, xmlDocument: XMLDocument, sequences: [SequenceInfo], isDirty: Bool = false) {
        self.id = id
        self.sourceURL = sourceURL
        self.displayName = displayName
        self.xmlDocument = xmlDocument
        self.sequences = sequences
        self.isDirty = isDirty
    }

    static func == (lhs: FCPXMLDocument, rhs: FCPXMLDocument) -> Bool {
        lhs.id == rhs.id
    }
}
