import SwiftUI

struct ClipInspectorView: View {
    let clip: TimelineClip
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Inspector")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    appState.selectedTimelineClip = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(white: 0.1))

            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    clipInfoSection

                    if let twInfo = timewarpInfo {
                        timewarpSection(twInfo)
                    }

                    if !clip.effects.isEmpty {
                        effectsSection
                    } else if timewarpInfo == nil {
                        Text("No effects")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 24)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 240)
        .background(Color(white: 0.09))
    }

    // MARK: - Clip Info

    private var clipInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(clip.clipName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 3) {
                InspectorRow("File", clip.filename)
                InspectorRow("Track", "\(clip.trackType == .video ? "V" : "A")\(clip.trackIndex + 1)")
                InspectorRow("Start", "\(clip.startFrame)")
                InspectorRow("End", "\(clip.endFrame)")
                InspectorRow("Duration", "\(clip.durationFrames) frames")
                InspectorRow("Source In", "\(clip.sourceInFrame)")
                InspectorRow("Source Out", "\(clip.sourceOutFrame)")
            }
        }
        .padding(8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Timewarp

    private struct TimewarpInfo {
        let effect: ClipEffect
        let speedParam: ClipParameter?
        let isAnimated: Bool
        let staticValue: String?
    }

    private var timewarpInfo: TimewarpInfo? {
        for effect in clip.effects {
            let name = effect.name.lowercased()
            let eid = (effect.effectID ?? "").lowercased()
            if name.contains("speed") || name.contains("timewarp") || name.contains("time remap")
                || eid.contains("speed") || eid.contains("timewarp") || eid.contains("timeremap") {
                let speedParam = effect.parameters.first { p in
                    let pid = p.parameterID.lowercased()
                    return pid.contains("speed") || pid == "rate" || pid.contains("graphdict")
                }
                let isAnimated = speedParam?.keyframes.isEmpty == false
                let staticValue: String? = {
                    if !isAnimated, let val = speedParam?.value, let dv = Double(val) {
                        return String(format: "%.1f%%", dv)
                    }
                    return nil
                }()
                return TimewarpInfo(effect: effect, speedParam: speedParam, isAnimated: isAnimated, staticValue: staticValue)
            }
        }
        return nil
    }

    private func timewarpSection(_ info: TimewarpInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if info.isAnimated {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                    Text("ANIMATED TIMEWARP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.red)
                }

                if let speedParam = info.speedParam {
                    Text("\(speedParam.keyframes.count) keyframes")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    KeyframeView(
                        keyframes: speedParam.keyframes,
                        clipDurationFrames: clip.durationFrames
                    )
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("SPEED: \(info.staticValue ?? "?")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(info.isAnimated ? Color.red.opacity(0.1) : Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            (info.isAnimated ? Color.red : Color.orange).opacity(0.2),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Effects

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Effects (\(clip.effects.count))")
                .font(.system(size: 11, weight: .semibold))

            ForEach(clip.effects) { effect in
                effectRow(effect)
            }
        }
    }

    private func effectRow(_ effect: ClipEffect) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: effectIcon(for: effect))
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
                Text(effect.name)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if let clipID = clip.clipElementID {
                    Button {
                        appState.removeEffect(
                            clipElementID: clipID,
                            filterIndex: effect.filterIndex
                        )
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Remove this effect")
                }
            }

            if let category = effect.effectCategory {
                Text(category)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            ForEach(effect.parameters) { param in
                ParameterEditRow(
                    param: param,
                    clipElementID: clip.clipElementID,
                    filterIndex: effect.filterIndex,
                    clipDurationFrames: clip.durationFrames
                )
            }
        }
        .padding(8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func effectIcon(for effect: ClipEffect) -> String {
        let name = effect.name.lowercased()
        if name.contains("motion") || name.contains("transform") || name.contains("basic motion") {
            return "arrow.up.left.and.arrow.down.right"
        } else if name.contains("opacity") {
            return "circle.lefthalf.filled"
        } else if name.contains("crop") {
            return "crop"
        } else if name.contains("speed") || name.contains("time") {
            return "gauge.with.dots.needle.33percent"
        } else if name.contains("color") || name.contains("colour") {
            return "paintpalette"
        } else if name.contains("blur") {
            return "aqi.medium"
        }
        return "slider.horizontal.3"
    }
}

// MARK: - Parameter Edit Row

private struct ParameterEditRow: View {
    let param: ClipParameter
    let clipElementID: String?
    let filterIndex: Int
    let clipDurationFrames: Int
    @Environment(AppState.self) private var appState
    @State private var editValue: String = ""
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(param.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()

                if isEditing {
                    TextField("", text: $editValue)
                        .font(.system(size: 10).monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .onSubmit {
                            commitEdit()
                        }
                        .onExitCommand {
                            isEditing = false
                        }
                } else if let value = param.value {
                    Button {
                        editValue = value
                        isEditing = true
                    } label: {
                        Text(formatValue(value))
                            .font(.system(size: 10).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Click to edit")
                }
            }

            if !param.keyframes.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.yellow)
                    Text("\(param.keyframes.count) keyframes")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                KeyframeView(
                    keyframes: param.keyframes,
                    clipDurationFrames: clipDurationFrames
                )
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        guard let clipID = clipElementID, editValue != param.value else { return }
        appState.updateEffectParameter(
            clipElementID: clipID,
            filterIndex: filterIndex,
            parameterID: param.parameterID,
            newValue: editValue
        )
    }

    private func formatValue(_ value: String) -> String {
        if let doubleVal = Double(value) {
            if doubleVal == doubleVal.rounded() {
                return String(format: "%.0f", doubleVal)
            }
            return String(format: "%.2f", doubleVal)
        }
        return value
    }
}

// MARK: - Inspector Row Helper

private struct InspectorRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 55, alignment: .trailing)
            Text(value)
                .font(.system(size: 10))
                .lineLimit(1)
        }
    }
}
