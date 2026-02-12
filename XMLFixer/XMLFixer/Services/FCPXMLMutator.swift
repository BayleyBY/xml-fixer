import Foundation

struct FCPXMLMutator {

    // MARK: - Remove All Audio Tracks

    /// Removes all <track> children from every <audio> section in every sequence.
    /// Returns the number of tracks removed.
    @discardableResult
    static func removeAllAudioTracks(in document: FCPXMLDocument) -> Int {
        guard let root = document.xmlDocument.rootElement() else { return 0 }
        guard let audioTracks = try? root.nodes(forXPath: "//sequence/media/audio/track") else { return 0 }

        let count = audioTracks.count
        for trackNode in audioTracks {
            trackNode.detach()
        }
        if count > 0 { document.isDirty = true }
        return count
    }

    // MARK: - Remove Clipitems by Filename

    /// Removes all clipitems referencing any of the given filenames from ALL sequences.
    /// After removal, prunes empty tracks. Returns number of clipitems removed.
    @discardableResult
    static func removeClipitems(
        matching filenamesToRemove: Set<String>,
        in document: FCPXMLDocument,
        fileMap: [String: String]
    ) -> Int {
        guard let root = document.xmlDocument.rootElement() else { return 0 }
        var removedCount = 0

        // Process both video and audio clipitems
        let xpaths = [
            "//sequence/media/video/track/clipitem",
            "//sequence/media/audio/track/clipitem"
        ]

        for xpath in xpaths {
            guard let clipNodes = try? root.nodes(forXPath: xpath) else { continue }

            for clipNode in clipNodes {
                guard let clipElem = clipNode as? XMLElement else { continue }

                if let filename = resolveClipFilename(clipElem, fileMap: fileMap),
                   filenamesToRemove.contains(filename) {
                    let parentTrack = clipElem.parent as? XMLElement
                    clipElem.detach()
                    removedCount += 1

                    // If parent track is now empty, remove it too
                    if let track = parentTrack {
                        let remainingClips = (try? track.nodes(forXPath: "clipitem"))?.count ?? 0
                        if remainingClips == 0 {
                            track.detach()
                        }
                    }
                }
            }
        }

        if removedCount > 0 { document.isDirty = true }
        return removedCount
    }

    // MARK: - Rename Sequences

    /// Sets <sequence><name> to the given new name for all sequences in the document.
    /// Returns the number of sequences renamed.
    @discardableResult
    static func renameSequences(in document: FCPXMLDocument, to newName: String) -> Int {
        guard let root = document.xmlDocument.rootElement() else { return 0 }
        guard let sequenceNames = try? root.nodes(forXPath: "//sequence/name") else { return 0 }

        var count = 0
        for nameNode in sequenceNames {
            nameNode.stringValue = newName
            count += 1
        }
        if count > 0 { document.isDirty = true }
        return count
    }

    // MARK: - Rename Single Sequence

    /// Renames a single sequence element identified by its XML @id attribute.
    @discardableResult
    static func renameSequence(in document: FCPXMLDocument, sequenceElementID: String, to newName: String) -> Bool {
        guard let root = document.xmlDocument.rootElement() else { return false }
        let xpath = "//sequence[@id='\(sequenceElementID)']"
        guard let seqNodes = try? root.nodes(forXPath: xpath),
              let seqElem = seqNodes.first as? XMLElement else { return false }
        if let nameNode = (try? seqElem.nodes(forXPath: "name"))?.first {
            nameNode.stringValue = newName
        } else {
            seqElem.insertChild(XMLElement(name: "name", stringValue: newName), at: 0)
        }
        document.isDirty = true
        return true
    }

    // MARK: - Build File Map

    /// Builds the file@id -> filename dictionary.
    /// Equivalent to Python script's file_map (lines 38-43).
    static func buildFileMap(from xmlDocument: XMLDocument) -> [String: String] {
        guard let root = xmlDocument.rootElement() else { return [:] }
        guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { return [:] }

        var map: [String: String] = [:]
        for node in fileNodes {
            guard let elem = node as? XMLElement,
                  let fileID = elem.attributeValue(forName: "id"),
                  let nameText = elem.singleStringValue(forXPath: "name")
            else { continue }
            map[fileID] = nameText
        }
        return map
    }

