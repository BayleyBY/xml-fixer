import Foundation

struct SourcesSequenceBuilder {

    // MARK: - Phase 1: Collect Usage Ranges

    /// Scan all loaded documents and collect per-media usage data.
    static func collectUsages(from documents: [FCPXMLDocument]) -> [MediaUsageSummary] {
        var summaryByFilename: [String: MediaUsageSummary] = [:]

        for doc in documents {
            guard let root = doc.xmlDocument.rootElement() else { continue }
            let fileMap = FCPXMLMutator.buildFileMap(from: doc.xmlDocument)
            let fileElements = buildFileElementMap(from: doc.xmlDocument)

            // Only scan VIDEO clipitems (audio clips have same source in/out)
            let xpath = "//sequence/media/video/track/clipitem"
            guard let clipNodes = try? root.nodes(forXPath: xpath) else { continue }

            for clipNode in clipNodes {
                guard let clipElem = clipNode as? XMLElement else { continue }
                guard let fileElem = (try? clipElem.nodes(forXPath: "file"))?.first as? XMLElement,
                      let fileID = fileElem.attributeValue(forName: "id")
                else { continue }

                let filename: String? = {
                    if let name = fileElem.singleStringValue(forXPath: "name"), !name.isEmpty { return name }
                    return fileMap[fileID]
                }()
                guard let resolvedName = filename else { continue }

                guard let inPoint = clipElem.singleIntValue(forXPath: "in"),
                      let outPoint = clipElem.singleIntValue(forXPath: "out"),
                      inPoint >= 0, outPoint > inPoint
                else { continue }

                // Extract speed factor from timewarp/speed effects
                let speedFactor: Double = Self.extractSpeedFactor(from: clipElem)

                let range = SourceRange(inPoint: inPoint, outPoint: outPoint, speedFactor: speedFactor)

                if var existing = summaryByFilename[resolvedName] {
                    existing.rawRanges.append(range)
                    if existing.fileElement == nil,
                       let fullElem = fileElements[fileID], fullElem.childCount > 0 {
                        existing.fileElement = fullElem.copy() as? XMLElement
                    }
                    summaryByFilename[resolvedName] = existing
                } else {
                    let fullFileElem = fileElements[fileID]
                    let resolvedFile = fullFileElem ?? fileElem

                    let duration = resolvedFile.singleIntValue(forXPath: "duration") ?? 0
                    let timebase = resolvedFile.singleIntValue(forXPath: "rate/timebase") ?? 25
                    let ntscStr = resolvedFile.singleStringValue(forXPath: "rate/ntsc")
                    let ntsc = ntscStr?.uppercased() == "TRUE"
                    let hasVideo = (try? resolvedFile.nodes(forXPath: "media/video"))?.isEmpty == false
                    let hasAudio = (try? resolvedFile.nodes(forXPath: "media/audio"))?.isEmpty == false
                    let channelCount = resolvedFile.singleIntValue(forXPath: "media/audio/channelcount") ?? 0
                    let width = resolvedFile.singleIntValue(forXPath: "media/video/samplecharacteristics/width")
                    let height = resolvedFile.singleIntValue(forXPath: "media/video/samplecharacteristics/height")
                    let tcString = resolvedFile.singleStringValue(forXPath: "timecode/string")
                    let reelName = resolvedFile.singleStringValue(forXPath: "timecode/reel/name")

                    summaryByFilename[resolvedName] = MediaUsageSummary(
                        filename: resolvedName,
                        pathURL: resolvedFile.singleStringValue(forXPath: "pathurl"),
                        sourceDuration: duration,
                        timebase: timebase,
                        ntsc: ntsc,
                        hasVideo: hasVideo || true,  // if we found it in video track, it has video
                        hasAudio: hasAudio,
                        audioChannelCount: channelCount,
                        videoWidth: width,
                        videoHeight: height,
                        timecodeString: tcString,
                        reelName: reelName,
                        rawRanges: [range],
                        fileElement: (fullFileElem?.childCount ?? 0) > 0 ? fullFileElem?.copy() as? XMLElement : nil
                    )
                }
            }
        }

        return Array(summaryByFilename.values)
            .sorted { $0.filename.localizedCaseInsensitiveCompare($1.filename) == .orderedAscending }
    }

