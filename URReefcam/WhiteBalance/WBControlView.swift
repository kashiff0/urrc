import SwiftUI

// MARK: - WB Sliders

struct WBControlView: View {

    @ObservedObject var whiteBalanceManager: WhiteBalanceManager
    @ObservedObject var cameraManager: CameraManager
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Expand / collapse toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.sun")
                        .foregroundColor(.cyan)
                    Text("White Balance")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(whiteBalanceManager.temperature))K  \(whiteBalanceManager.tint > 0 ? "+" : "")\(Int(whiteBalanceManager.tint))")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.cyan)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .foregroundColor(.white.opacity(0.6))
                        .imageScale(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 12) {
                    WBSliderRow(
                        label: "Temp",
                        value: $whiteBalanceManager.temperature,
                        range: WhiteBalanceManager.temperatureRange,
                        unit: "K",
                        color: .orange
                    )
                    WBSliderRow(
                        label: "Tint",
                        value: $whiteBalanceManager.tint,
                        range: WhiteBalanceManager.tintRange,
                        unit: "",
                        color: .green
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

// MARK: - Single slider row

private struct WBSliderRow: View {

    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(color)

            Text("\(Int(value))\(unit)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(color)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

// MARK: - Preset Picker (top bar)

struct WBPresetPicker: View {

    @ObservedObject var whiteBalanceManager: WhiteBalanceManager
    @ObservedObject var cameraManager: CameraManager
    @StateObject private var store = WBPresetStore()
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .foregroundColor(.cyan)
                    .imageScale(.small)
                Text(whiteBalanceManager.selectedPreset?.name ?? "Custom")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            WBPresetSheet(store: store, wbManager: whiteBalanceManager)
        }
    }
}

// MARK: - Preset Sheet

private struct WBPresetSheet: View {

    @ObservedObject var store: WBPresetStore
    @ObservedObject var wbManager: WhiteBalanceManager
    @Environment(\.dismiss) private var dismiss
    @State private var showSaveDialog = false
    @State private var newPresetName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Built-in") {
                    ForEach(WBPreset.builtIn) { preset in
                        presetRow(preset)
                    }
                }
                if !store.customPresets.isEmpty {
                    Section("Custom") {
                        ForEach(store.customPresets) { preset in
                            presetRow(preset)
                        }
                        .onDelete { idx in
                            idx.forEach { store.delete(preset: store.customPresets[$0]) }
                        }
                    }
                }
            }
            .navigationTitle("WB Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPresetName = ""
                        showSaveDialog = true
                    } label: {
                        Label("Save Current", systemImage: "plus")
                    }
                }
            }
            .alert("Save Preset", isPresented: $showSaveDialog) {
                TextField("Name", text: $newPresetName)
                Button("Save") {
                    guard !newPresetName.isEmpty else { return }
                    let p = WBPreset(name: newPresetName,
                                     temperature: wbManager.temperature,
                                     tint: wbManager.tint)
                    store.save(preset: p)
                    wbManager.selectedPreset = p
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .preferredColorScheme(.dark)
        }
    }

    private func presetRow(_ preset: WBPreset) -> some View {
        Button {
            wbManager.apply(preset: preset)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name).foregroundColor(.white)
                    Text("\(Int(preset.temperature))K  \(preset.tint > 0 ? "+" : "")\(Int(preset.tint))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                if wbManager.selectedPreset?.id == preset.id {
                    Image(systemName: "checkmark").foregroundColor(.cyan)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
