import SwiftUI

struct TimelineView: View {
    let timeline: TimelineData
    @Environment(AppState.self) private var appState
    @State private var zoom: Double = 1.0
    @State private var hoveredClipID: UUID? = nil
    @State private var visibleWidth: CGFloat = 400
    @State private var visibleHeight: CGFloat = 200
    @State private var magnifyMonitor: Any? = nil
    @State private var scrollMonitor: Any? = nil

    // Box selection state
    @State private var boxSelectionStart: CGPoint? = nil
    @State private var boxSelectionCurrent: CGPoint? = nil
    @State private var isScrubbing: Bool = false

    private let trackHeight: CGFloat = 28
    private let trackLabelWidth: CGFloat = 30
    private let rulerHeight: CGFloat = 24
    // Low enough that multi-hour timelines can still fit the panel.
    private let minZoom: Double = 0.001
    private let maxZoom: Double = 20
    private let fitTrailingGap: CGFloat = 40

    private var videoColorMap: [String: Color] {
        ClipColorAssigner.buildColorMap(from: timeline.uniqueFilenames, trackType: .video)
    }
    private var audioColorMap: [String: Color] {
        ClipColorAssigner.buildColorMap(from: timeline.uniqueFilenames, trackType: .audio)
    }

    private var pixelsPerFrame: CGFloat {
        CGFloat(zoom) * 0.5
    }

    private var timelineWidth: CGFloat {
        CGFloat(timeline.totalDurationFrames) * pixelsPerFrame
    }

    private var contentWidth: CGFloat {
        timelineWidth + trackLabelWidth
    }

    private var totalTracksHeight: CGFloat {
        rulerHeight
        + CGFloat(timeline.videoTracks.count + timeline.audioTracks.count) * trackHeight
        + ((!timeline.videoTracks.isEmpty && !timeline.audioTracks.isEmpty) ? 1 : 0)
    }

