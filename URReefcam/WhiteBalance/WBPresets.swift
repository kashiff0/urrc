import Foundation

struct WBPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var temperature: Float   // Kelvin
    var tint: Float          // -150 to +150

    init(id: UUID = UUID(), name: String, temperature: Float, tint: Float) {
        self.id = id
        self.name = name
        self.temperature = temperature
        self.tint = tint
    }
}

extension WBPreset {

    // MARK: - Built-in reef presets (from dev brief)

    static let builtIn: [WBPreset] = [
        WBPreset(name: "Reef Blue",  temperature: 8500, tint:  45),
        WBPreset(name: "Actinic",    temperature: 9500, tint:  60),
        WBPreset(name: "Mixed Reef", temperature: 7500, tint:  30),
        WBPreset(name: "FOWLR",      temperature: 6500, tint:  10),
        WBPreset(name: "Natural",    temperature: 5500, tint:   0),
    ]
}

// MARK: - Custom Preset Store

final class WBPresetStore: ObservableObject {

    private let key = "com.ureefcam.customPresets"

    @Published var customPresets: [WBPreset] = [] {
        didSet { save() }
    }

    init() { load() }

    var allPresets: [WBPreset] { WBPreset.builtIn + customPresets }

    func save(preset: WBPreset) {
        if let idx = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[idx] = preset
        } else {
            customPresets.append(preset)
        }
    }

    func delete(preset: WBPreset) {
        customPresets.removeAll { $0.id == preset.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([WBPreset].self, from: data) else { return }
        customPresets = presets
    }
}