    // MARK: - Phase 2: Merge Ranges

    static func applyHandlesAndMerge(summaries: inout [MediaUsageSummary], handles: Int, mergeThreshold: Int = 0) {
        for i in summaries.indices {
            summaries[i].mergeRanges(handles: handles, mergeThreshold: mergeThreshold)
        }
    }

    // MARK: - Phase 3: Build XML

    static func buildXML(from summaries: [MediaUsageSummary], options: SourcesExportOptions) -> XMLDocument {
        let xmlDoc = XMLDocument(kind: .document)
        xmlDoc.version = "1.0"
        xmlDoc.characterEncoding = "UTF-8"

        let xmemlElem = XMLElement(name: "xmeml")
        xmemlElem.addAttribute(XMLNode.attribute(withName: "version", stringValue: "4") as! XMLNode)
        xmlDoc.setRootElement(xmemlElem)

        let sequenceElem = XMLElement(name: "sequence")
        sequenceElem.addAttribute(XMLNode.attribute(withName: "id", stringValue: "sequence-1") as! XMLNode)
        xmemlElem.addChild(sequenceElem)

        addChild(to: sequenceElem, name: "name", value: options.sequenceName)
        addRateElement(to: sequenceElem, timebase: options.sequenceTimebase, ntsc: options.ntsc)

        // Determine format from first summary that has video dimensions
        let formatSource = summaries.first(where: { $0.videoWidth != nil && $0.videoHeight != nil })
        let seqWidth = formatSource?.videoWidth ?? 1920
        let seqHeight = formatSource?.videoHeight ?? 1080

        // Timecode element (start at 01:00:00:00)
        let seqTimecode = XMLElement(name: "timecode")
        addRateElement(to: seqTimecode, timebase: options.sequenceTimebase, ntsc: options.ntsc)
        addChild(to: seqTimecode, name: "string", value: "01:00:00:00")
        addChild(to: seqTimecode, name: "frame", value: String(options.sequenceTimebase * 3600))
        addChild(to: seqTimecode, name: "displayformat", value: options.ntsc ? "DF" : "NDF")
        sequenceElem.addChild(seqTimecode)

        // Duration placeholder — will be updated after clips are laid out
        let durationElem = XMLElement(name: "duration", stringValue: "0")
        sequenceElem.addChild(durationElem)

        let mediaElem = XMLElement(name: "media")
        sequenceElem.addChild(mediaElem)

        let videoElem = XMLElement(name: "video")
        mediaElem.addChild(videoElem)

        // Format block — required by DaVinci Resolve to interpret the sequence
        let formatElem = XMLElement(name: "format")
        let sampleChars = XMLElement(name: "samplecharacteristics")
        addRateElement(to: sampleChars, timebase: options.sequenceTimebase, ntsc: options.ntsc)
        addChild(to: sampleChars, name: "width", value: String(seqWidth))
        addChild(to: sampleChars, name: "height", value: String(seqHeight))
        addChild(to: sampleChars, name: "anamorphic", value: "FALSE")
        addChild(to: sampleChars, name: "pixelaspectratio", value: "square")
        addChild(to: sampleChars, name: "fielddominance", value: "none")
        formatElem.addChild(sampleChars)
        videoElem.addChild(formatElem)

        let videoTrackElem = XMLElement(name: "track")
        videoElem.addChild(videoTrackElem)

        let maxAudioChannels = options.includeAudio
            ? summaries.filter(\.hasAudio).map(\.audioChannelCount).max() ?? 0
            : 0

        var audioTrackElems: [XMLElement] = []
        if maxAudioChannels > 0 {
            let audioElem = XMLElement(name: "audio")
            mediaElem.addChild(audioElem)
            for _ in 1...maxAudioChannels {
                let trackElem = XMLElement(name: "track")
                audioElem.addChild(trackElem)
                audioTrackElems.append(trackElem)
            }
        }

        var timelinePosition = 0
        var clipCounter = 0
        var filenameToFileID: [String: String] = [:]
        var fileIDCounter = 0

        let activeSummaries = summaries.filter { !$0.mergedRanges.isEmpty }

        for summary in activeSummaries {
            // Get or create file ID for this filename
            let fileID: String
            if let existingID = filenameToFileID[summary.filename] {
                fileID = existingID
            } else {
                fileIDCounter += 1
                fileID = "file-\(fileIDCounter)"
                filenameToFileID[summary.filename] = fileID
            }

            var isFirstReference = true

            for range in summary.mergedRanges {
                clipCounter += 1

                let sourceLength = range.length
                let timelineLength: Int
                if summary.timebase != options.sequenceTimebase && summary.timebase > 0 {
                    timelineLength = Int(round(Double(sourceLength) * Double(options.sequenceTimebase) / Double(summary.timebase)))
                } else {
                    timelineLength = sourceLength
                }

                let clipStart = timelinePosition
                let clipEnd = timelinePosition + timelineLength

                // Video clipitem
                let clipitem = XMLElement(name: "clipitem")
                clipitem.addAttribute(XMLNode.attribute(withName: "id", stringValue: "clipitem-\(clipCounter)") as! XMLNode)
                addChild(to: clipitem, name: "name", value: summary.filename)
                addChild(to: clipitem, name: "enabled", value: "TRUE")
                addChild(to: clipitem, name: "duration", value: String(summary.sourceDuration))
                addRateElement(to: clipitem, timebase: summary.timebase, ntsc: summary.ntsc)
                addChild(to: clipitem, name: "start", value: String(clipStart))
                addChild(to: clipitem, name: "end", value: String(clipEnd))
                addChild(to: clipitem, name: "in", value: String(range.inPoint))
                addChild(to: clipitem, name: "out", value: String(range.outPoint))

                if isFirstReference, let fullFile = summary.fileElement {
                    let fileCopy = fullFile.copy() as! XMLElement
                    fileCopy.removeAttribute(forName: "id")
                    fileCopy.addAttribute(XMLNode.attribute(withName: "id", stringValue: fileID) as! XMLNode)
                    clipitem.addChild(fileCopy)
                    isFirstReference = false
                } else {
                    let fileStub = XMLElement(name: "file")
                    fileStub.addAttribute(XMLNode.attribute(withName: "id", stringValue: fileID) as! XMLNode)
                    clipitem.addChild(fileStub)
                }

                videoTrackElem.addChild(clipitem)

                // Audio clipitems
                if options.includeAudio && summary.hasAudio {
                    let channels = min(summary.audioChannelCount, maxAudioChannels)
                    for ch in 1...max(1, channels) {
                        let audioClip = XMLElement(name: "clipitem")
                        audioClip.addAttribute(XMLNode.attribute(withName: "id", stringValue: "clipitem-\(clipCounter)-audio-\(ch)") as! XMLNode)
                        addChild(to: audioClip, name: "name", value: summary.filename)
                        addChild(to: audioClip, name: "enabled", value: "TRUE")
                        addChild(to: audioClip, name: "duration", value: String(summary.sourceDuration))
                        addRateElement(to: audioClip, timebase: summary.timebase, ntsc: summary.ntsc)
                        addChild(to: audioClip, name: "start", value: String(clipStart))
                        addChild(to: audioClip, name: "end", value: String(clipEnd))
                        addChild(to: audioClip, name: "in", value: String(range.inPoint))
                        addChild(to: audioClip, name: "out", value: String(range.outPoint))

                        let fileStub = XMLElement(name: "file")
                        fileStub.addAttribute(XMLNode.attribute(withName: "id", stringValue: fileID) as! XMLNode)
                        audioClip.addChild(fileStub)

                        let sourcetrack = XMLElement(name: "sourcetrack")
                        addChild(to: sourcetrack, name: "mediatype", value: "audio")
                        addChild(to: sourcetrack, name: "trackindex", value: String(ch))
                        audioClip.addChild(sourcetrack)

                        if ch - 1 < audioTrackElems.count {
                            audioTrackElems[ch - 1].addChild(audioClip)
                        }
                    }
                }

                timelinePosition = clipEnd
            }
        }

        // Update duration with final timeline length
        durationElem.stringValue = String(timelinePosition)

        return xmlDoc
    }

