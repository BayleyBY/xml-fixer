import Foundation

struct ReelMetadataRepairer {

    /// Regex from Python script: matches filenames like "A_0012_001_h3F2A.mov"
    /// Group 1: "A_0012", Group 2: "3F2A"
    static let reelPattern = try! NSRegularExpression(
        pattern: #"(A_\d+).*_h([A-Z0-9]{4})"#
    )

    /// Repairs reel metadata for all A_-prefixed file elements in the document.
    /// For each <file> whose <name> starts with "A_":
    ///   - If <file><timecode> exists but has no <reel> child:
    ///     - Extract reel name from filename using regex
    ///     - Insert <reel><name>A_XXXX_YYYY</name></reel> into <timecode>
    /// Returns the number of files repaired.
    @discardableResult
    static func repairReelMetadata(in xmlDocument: XMLDocument) -> Int {
        guard let root = xmlDocument.rootElement() else { return 0 }
        var fixedCount = 0
        var processedIDs: Set<String> = []

        guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { return 0 }

        for node in fileNodes {
            guard let fileElem = node as? XMLElement,
                  let fileID = fileElem.attribute(forName: "id")?.stringValue,
                  !processedIDs.contains(fileID)
            else { continue }

            processedIDs.insert(fileID)

            guard let nameText = (try? fileElem.nodes(forXPath: "name"))?.first?.stringValue,
                  nameText.hasPrefix("A_")
            else { continue }

            // Check for timecode node
            guard let timecodeNode = (try? fileElem.nodes(forXPath: "timecode"))?.first as? XMLElement
            else { continue }

            // Skip if reel already exists
            let existingReel = try? timecodeNode.nodes(forXPath: "reel")
            if let reels = existingReel, !reels.isEmpty { continue }

            // Extract reel name from filename using regex
            let range = NSRange(nameText.startIndex..., in: nameText)
            guard let match = reelPattern.firstMatch(in: nameText, range: range),
                  let group1Range = Range(match.range(at: 1), in: nameText),
                  let group2Range = Range(match.range(at: 2), in: nameText)
            else { continue }

            let reelName = "\(nameText[group1Range])_\(nameText[group2Range])"

            // Build <reel><name>...</name></reel> and insert
            let reelElem = XMLElement(name: "reel")
            let reelNameElem = XMLElement(name: "name", stringValue: reelName)
            reelElem.addChild(reelNameElem)
            timecodeNode.addChild(reelElem)

            fixedCount += 1
        }

        return fixedCount
    }

    /// Counts how many files would have reel metadata repaired (for confirmation preview).
    static func countRepairableFiles(in documents: [FCPXMLDocument]) -> (fileCount: Int, documentCount: Int) {
        var totalFiles = 0
        var affectedDocs = 0

        for doc in documents {
            guard let root = doc.xmlDocument.rootElement() else { continue }
            var processedIDs: Set<String> = []
            var docCount = 0

            guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { continue }

            for node in fileNodes {
                guard let fileElem = node as? XMLElement,
                      let fileID = fileElem.attribute(forName: "id")?.stringValue,
                      !processedIDs.contains(fileID)
                else { continue }

                processedIDs.insert(fileID)

                guard let nameText = (try? fileElem.nodes(forXPath: "name"))?.first?.stringValue,
                      nameText.hasPrefix("A_")
                else { continue }

                guard let timecodeNode = (try? fileElem.nodes(forXPath: "timecode"))?.first as? XMLElement
                else { continue }

                let existingReel = try? timecodeNode.nodes(forXPath: "reel")
                if let reels = existingReel, !reels.isEmpty { continue }

                let range = NSRange(nameText.startIndex..., in: nameText)
                guard reelPattern.firstMatch(in: nameText, range: range) != nil
                else { continue }

                docCount += 1
            }

            if docCount > 0 {
                totalFiles += docCount
                affectedDocs += 1
            }
        }

        return (totalFiles, affectedDocs)
    }
}
