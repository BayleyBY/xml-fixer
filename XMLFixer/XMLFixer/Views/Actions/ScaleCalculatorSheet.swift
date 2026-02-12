import SwiftUI

struct ScaleCalculatorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var sourceWidth = ""
    @State private var sourceHeight = ""
    @State private var targetWidth = ""
    @State private var targetHeight = ""

    private var scaleX: Double? {
        guard let sw = Double(sourceWidth), let tw = Double(targetWidth), sw > 0 else { return nil }
        return (tw / sw) * 100.0
    }

    private var scaleY: Double? {
        guard let sh = Double(sourceHeight), let th = Double(targetHeight), sh > 0 else { return nil }
        return (th / sh) * 100.0
    }

    private var inverseScaleX: Double? {
        guard let sw = Double(sourceWidth), let tw = Double(targetWidth), tw > 0 else { return nil }
        return (sw / tw) * 100.0
    }

    private var inverseScaleY: Double? {
        guard let sh = Double(sourceHeight), let th = Double(targetHeight), th > 0 else { return nil }
        return (sh / th) * 100.0
    }

    private var isNonUniform: Bool {
        guard let sx = scaleX, let sy = scaleY else { return false }
        return abs(sx - sy) > 0.01
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Scale / Resize Calculator")
                .font(.headline)

            Form {
                Section("Source (Full Resolution)") {
                    HStack {
                        TextField("Width", text: $sourceWidth)
                            .frame(width: 100)
                        Text("\u{00D7}")
                        TextField("Height", text: $sourceHeight)
                            .frame(width: 100)
                        Spacer()
                        Button("From Selection") {
                            populateFromSelection()
                        }
                        .disabled(appState.selectedMediaIDs.isEmpty)
                    }
                }

                Section("Target (Proxy Resolution)") {
                    HStack {
                        TextField("Width", text: $targetWidth)
                            .frame(width: 100)
                        Text("\u{00D7}")
                        TextField("Height", text: $targetHeight)
                            .frame(width: 100)
                    }

                    HStack(spacing: 8) {
                        Text("Presets:")
                            .foregroundStyle(.secondary)
                        Button("1/2") { applyDivisor(2) }
                        Button("1/4") { applyDivisor(4) }
                        Button("1/8") { applyDivisor(8) }
                    }
                    .disabled(sourceWidth.isEmpty || sourceHeight.isEmpty)
                }

                Section("Result") {
                    if let sx = scaleX, let sy = scaleY,
                       let isx = inverseScaleX, let isy = inverseScaleY {

                        LabeledContent("Source \u{2192} Target") {
                            Text(String(format: "%.2f%% \u{00D7} %.2f%%", sx, sy))
                                .foregroundStyle(isNonUniform ? .orange : .primary)
                        }

                        LabeledContent("Target \u{2192} Source") {
                            Text(String(format: "%.2f%% \u{00D7} %.2f%%", isx, isy))
                                .foregroundStyle(isNonUniform ? .orange : .primary)
                        }

                        if isNonUniform {
                            Text("Non-uniform scaling: X and Y percentages differ.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Enter source and target dimensions to see results.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 420)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 480)
    }

    private func populateFromSelection() {
        guard let firstID = appState.selectedMediaIDs.first,
              let media = appState.mediaReferences.first(where: { $0.id == firstID }),
              let resolution = media.resolution
        else { return }

        let parts = resolution.split(separator: "x")
        guard parts.count == 2 else { return }
        sourceWidth = String(parts[0])
        sourceHeight = String(parts[1])
    }

    private func applyDivisor(_ divisor: Int) {
        guard let sw = Int(sourceWidth), let sh = Int(sourceHeight) else { return }
        targetWidth = "\(sw / divisor)"
        targetHeight = "\(sh / divisor)"
    }
}
