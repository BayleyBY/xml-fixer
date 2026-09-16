import Foundation
import AVFoundation
import CoreMedia

/// Lossless QuickTime/MP4 trimming: compressed samples are read with AVAssetReader and written back with
/// AVAssetWriter using nil output settings (passthrough), so nothing is decoded or re-encoded.
/// Cuts on long-GOP codecs snap outward to the nearest sync samples. A timecode track is written whose
/// start reflects the trimmed in point.
struct QuickTimeTrimEngine: TrimEngine {
    let kind: TrimSourceKind = .quickTime

    // MARK: - Probe

    /// Frame rate, frame count, embedded start TC and GOP structure of an original.
    func probe(url: URL) async throws -> TrimSourceProbe {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw TrimEngineError.noVideoTrack
        }
        let fps = try await video.load(.nominalFrameRate)
        let timeRange = try await video.load(.timeRange)
        let (timebase, ntsc) = Self.nominalTimebase(fps: Double(fps))
        let frameDuration = try await video.load(.minFrameDuration)
        let frameCount: Int
        if frameDuration.isValid && frameDuration.seconds > 0 {
            frameCount = Int((timeRange.duration.seconds / frameDuration.seconds).rounded())
        } else {
            frameCount = Int((timeRange.duration.seconds * Double(fps)).rounded())
        }