    // MARK: - Phase 4: Export

    static func export(documents: [FCPXMLDocument], options: SourcesExportOptions) throws -> URL {
        guard let outputDir = options.outputDirectory else {
            throw ExportError.noOutputDirectory
        }

        var summaries = collectUsages(from: documents)
        applyHandlesAndMerge(summaries: &summaries, handles: options.handles, mergeThreshold: options.mergeThreshold)

        let xmlDoc = buildXML(from: summaries, options: options)

        let outputURL = outputDir.appendingPathComponent(options.outputFilename)
        let accessing = outputDir.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                outputDir.stopAccessingSecurityScopedResource()
            }
        }

        // Serialize and prepend DOCTYPE
        var xmlString = xmlDoc.xmlString(options: [.nodePrettyPrint])
        if let range = xmlString.range(of: "?>") {
            xmlString.insert(contentsOf: "\n<!DOCTYPE xmeml>", at: range.upperBound)
        }
        try xmlString.data(using: .utf8)?.write(to: outputURL)

        return outputURL
    }

    // MARK: - Private Helpers

    /// Extract speed factor from a clipitem's filter effects.
    /// Returns 1.0 for normal speed, 2.0 for 200%, 0.5 for 50% etc.
    private static func extractSpeedFactor(from clipElem: XMLElement) -> Double {
        guard let filterNodes = try? clipElem.nodes(forXPath: "filter/effect") else { return 1.0 }
        for filterNode in filterNodes {
            guard let effectElem = filterNode as? XMLElement else { continue }
            let effectName = effectElem.singleStringValue(forXPath: "name")?.lowercased() ?? ""
            let effectID = effectElem.singleStringValue(forXPath: "effectid")?.lowercased() ?? ""

            // Match speed/timewarp/timeremap effects
            if effectName.contains("speed") || effectName.contains("time") ||
               effectID.contains("speed") || effectID.contains("timeremap") {
                // Look for speed parameter (FCP stores as percentage: 100 = normal)
                if let params = try? effectElem.nodes(forXPath: "parameter") {
                    for param in params {
                        guard let paramElem = param as? XMLElement else { continue }
                        let paramID = paramElem.singleStringValue(forXPath: "parameterid")?.lowercased() ?? ""
                        if paramID == "speed" || paramID == "rate" {
                            if let valueStr = paramElem.singleStringValue(forXPath: "value"),
                               let value = Double(valueStr), value > 0 {
                                return value / 100.0
                            }
                        }
                    }
                }
                // If we found a speed effect but no explicit value, check reverse flag
                if let reverseParam = effectElem.singleStringValue(forXPath: "parameter[parameterid='reverse']/value"),
                   reverseParam.uppercased() == "TRUE" {
                    return 1.0  // reverse at normal speed
                }
            }
        }
        return 1.0
    }

    private static func buildFileElementMap(from xmlDocument: XMLDocument) -> [String: XMLElement] {
        guard let root = xmlDocument.rootElement() else { return [:] }
        guard let fileNodes = try? root.nodes(forXPath: "//file[@id]") else { return [:] }

        var map: [String: XMLElement] = [:]
        for node in fileNodes {
            guard let elem = node as? XMLElement,
                  let fileID = elem.attributeValue(forName: "id")
            else { continue }
            if let existing = map[fileID] {
                if elem.childCount > existing.childCount { map[fileID] = elem }
            } else {
                map[fileID] = elem
            }
        }
        return map
    }

    private static func addChild(to parent: XMLElement, name: String, value: String) {
        parent.addChild(XMLElement(name: name, stringValue: value))
    }

    private static func addRateElement(to parent: XMLElement, timebase: Int, ntsc: Bool) {
        let rate = XMLElement(name: "rate")
        addChild(to: rate, name: "timebase", value: String(timebase))
        addChild(to: rate, name: "ntsc", value: ntsc ? "TRUE" : "FALSE")
        parent.addChild(rate)
    }

    enum ExportError: LocalizedError {
        case noOutputDirectory
        case noUsableMedia

        var errorDescription: String? {
            switch self {
            case .noOutputDirectory: return "No output directory selected."
            case .noUsableMedia: return "No media with valid source ranges found."
            }
        }
    }
}