    // MARK: - Count affected items (for confirmation previews)

    /// Counts how many clipitems would be removed across all documents.
    /// Returns (totalClips, affectedDocumentCount).
    static func countClipitemsToRemove(
        matching filenamesToRemove: Set<String>,
        in documents: [FCPXMLDocument]
    ) -> (clipCount: Int, documentCount: Int) {
        var totalClips = 0
        var affectedDocs = 0

        for doc in documents {
            let fileMap = buildFileMap(from: doc.xmlDocument)
            guard let root = doc.xmlDocument.rootElement() else { continue }

            var docClips = 0
            let xpaths = [
                "//sequence/media/video/track/clipitem",
                "//sequence/media/audio/track/clipitem"
            ]

            for xpath in xpaths {
                guard let clipNodes = try? root.nodes(forXPath: xpath) else { continue }
                for clipNode in clipNodes {
                    guard let clipElem = clipNode as? XMLElement else { continue }
                    if let filename = resolveClipFilename(clipElem, fileMap: fileMap),
                       filenamesToRemove.contains(filename) {
                        docClips += 1
                    }
                }
            }

            if docClips > 0 {
                totalClips += docClips
                affectedDocs += 1
            }
        }

        return (totalClips, affectedDocs)
    }

    // MARK: - Update Filename

    /// Updates the <name> of all <file> elements matching oldName across all documents.
    /// Also updates <name> on parent clipitems. Returns count of updated file elements.
    @discardableResult
    static func updateFilename(from oldName: String, to newName: String, in documents: [FCPXMLDocument]) -> Int {
        var totalUpdated = 0
        for doc in documents {
            guard let root = doc.xmlDocument.rootElement() else { continue }
            guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { continue }

            var docUpdated = 0
            for node in fileNodes {
                guard let fileElem = node as? XMLElement else { continue }
                guard let nameNode = (try? fileElem.nodes(forXPath: "name"))?.first,
                      nameNode.stringValue == oldName
                else { continue }

                nameNode.stringValue = newName
                docUpdated += 1
            }

            // Also update clipitem <name> elements that match
            if let clipNames = try? root.nodes(forXPath: "//clipitem/name") {
                for nameNode in clipNames {
                    if nameNode.stringValue == oldName {
                        nameNode.stringValue = newName
                    }
                }
            }

            if docUpdated > 0 {
                doc.isDirty = true
                totalUpdated += docUpdated
            }
        }
        return totalUpdated
    }

    // MARK: - Update Reel Name

    /// Updates or creates <timecode><reel><name> for all <file> elements matching the given filename.
    @discardableResult
    static func updateReelName(for filename: String, to newReel: String, in documents: [FCPXMLDocument]) -> Int {
        var totalUpdated = 0
        for doc in documents {
            guard let root = doc.xmlDocument.rootElement() else { continue }
            guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { continue }

            var docUpdated = 0
            for node in fileNodes {
                guard let fileElem = node as? XMLElement else { continue }
                let nameText = fileElem.singleStringValue(forXPath: "name") ?? ""
                guard nameText == filename else { continue }

                // Find or create timecode element
                var timecodeElem = (try? fileElem.nodes(forXPath: "timecode"))?.first as? XMLElement
                if timecodeElem == nil {
                    timecodeElem = XMLElement(name: "timecode")
                    fileElem.addChild(timecodeElem!)
                }

                // Find or create reel element
                var reelElem = (try? timecodeElem!.nodes(forXPath: "reel"))?.first as? XMLElement
                if reelElem == nil {
                    reelElem = XMLElement(name: "reel")
                    timecodeElem!.addChild(reelElem!)
                }

                // Find or create name element inside reel
                if let reelNameNode = (try? reelElem!.nodes(forXPath: "name"))?.first {
                    reelNameNode.stringValue = newReel
                } else {
                    reelElem!.addChild(XMLElement(name: "name", stringValue: newReel))
                }

                docUpdated += 1
            }

            if docUpdated > 0 {
                doc.isDirty = true
                totalUpdated += docUpdated
            }
        }
        return totalUpdated
    }

    // MARK: - Update Path URL

