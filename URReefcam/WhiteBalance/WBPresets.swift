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

    // MARK: - Built-in reef presets

    static let builtIn: [WBPreset] = [
        WBPreset(name: "Reef Blue",  temperature: 8500,  tint:  45),
        WBPreset(name: "Actinic",    temperature: 9500,  tint:  60),
        WBPreset(name: "Deep Blue",  temperature: 14000, tint:  80),
        WBPreset(name: "Mixed Reef", temperature: 7500,  tint:  30),
        WBPreset(name: "FOWLR",      temperature: 6500,  tint:  10),
        WBPreset(name: "Natural",    temperature: 5500,  tint:   0),
    ]

    // MARK: - Gel filter presets
    // These counteract the heavy blue/actinic spectrum of reef lighting.
    // Equivalent to placing a physical CTO (Color Temperature Orange) or
    // tobacco gel over the lens — pushing WB very warm so coral colours
    // read naturally instead of washed out blue.

    static let gels: [WBPreset] = [
        // 1/4 CTO — subtle warm correction, still shows blue character
        WBPreset(name: "1/4 CTO",       temperature: 4500, tint: +15),
        // 1/2 CTO — the everyday reef-photography "orange gel" sweet spot
        WBPreset(name: "1/2 CTO",       temperature: 3800, tint: +20),
        // Full CTO — matches a Magic Filter / Keldan ambient filter
        WBPreset(name: "Full CTO",       temperature: 3200, tint: +25),
        // Tobacco / brown gel — adds warmth with a slight green-brown cast,
        // useful for showing sand bed / rock colouration under blue LEDs
        WBPreset(name: "Tobacco Brown",  temperature: 3600, tint: +35),
        // 15K Gel — pushes maximum blue/violet for extreme actinic setups;
        // sits near the hardware gain ceiling so results vary by device
        WBPreset(name: "15K Gel",        temperature: 15000, tint: +90),
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
