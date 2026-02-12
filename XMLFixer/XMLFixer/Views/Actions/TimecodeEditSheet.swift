import SwiftUI

struct TimecodeEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var timecodeText: String = "01:00:00:00"
    @State private var displayFormat: String = "NDF"
    @State private var batchMode: Bool = false

    // The target sequence (if single mode) — set from appState.timecodeEditTargetSequenceID
    private var targetSequence: SequenceInfo? {
        guard let targetID = appState.timecodeEditTargetSequenceID else { return nil }
        return appState.documents.flatMap(\.sequences).first { $0.id == targetID }
    }

    private var isValid: Bool {
        let cleaned = timecodeText.replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        return parts.count == 4 && parts[0] >= 0 && parts[0] <= 23 && parts[1] >= 0 && parts[1] <= 59 && parts[2] >= 0 && parts[2] <= 59
    }

    private var referenceTC: Timecode? {
        guard let targetID = appState.timecodeEditTargetSequenceID,
              let match = appState.referenceMatches[targetID] else { return nil }
        return match.selectedTimecode
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Start Timecode")
                .font(.headline)

            Form {
                if let seq = targetSequence {
                    LabeledContent("Sequence") {
                        Text(seq.name)
                    }
                    LabeledContent("Current TC") {
                        Text(seq.startTimecodeString ?? "00:00:00:00")
                            .font(.system(.body, design: .monospaced))
                    }
                }

                LabeledContent("New Timecode") {
                    TextField("HH:MM:SS:FF", text: $timecodeText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }

                Picker("Display Format", selection: $displayFormat) {
                    Text("Non-Drop Frame").tag("NDF")
                    Text("Drop Frame").tag("DF")
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                if targetSequence == nil {
                    // Batch mode - show all sequences that will be affected
                    let allSequences = appState.documents.flatMap(\.sequences)
                    LabeledContent("Applies to") {
                        Text("\(allSequences.count) sequences across \(appState.documents.count) XMLs")
                            .foregroundStyle(.secondary)
                    }
                }

                if let refTC = referenceTC {
                    Divider()
                    HStack {
                        Text("Reference TC:")
                            .foregroundStyle(.secondary)
                        Text(refTC.description)
                            .font(.system(.body, design: .monospaced))
                        Button("Use Reference TC") {
                            timecodeText = refTC.description
                            displayFormat = refTC.isDropFrame ? "DF" : "NDF"
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 400)

            if !isValid {
                Text("Invalid timecode format. Use HH:MM:SS:FF")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    applyTimecode()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 450)
        .onAppear {
            if let seq = targetSequence {
                timecodeText = seq.startTimecodeString ?? "01:00:00:00"
                displayFormat = seq.startTimecodeDisplayFormat ?? "NDF"
            }
        }
    }

    private func applyTimecode() {
        // Parse the timecode to get frame count
        let timebase = targetSequence?.timebase ?? appState.documents.first?.sequences.first?.timebase ?? 25
        guard let tc = Timecode.parse(timecodeText, timebase: timebase, dropFrame: displayFormat == "DF") else { return }

        if let targetID = appState.timecodeEditTargetSequenceID {
            appState.updateSequenceTimecode(sequenceID: targetID, newTC: timecodeText, frame: tc.totalFrames, displayFormat: displayFormat)
        } else {
            appState.batchUpdateTimecodes(newTC: timecodeText, frame: tc.totalFrames, displayFormat: displayFormat)
        }
    }
}