    /// Updates <pathurl> for all <file> elements matching the given filename.
    @discardableResult
    static func updatePathURL(for filename: String, to newPath: String, in documents: [FCPXMLDocument]) -> Int {
        var totalUpdated = 0
        for doc in documents {
            guard let root = doc.xmlDocument.rootElement() else { continue }
            guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { continue }

            var docUpdated = 0
            for node in fileNodes {
                guard let fileElem = node as? XMLElement else { continue }
                let nameText = fileElem.singleStringValue(forXPath: "name") ?? ""
                guard nameText == filename else { continue }

                if let pathNode = (try? fileElem.nodes(forXPath: "pathurl"))?.first {
                    pathNode.stringValue = newPath
                } else {
                    fileElem.addChild(XMLElement(name: "pathurl", stringValue: newPath))
                }
                docUpdated += 1
            }

            if docUpdated > 0 {
                doc.isDirty = true
                totalUpdated += docUpdated
            }
        }
        return totalUpdated
    }

    // MARK: - Denest Sequences

    /// Flattens nested sequences by replacing clipitems that contain <sequence> children
    /// with the actual clipitems from inside those nested sequences.
    /// Returns the number of nested sequences denested.
    @discardableResult
    static func denestSequences(in document: FCPXMLDocument) -> Int {
        guard let root = document.xmlDocument.rootElement() else { return 0 }

        // Find all clipitems in video tracks that contain a nested sequence
        guard let nestedNodes = try? root.nodes(forXPath: "//sequence/media/video/track/clipitem[sequence]") else { return 0 }

        var denestCount = 0

        for node in nestedNodes {
            guard let clipElem = node as? XMLElement,
                  let parentTrack = clipElem.parent as? XMLElement,
                  let innerSeq = (try? clipElem.nodes(forXPath: "sequence"))?.first as? XMLElement
            else { continue }

            let parentStart = clipElem.singleIntValue(forXPath: "start") ?? 0
            let parentIn = clipElem.singleIntValue(forXPath: "in") ?? 0
            let offset = parentStart - parentIn

            // Get all clipitems from the inner sequence's video tracks
            let innerClips = (try? innerSeq.nodes(forXPath: "media/video/track/clipitem")) ?? []

            // Find the index of the nested clipitem in the parent track
            let clipIndex = parentTrack.children?.firstIndex(where: { ($0 as? XMLElement) === clipElem }) ?? 0

            // Insert inner clips, adjusting timeline positions
            var insertIndex = clipIndex
            for innerClip in innerClips {
                guard let innerClipElem = innerClip as? XMLElement else { continue }
                let copy = innerClipElem.copy() as! XMLElement

                // Adjust start/end by offset
                if let startNode = (try? copy.nodes(forXPath: "start"))?.first,
                   let startVal = startNode.stringValue.flatMap({ Int($0) }) {
                    startNode.stringValue = String(startVal + offset)
                }
                if let endNode = (try? copy.nodes(forXPath: "end"))?.first,
                   let endVal = endNode.stringValue.flatMap({ Int($0) }) {
                    endNode.stringValue = String(endVal + offset)
                }

                parentTrack.insertChild(copy, at: insertIndex)
                insertIndex += 1
            }

            // Remove the original nested-sequence clipitem
            clipElem.detach()
            denestCount += 1
        }

        if denestCount > 0 { document.isDirty = true }
        return denestCount
    }

    // MARK: - Effect Mutations

    /// Updates a parameter value on a specific effect of a clipitem.
    /// Finds the clipitem by its @id attribute, then the filter by index, then the parameter by parameterid.
    @discardableResult
    static func updateEffectParameter(
        clipElementID: String,
        filterIndex: Int,
        parameterID: String,
        newValue: String,
        in document: FCPXMLDocument
    ) -> Bool {
        guard let root = document.xmlDocument.rootElement() else { return false }
        let xpath = "//clipitem[@id='\(clipElementID)']"
        guard let clipNodes = try? root.nodes(forXPath: xpath),
              let clipElem = clipNodes.first as? XMLElement
        else { return false }

        guard let filterNodes = try? clipElem.nodes(forXPath: "filter"),
              filterIndex < filterNodes.count,
              let filterElem = filterNodes[filterIndex] as? XMLElement,
              let effectElem = (try? filterElem.nodes(forXPath: "effect"))?.first as? XMLElement
        else { return false }

        guard let paramNodes = try? effectElem.nodes(forXPath: "parameter") else { return false }

        for paramNode in paramNodes {
            guard let paramElem = paramNode as? XMLElement else { continue }
            let pid = paramElem.singleStringValue(forXPath: "parameterid") ?? ""
            guard pid == parameterID else { continue }

            // Update or create the <value> element
            if let valueNode = (try? paramElem.nodes(forXPath: "value"))?.first {
                valueNode.stringValue = newValue
            } else {
                paramElem.addChild(XMLElement(name: "value", stringValue: newValue))
            }
            document.isDirty = true
            return true
        }
        return false
    }