    private var allClips: [TimelineClip] {
        timeline.videoTracks.flatMap(\.clips) + timeline.audioTracks.flatMap(\.clips)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    rulerRow
                    videoTracksSection
                    trackDivider
                    audioTracksSection
                }
                .frame(
                    minWidth: max(contentWidth, visibleWidth),
                    minHeight: max(totalTracksHeight, visibleHeight),
                    alignment: .topLeading
                )
                .overlay(alignment: .topLeading) {
                    if appState.playheadFrame > 0 || appState.playbackCoordinator != nil {
                        PlayheadOverlay(
                            playheadFrame: appState.playheadFrame,
                            pixelsPerFrame: pixelsPerFrame,
                            totalHeight: totalTracksHeight,
                            trackLabelWidth: trackLabelWidth
                        )
                    }
                }
                .overlay(alignment: .topLeading) {
                    boxSelectionOverlay
                }
                .background(alignment: .topLeading) {
                    Color.black.opacity(0.2)
                        .frame(
                            width: max(contentWidth, visibleWidth),
                            height: max(totalTracksHeight, visibleHeight)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { clearSelection() }
                }
                .simultaneousGesture(boxSelectionGesture)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            visibleWidth = geo.size.width
                            visibleHeight = geo.size.height
                            zoomToFit()
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            visibleWidth = newWidth
                        }
                        .onChange(of: geo.size.height) { _, newHeight in
                            visibleHeight = newHeight
                        }
                }
            )
        }
        .background(Color(white: 0.08))
        // Each newly selected sequence opens fitted to the panel; edits to the same sequence keep the zoom.
        .onChange(of: timeline.sequenceID) { zoomToFit() }
        .onAppear {
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { event in
                let factor = 1.0 + event.magnification
                withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.9)) {
                    zoom = max(minZoom, min(maxZoom, zoom * factor))
                }
                return event
            }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.modifierFlags.contains(.option) else { return event }
                let delta = event.scrollingDeltaY
                let factor = 1.0 + (delta * 0.01)
                withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.9)) {
                    zoom = max(minZoom, min(maxZoom, zoom * factor))
                }
                return nil
            }
        }
        .onDisappear {
            if let monitor = magnifyMonitor {
                NSEvent.removeMonitor(monitor)
                magnifyMonitor = nil
            }
            if let monitor = scrollMonitor {
                NSEvent.removeMonitor(monitor)
                scrollMonitor = nil
            }
        }
    }

    // MARK: - Ruler Row

    private var rulerRow: some View {
        HStack(spacing: 0) {
            // Label area placeholder
            ZStack {
                Color.white.opacity(0.04)
            }
            .frame(width: trackLabelWidth, height: rulerHeight)
            .overlay(alignment: .trailing) {
                Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            }

            TimelineRulerView(
                totalFrames: timeline.totalDurationFrames,
                timebase: timeline.timebase,
                pixelsPerFrame: pixelsPerFrame,
                playheadFrame: appState.playheadFrame
            )
            .frame(width: timelineWidth, height: rulerHeight)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isScrubbing { isScrubbing = true; NSCursor.resizeLeftRight.push() }
                    let frame = Int((value.location.x - trackLabelWidth) / pixelsPerFrame)
                    appState.seekPlayhead(toFrame: max(0, min(timeline.totalDurationFrames, frame)))
                }
                .onEnded { _ in
                    if isScrubbing { isScrubbing = false; NSCursor.pop() }
                }
        )
    }

    // MARK: - Track Sections

    private var videoTracksSection: some View {
        let sorted = timeline.videoTracks.sorted(by: { $0.index > $1.index })
        return ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, track in
            TimelineTrackView(
                track: track,
                totalTimelineWidth: timelineWidth,
                colorMap: videoColorMap,
                pixelsPerFrame: pixelsPerFrame,
                trackHeight: trackHeight,
                trackLabelWidth: trackLabelWidth,
                selectedFilenames: appState.selectedMediaFilenames,
                isEven: idx % 2 == 0,
                hoveredClipID: $hoveredClipID,
                onClipTap: handleClipTap,
                onBackgroundTap: clearSelection
            )
        }
    }

    @ViewBuilder
    private var trackDivider: some View {
        if !timeline.videoTracks.isEmpty && !timeline.audioTracks.isEmpty {
            Rectangle()
                .fill(.white.opacity(0.06))
                .frame(height: 1)
                .padding(.leading, trackLabelWidth)
        }
    }

    private var audioTracksSection: some View {
        let sorted = timeline.audioTracks.sorted(by: { $0.index < $1.index })
        return ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, track in
            TimelineTrackView(
                track: track,
                totalTimelineWidth: timelineWidth,
                colorMap: audioColorMap,
                pixelsPerFrame: pixelsPerFrame,
                trackHeight: trackHeight,
                trackLabelWidth: trackLabelWidth,
                selectedFilenames: appState.selectedMediaFilenames,
                isEven: idx % 2 == 0,
                hoveredClipID: $hoveredClipID,
                onClipTap: handleClipTap,
                onBackgroundTap: clearSelection
            )
        }
    }

    // MARK: - Box Selection

    @ViewBuilder
    private var boxSelectionOverlay: some View {
        if let start = boxSelectionStart, let current = boxSelectionCurrent {
            let rect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    private var boxSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if boxSelectionStart == nil {
                    guard value.startLocation.y > rulerHeight else { return }
                    boxSelectionStart = value.startLocation
                    NSCursor.crosshair.push()
                }
                boxSelectionCurrent = value.location
            }
            .onEnded { value in
                if let start = boxSelectionStart {
                    let rect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                    selectClipsInBox(rect)
                    NSCursor.pop()
                }
                boxSelectionStart = nil
                boxSelectionCurrent = nil
            }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            Text(timeline.sequenceName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if !appState.sourceTimecodesAtPlayhead.isEmpty {
                Circle().fill(.white.opacity(0.15)).frame(width: 3, height: 3)
                HStack(spacing: 4) {
                    Image(systemName: "film")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(appState.sourceTimecodesAtPlayhead.first?.timecode ?? "")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    if let entry = appState.sourceTimecodesAtPlayhead.first {
                        Text(entry.clipName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Track count pill
            Text("\(timeline.videoTracks.count)V / \(timeline.audioTracks.count)A")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.white.opacity(0.06), in: Capsule())

            // Duration
            Text(formatDuration(timeline.durationSeconds))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            // Zoom controls group
            HStack(spacing: 2) {
                Button { zoom = max(minZoom, zoom * 0.7) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(zoom < 0.01 ? "<1%" : "\(Int(zoom * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34)

                Button { zoom = min(maxZoom, zoom * 1.4) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle().fill(.white.opacity(0.1)).frame(width: 1, height: 12)

                Button { zoomToFit() } label: {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(white: 0.1))
    }

    // MARK: - Actions

    private func zoomToFit() {
        guard timeline.totalDurationFrames > 0 else { return }
        // Leave a visible gap after the last clip so the end of the timeline reads as the end.
        let available = max(1, visibleWidth - trackLabelWidth - fitTrailingGap)
        // pixelsPerFrame = zoom * 0.5
        let fitted = Double(available * 2.0) / Double(timeline.totalDurationFrames)
        zoom = max(minZoom, min(maxZoom, fitted))
    }

    private func clearSelection() {
        appState.selectedMediaIDs.removeAll()
        appState.selectedTimelineClip = nil
    }

    private func handleClipTap(_ clip: TimelineClip, modifiers: NSEvent.ModifierFlags) {
        if let media = appState.mediaReferences.first(where: { $0.filename == clip.filename }) {
            if modifiers.contains(.command) {
                if appState.selectedMediaIDs.contains(media.id) {
                    appState.selectedMediaIDs.remove(media.id)
                } else {
                    appState.selectedMediaIDs.insert(media.id)
                }
            } else if modifiers.contains(.shift) {
                appState.selectedMediaIDs.insert(media.id)
            } else {
                appState.selectedMediaIDs = [media.id]
            }
        }
        appState.selectedTimelineClip = clip
    }

    private func selectClipsInBox(_ rect: CGRect) {
        let startFrame = Int((rect.minX - trackLabelWidth) / pixelsPerFrame)
        let endFrame = Int((rect.maxX - trackLabelWidth) / pixelsPerFrame)

        let sortedVideoTracks = timeline.videoTracks.sorted(by: { $0.index > $1.index })
        let sortedAudioTracks = timeline.audioTracks.sorted(by: { $0.index < $1.index })
        let hasDivider = !timeline.videoTracks.isEmpty && !timeline.audioTracks.isEmpty

        var selectedFilenames = Set<String>()
        var yOffset: CGFloat = rulerHeight

        for track in sortedVideoTracks {
            let trackTop = yOffset
            let trackBottom = yOffset + trackHeight
            yOffset = trackBottom
            if rect.maxY >= trackTop && rect.minY <= trackBottom {
                for clip in track.clips {
                    if clip.endFrame > startFrame && clip.startFrame < endFrame {
                        selectedFilenames.insert(clip.filename)
                    }
                }
            }
        }

        if hasDivider { yOffset += 1 }

        for track in sortedAudioTracks {
            let trackTop = yOffset
            let trackBottom = yOffset + trackHeight
            yOffset = trackBottom
            if rect.maxY >= trackTop && rect.minY <= trackBottom {
                for clip in track.clips {
                    if clip.endFrame > startFrame && clip.startFrame < endFrame {
                        selectedFilenames.insert(clip.filename)
                    }
                }
            }
        }

        if !selectedFilenames.isEmpty {
            let mediaIDs = appState.mediaReferences
                .filter { selectedFilenames.contains($0.filename) }
                .map(\.id)
            appState.selectedMediaIDs = Set(mediaIDs)
            if let firstClip = allClips.first(where: { selectedFilenames.contains($0.filename) }) {
                appState.selectedTimelineClip = firstClip
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds - Double(Int(seconds))) * Double(timeline.timebase))
        return String(format: "%02d:%02d:%02d", mins, secs, frames)
    }
}
