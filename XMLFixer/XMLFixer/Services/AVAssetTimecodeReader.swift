import AVFoundation

enum AVAssetTimecodeReader {
    /// Read the embedded starting timecode from a QuickTime/MP4 file.
    static func readStartTimecode(from url: URL, timebase: Int) async -> Timecode? {
        let asset = AVAsset(url: url)

        // Try timecode track first
        if let tc = await readFromTimecodeTrack(asset: asset, timebase: timebase) {
            return tc
        }

        // Fallback: check metadata
        if let tc = await readFromMetadata(asset: asset, timebase: timebase) {
            return tc
        }

        return nil
    }

    private static func readFromTimecodeTrack(asset: AVAsset, timebase: Int) async -> Timecode? {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .timecode)
            guard let track = tracks.first else { return nil }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            reader.startReading()

            guard let sampleBuffer = output.copyNextSampleBuffer() else { return nil }

            // Get the timecode format description
            guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }

            let frameQuanta = CMTimeCodeFormatDescriptionGetFrameQuanta(formatDesc)
            let tcFlags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(formatDesc)
            let isDropFrame = (tcFlags & UInt32(kCMTimeCodeFlag_DropFrame)) != 0

            // Read the frame number from the sample data
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

            guard let ptr = dataPointer, length >= 4 else { return nil }

            let frameNumber = ptr.withMemoryRebound(to: Int32.self, capacity: 1) {
                Int(Int32(bigEndian: $0.pointee))
            }

            let effectiveTimebase = frameQuanta > 0 ? Int(frameQuanta) : timebase
            return Timecode.fromFrames(frameNumber, timebase: effectiveTimebase, dropFrame: isDropFrame)
        } catch {
            return nil
        }
    }

    private static func readFromMetadata(asset: AVAsset, timebase: Int) async -> Timecode? {
        do {
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                if let key = item.commonKey?.rawValue, key.lowercased().contains("timecode") {
                    if let stringValue = try await item.load(.stringValue) {
                        return Timecode.parse(stringValue, timebase: timebase)
                    }
                }
            }
        } catch {
            // Metadata read failed
        }
        return nil
    }
}