    /// Removes an entire effect (filter) from a clipitem by filter index.
    @discardableResult
    static func removeEffect(
        clipElementID: String,
        filterIndex: Int,
        in document: FCPXMLDocument
    ) -> Bool {
        guard let root = document.xmlDocument.rootElement() else { return false }
        let xpath = "//clipitem[@id='\(clipElementID)']"
        guard let clipNodes = try? root.nodes(forXPath: xpath),
              let clipElem = clipNodes.first as? XMLElement
        else { return false }

        guard let filterNodes = try? clipElem.nodes(forXPath: "filter"),
              filterIndex < filterNodes.count
        else { return false }

        filterNodes[filterIndex].detach()
        document.isDirty = true
        return true
    }

    // MARK: - Timecode Mutations

    /// Updates the sequence-level starting timecode.
    @discardableResult
    static func updateSequenceTimecode(
        in document: FCPXMLDocument,
        sequenceElementID: String,
        timecodeString: String,
        frame: Int,
        displayFormat: String
    ) -> Bool {
        guard let root = document.xmlDocument.rootElement() else { return false }
        let xpath = "//sequence[@id='\(sequenceElementID)']"
        guard let seqNodes = try? root.nodes(forXPath: xpath),
              let seqElem = seqNodes.first as? XMLElement
        else { return false }

        // Find or create <timecode> element
        let tcElem: XMLElement
        if let existing = (try? seqElem.nodes(forXPath: "timecode"))?.first as? XMLElement {
            tcElem = existing
        } else {
            tcElem = XMLElement(name: "timecode")
            // Insert after <rate> if it exists, otherwise at beginning
            if let rateNodes = try? seqElem.nodes(forXPath: "rate"),
               let rateNode = rateNodes.first,
               let rateIndex = seqElem.children?.firstIndex(where: { $0 === rateNode }) {
                seqElem.insertChild(tcElem, at: rateIndex + 1)
            } else {
                seqElem.insertChild(tcElem, at: 0)
            }
        }

        // Update or create <string>
        if let existing = (try? tcElem.nodes(forXPath: "string"))?.first {
            existing.stringValue = timecodeString
        } else {
            tcElem.addChild(XMLElement(name: "string", stringValue: timecodeString))
        }

        // Update or create <frame>
        if let existing = (try? tcElem.nodes(forXPath: "frame"))?.first {
            existing.stringValue = String(frame)
        } else {
            tcElem.addChild(XMLElement(name: "frame", stringValue: String(frame)))
        }

        // Update or create <displayformat>
        if let existing = (try? tcElem.nodes(forXPath: "displayformat"))?.first {
            existing.stringValue = displayFormat
        } else {
            tcElem.addChild(XMLElement(name: "displayformat", stringValue: displayFormat))
        }

        // Ensure <rate> exists inside <timecode> (copy from sequence rate)
        if (try? tcElem.nodes(forXPath: "rate"))?.first == nil {
            if let seqRate = (try? seqElem.nodes(forXPath: "rate"))?.first as? XMLElement {
                tcElem.addChild(seqRate.copy() as! XMLElement)
            }
        }

        document.isDirty = true
        return true
    }

    // MARK: - Private

    private static func resolveClipFilename(
        _ clipElem: XMLElement,
        fileMap: [String: String]
    ) -> String? {
        guard let fileElem = (try? clipElem.nodes(forXPath: "file"))?.first as? XMLElement
        else { return nil }

        if let directName = fileElem.singleStringValue(forXPath: "name"),
           !directName.isEmpty {
            return directName
        }

        if let fileID = fileElem.attributeValue(forName: "id") {
            return fileMap[fileID]
        }

        return nil
    }
}