        var probe = TrimSourceProbe(timebase: timebase, ntsc: ntsc, frameCount: frameCount, startTimecode: nil)
        probe.startTimecode = await AVAssetTimecodeReader.readStartTimecode(from: url, timebase: timebase)
        probe.isAllIntra = Self.looksAllIntra(track: video)
        if probe.startTimecode == nil {
            probe.notes.append("No timecode track; using frame offsets")
        }
        return probe
    }

    /// 23.976 → (24, ntsc), 29.97 → (30, ntsc), 25 → (25, false) …
    static func nominalTimebase(fps: Double) -> (Int, Bool) {
        guard fps > 0 else { return (25, false) }
        let rounded = Int(fps.rounded())
        let ntsc = abs(Double(rounded) - fps) > 0.01
        return (rounded, ntsc)
    }

    /// Inspect the first few dozen samples: if every one is a full sync sample the codec is intra-only.
    static func looksAllIntra(track: AVAssetTrack) -> Bool? {
        guard track.canProvideSampleCursors,
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder()
        else { return nil }
        for _ in 0..<48 {
            if !cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue { return false }
            if cursor.stepInDecodeOrder(byCount: 1) == 0 { break }
        }
        return true
    }

    // MARK: - Trim

    func trim(
        item: TrimPlanItem,
        candidate: TrimCandidate,
        range: TrimRange,
        rangeIndex: Int,
        rangeCount: Int,
        outputDirectory: URL,
        options: TrimOptions,
        progress: @escaping (Double) -> Void
    ) async throws -> TrimEngineOutput {
        let sourceURL = candidate.url
        let outputURL = TrimNaming.outputURL(for: sourceURL, in: outputDirectory, rangeIndex: rangeIndex, rangeCount: rangeCount)
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if fm.fileExists(atPath: outputURL.path) {
            if options.overwriteExisting {
                try fm.removeItem(at: outputURL)
            } else {
                throw TrimEngineError.outputExists(outputURL)
            }
        }

        let startFrameNumber: Int? = {
            // Frame number of the original's first frame, from the XML TC when the file has none.
            if let tc = item.probe?.startTimecode { return tc.totalFrames }
            if let xmlTC = item.xmlStartTimecode,
               let tc = Timecode.parse(xmlTC, timebase: item.probe?.timebase ?? item.xmlTimebase),
               item.basis == .offset {
                // Offset basis: original frame 0 == XML frame 0, so the XML TC is the original's TC (converted to its rate)
                let xmlFrames = tc.totalFrames
                let origTB = item.probe?.timebase ?? item.xmlTimebase
                return Self.convertFrames(xmlFrames, from: item.xmlTimebase, to: origTB)
            }
            return nil
        }()

        let result = try await Self.passthroughTrim(
            sourceURL: sourceURL,
            outputURL: outputURL,
            inFrame: range.originalIn,
            outFrame: range.originalOut,
            startFrameNumber: startFrameNumber,
            progress: progress
        )
        var output = TrimEngineOutput()
        output.outputs = [outputURL]
        output.framesWritten = result.framesWritten
        output.extraFrames = max(0, result.framesWritten - range.length)
        output.bytesWritten = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        output.messages = result.messages
        return output
    }

    static func convertFrames(_ frames: Int, from tbA: Int, to tbB: Int) -> Int {
        guard tbA > 0, tbA != tbB else { return frames }
        return (frames * tbB * 2 + tbA) / (2 * tbA)
    }

    struct PassthroughResult {
        var framesWritten: Int
        var snappedInFrame: Int
        var snappedOutFrame: Int
        var messages: [String]
    }

    /// Core reader→writer copy. `inFrame`/`outFrame` are frame indices into the video track (out exclusive).
    /// `startFrameNumber` is the timecode frame number of the *original's* first frame; when non-nil a
    /// timecode track is written starting at `startFrameNumber + snappedInFrame`.
    static func passthroughTrim(
        sourceURL: URL,
        outputURL: URL,
        inFrame: Int,
        outFrame: Int,
        startFrameNumber: Int?,
        progress: @escaping (Double) -> Void
    ) async throws -> PassthroughResult {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw TrimEngineError.noVideoTrack }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let timecodeTracks = try await asset.loadTracks(withMediaType: .timecode)

        let trackRange = try await videoTrack.load(.timeRange)
        var frameDuration = try await videoTrack.load(.minFrameDuration)
        if !frameDuration.isValid || frameDuration.seconds <= 0 {
            let fps = try await videoTrack.load(.nominalFrameRate)
            frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, fps.rounded())))
        }
        let naturalTimeScale = try await videoTrack.load(.naturalTimeScale)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let videoFormat = try await videoTrack.load(.formatDescriptions).first

        // Requested range in track time
        let requestedStart = CMTimeAdd(trackRange.start, CMTimeMultiply(frameDuration, multiplier: Int32(clamping: inFrame)))
        var requestedEnd = CMTimeAdd(trackRange.start, CMTimeMultiply(frameDuration, multiplier: Int32(clamping: outFrame)))
        let trackEnd = CMTimeRangeGetEnd(trackRange)
        if CMTimeCompare(requestedEnd, trackEnd) > 0 { requestedEnd = trackEnd }

        // Snap outward to sync samples (no-op for intra-only codecs).
        // AVSampleCursor timestamps live in the track's *media* timeline, whereas AVAssetReader's
        // timeRange is in the edited track timeline; files with B-frames usually carry an edit list
        // that offsets the two, so every cursor time is mapped through the track segments.
        var snappedStart = requestedStart
        var snappedEnd = requestedEnd
        var messages: [String] = []
        if videoTrack.canProvideSampleCursors {
            let segments = try await videoTrack.load(.segments)
            let mapper = MediaTimeMapper(segments: segments)
            if let cursor = videoTrack.makeSampleCursor(presentationTimeStamp: mapper.toMedia(requestedStart)) {
                var steps = 0
                while !(cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue && CMTimeCompare(mapper.toTrack(cursor.presentationTimeStamp), requestedStart) <= 0) {
                    if cursor.stepInDecodeOrder(byCount: -1) == 0 || steps > 10_000 { break }
                    steps += 1
                }
                snappedStart = CMTimeMaximum(trackRange.start, CMTimeMinimum(mapper.toTrack(cursor.presentationTimeStamp), requestedStart))
            }
            if CMTimeCompare(requestedEnd, trackEnd) < 0,
               let cursor = videoTrack.makeSampleCursor(presentationTimeStamp: mapper.toMedia(requestedEnd)) {
                var steps = 0
                var reachedEnd = false
                while !(cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue && CMTimeCompare(mapper.toTrack(cursor.presentationTimeStamp), requestedEnd) >= 0) {
                    if cursor.stepInDecodeOrder(byCount: 1) == 0 || steps > 10_000 { reachedEnd = true; break }
                    steps += 1
                }
                snappedEnd = reachedEnd ? trackEnd : CMTimeMinimum(trackEnd, CMTimeMaximum(mapper.toTrack(cursor.presentationTimeStamp), requestedEnd))
            }
        }
        if CMTimeCompare(snappedStart, requestedStart) != 0 || CMTimeCompare(snappedEnd, requestedEnd) != 0 {
            messages.append("Cut snapped to keyframes")
        }

        let snappedInFrame = frameIndex(of: snappedStart, trackStart: trackRange.start, frameDuration: frameDuration)
        let snappedOutFrame = frameIndex(of: snappedEnd, trackStart: trackRange.start, frameDuration: frameDuration)
        let rangeDuration = CMTimeSubtract(snappedEnd, snappedStart)
        guard rangeDuration.seconds > 0 else {
            throw TrimEngineError.unreadable("Empty range after snapping")
        }

        // Reader
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw TrimEngineError.readerFailed(error.localizedDescription) }
        reader.timeRange = CMTimeRange(start: snappedStart, duration: rangeDuration)

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw TrimEngineError.readerFailed("Cannot add video output") }
        reader.add(videoOutput)

        var audioPairs: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []

        // Writer
        let tempURL = outputURL.deletingLastPathComponent().appendingPathComponent(".\(outputURL.lastPathComponent).partial")
        try? FileManager.default.removeItem(at: tempURL)
        let fileType: AVFileType = ["mp4", "m4v"].contains(outputURL.pathExtension.lowercased()) ? .mp4 : .mov
        let writer: AVAssetWriter
        do { writer = try AVAssetWriter(outputURL: tempURL, fileType: fileType) } catch { throw TrimEngineError.writerFailed(error.localizedDescription) }
        writer.shouldOptimizeForNetworkUse = false
        writer.movieTimeScale = naturalTimeScale
        if let metadata = try? await asset.load(.metadata), !metadata.isEmpty {
            writer.metadata = metadata
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = preferredTransform
        videoInput.mediaTimeScale = naturalTimeScale
        guard writer.canAdd(videoInput) else { throw TrimEngineError.writerFailed("Cannot add video input") }
        writer.add(videoInput)

        for track in audioTracks {
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { continue }
            reader.add(output)
            let format = try await track.load(.formatDescriptions).first
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            if let lang = try? await track.load(.languageCode) { input.languageCode = lang }
            guard writer.canAdd(input) else { continue }
            writer.add(input)
            audioPairs.append((output, input))
        }

        // Timecode track
        var timecodeInput: AVAssetWriterInput? = nil
        var timecodeSample: CMSampleBuffer? = nil
        if let startFrameNumber {
            let sourceTCFormat = try? await timecodeTracks.first?.load(.formatDescriptions).first
            if let tcFormat = try makeTimecodeFormat(source: sourceTCFormat, frameDuration: frameDuration) {
                let input = AVAssetWriterInput(mediaType: .timecode, outputSettings: nil, sourceFormatHint: tcFormat)
                input.expectsMediaDataInRealTime = false
                if writer.canAdd(input) {
                    writer.add(input)
                    videoInput.addTrackAssociation(withTrackOf: input, type: AVAssetTrack.AssociationType.timecode.rawValue)
                    timecodeInput = input
                    let frameNumber = Int32(clamping: startFrameNumber + snappedInFrame)
                    timecodeSample = try makeTimecodeSample(format: tcFormat, frameNumber: frameNumber, pts: snappedStart, duration: rangeDuration)
                } else {
                    messages.append("\(fileType == .mp4 ? "MP4" : "This container") cannot carry a timecode track; start TC not embedded")
                }
            } else {
                messages.append("Could not create timecode track")
            }
        }

        guard writer.startWriting() else {
            throw TrimEngineError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        guard reader.startReading() else {
            writer.cancelWriting()
            throw TrimEngineError.readerFailed(reader.error?.localizedDescription ?? "startReading failed")
        }
        writer.startSession(atSourceTime: snappedStart)

        if let timecodeInput, let timecodeSample {
            if !timecodeInput.append(timecodeSample) {
                messages.append("Timecode sample rejected: \(writer.error?.localizedDescription ?? "unknown")")
            }
            timecodeInput.markAsFinished()
        }

        // Pump samples
        let pumpQueue = DispatchQueue(label: "com.xmlfixer.trim.pump")
        let framesWritten = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let group = DispatchGroup()
            var videoFrames = 0
            var failure: Error? = nil
            let rangeSeconds = rangeDuration.seconds
            let startSeconds = snappedStart.seconds
            let lock = NSLock()

            func pump(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput, isVideo: Bool) {
                group.enter()
                input.requestMediaDataWhenReady(on: pumpQueue) {
                    while input.isReadyForMoreMediaData {
                        if Task.isCancelled {
                            lock.lock(); if failure == nil { failure = TrimEngineError.cancelled }; lock.unlock()
                            input.markAsFinished(); group.leave(); return
                        }
                        guard let sample = output.copyNextSampleBuffer() else {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                        if !input.append(sample) {
                            lock.lock()
                            if failure == nil {
                                failure = TrimEngineError.writerFailed(writer.error?.localizedDescription ?? "append failed")
                            }
                            lock.unlock()
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                        if isVideo {
                            videoFrames += CMSampleBufferGetNumSamples(sample)
                            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                            if rangeSeconds > 0 {
                                progress(min(1, max(0, (pts - startSeconds) / rangeSeconds)))
                            }
                        }
                    }
                }
            }

            pump(output: videoOutput, input: videoInput, isVideo: true)
            for (output, input) in audioPairs {
                pump(output: output, input: input, isVideo: false)
            }

            group.notify(queue: pumpQueue) {
                if let failure {
                    continuation.resume(throwing: failure)
                } else if reader.status == .failed {
                    continuation.resume(throwing: TrimEngineError.readerFailed(reader.error?.localizedDescription ?? "unknown"))
                } else {
                    continuation.resume(returning: videoFrames)
                }
            }
        }

        if reader.status == .reading { reader.cancelReading() }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: tempURL)
            throw TrimEngineError.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed")
        }
        try FileManager.default.moveItem(at: tempURL, to: outputURL)
        progress(1)

        return PassthroughResult(
            framesWritten: framesWritten,
            snappedInFrame: snappedInFrame,
            snappedOutFrame: snappedOutFrame,
            messages: messages
        )
    }

    // MARK: - Helpers

    /// Converts between a track's media timeline (sample-table timestamps, what AVSampleCursor reports)
    /// and its edited timeline (what AVAssetReader.timeRange and AVAssetTrack.timeRange use).
    struct MediaTimeMapper {
        let segments: [AVAssetTrackSegment]

        func toMedia(_ trackTime: CMTime) -> CMTime {
            for seg in segments where !seg.isEmpty {
                let target = seg.timeMapping.target
                if CMTimeRangeContainsTime(target, time: trackTime) || CMTimeCompare(trackTime, CMTimeRangeGetEnd(target)) == 0 {
                    return CMTimeAdd(seg.timeMapping.source.start, CMTimeSubtract(trackTime, target.start))
                }
            }
            return trackTime
        }

        func toTrack(_ mediaTime: CMTime) -> CMTime {
            for seg in segments where !seg.isEmpty {
                let source = seg.timeMapping.source
                if CMTimeRangeContainsTime(source, time: mediaTime) || CMTimeCompare(mediaTime, CMTimeRangeGetEnd(source)) == 0 {
                    return CMTimeAdd(seg.timeMapping.target.start, CMTimeSubtract(mediaTime, source.start))
                }
            }
            // Outside every segment (e.g. samples hidden by the edit list): extrapolate from the first segment.
            if let seg = segments.first(where: { !$0.isEmpty }) {
                return CMTimeAdd(seg.timeMapping.target.start, CMTimeSubtract(mediaTime, seg.timeMapping.source.start))
            }
            return mediaTime
        }
    }

    static func frameIndex(of time: CMTime, trackStart: CMTime, frameDuration: CMTime) -> Int {
        let offset = CMTimeSubtract(time, trackStart).seconds
        let fd = frameDuration.seconds
        guard fd > 0 else { return 0 }
        return Int((offset / fd).rounded())
    }

    /// Reuse the source's tmcd format when present, else build a TimeCode32 description.
    static func makeTimecodeFormat(source: CMFormatDescription?, frameDuration: CMTime) throws -> CMTimeCodeFormatDescription? {
        if let source, CMFormatDescriptionGetMediaType(source) == kCMMediaType_TimeCode {
            return source
        }
        let fps = frameDuration.seconds > 0 ? 1.0 / frameDuration.seconds : 25
        let quanta = UInt32(fps.rounded())
        // Non-drop-frame; drop-frame is only carried over when the source already had a tmcd track.
        let flags: UInt32 = UInt32(kCMTimeCodeFlag_24HourMax)
        var desc: CMTimeCodeFormatDescription?
        let status = CMTimeCodeFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            timeCodeFormatType: kCMTimeCodeFormatType_TimeCode32,
            frameDuration: frameDuration,
            frameQuanta: quanta,
            flags: flags,
            extensions: nil,
            formatDescriptionOut: &desc
        )
        guard status == noErr else { return nil }
        return desc
    }

    static func makeTimecodeSample(format: CMTimeCodeFormatDescription, frameNumber: Int32, pts: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: 4,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: 4,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let block = blockBuffer else {
            throw TrimEngineError.writerFailed("Timecode block buffer failed (\(status))")
        }
        var bigEndian = frameNumber.bigEndian
        status = withUnsafeBytes(of: &bigEndian) { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: 4)
        }
        guard status == kCMBlockBufferNoErr else {
            throw TrimEngineError.writerFailed("Timecode data write failed (\(status))")
        }

        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleSize = 4
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample
        )
        guard status == noErr, let result = sample else {
            throw TrimEngineError.writerFailed("Timecode sample failed (\(status))")
        }
        return result
    }
}
