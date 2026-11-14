import SwiftUI

struct BatteryPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var models = ModelManager.shared
    @State private var onBattery = Power.onBattery

    private static let chooseTag = "\u{0}choose"

    var body: some View {
        GlassPage {
            HeroBanner(symbol: onBattery ? "bolt.fill" : "powerplug.fill",
                       title: onBattery ? L("Running on battery", "A batteria") : L("Plugged in", "Collegato all'alimentatore"),
                       subtitle: onBattery
                           ? L("These settings apply now.", "Queste impostazioni sono attive ora.")
                           : L("These settings apply as soon as you unplug.", "Queste impostazioni si attivano appena scolleghi l'alimentatore."),
                       colors: onBattery ? [Theme.amber, Theme.mint, Theme.cyan] : [Theme.mint, Theme.cyan, Theme.blue]) {
                StatusPill(text: onBattery ? L("Battery", "Batteria") : L("AC Power", "Alimentatore"),
                           symbol: onBattery ? "battery.75percent" : "bolt.horizontal.fill",
                           color: onBattery ? Theme.amber : Theme.mint)
            }
            .animation(Theme.spring, value: onBattery)

            GlassSection(L("On Battery Power", "A batteria")) {
                ToggleRow(L("Suggest only on demand", "Suggerisci solo su richiesta"),
                          L("Suggestions appear only when you press the Suggest now shortcut.", "I suggerimenti compaiono solo quando premi la scorciatoia Suggerisci ora."),
                          isOn: $settings.prefs.batteryOnDemand)
                ToggleRow(L("On demand below 20%", "Su richiesta sotto il 20%"),
                          L("Below 20% battery, suggestions appear only on demand until you plug in.",
                            "Sotto il 20% di batteria i suggerimenti compaiono solo su richiesta finché non colleghi l'alimentatore."),
                          isOn: $settings.prefs.lowBatteryOnDemand)
                    .disabled(settings.prefs.batteryOnDemand)
                SettingRow(L("Battery model", "Modello a batteria"),
                           L("A smaller model uses less energy, with slightly lower quality. Manage models in Models.",
                             "Un modello più piccolo consuma meno energia, con qualità leggermente inferiore. Gestisci i modelli in Modelli.")) {
                    GlassMenuPicker(selection: batteryModel, options: batteryOptions)
                }
                ToggleRow(L("Shorter suggestions", "Suggerimenti più brevi"),
                          L("One step shorter than your suggestion length.", "Un livello più corti della lunghezza scelta."),
                          isOn: $settings.prefs.batteryShorter)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Power.changed)) { _ in onBattery = Power.onBattery }
    }

    private var batteryOptions: [(String, String, Bool)] {
        let current = settings.prefs.batteryModelPath
        var seen = Set<String>()
        var modelRows: [(String, String, Bool)] = models.installed.compactMap { m in
            guard seen.insert(m.path).inserted else { return nil }
            return (m.path, "\(m.name) · \(Fmt.bytes(m.bytes))", false)
        }
        if !current.isEmpty, seen.insert(current).inserted {
            modelRows.append((current, SettingsUI.fileName(current), false))
        }
        return [("", L("Same as plugged in", "Uguale a quello con alimentatore"), false)]
            + modelRows
            + [(Self.chooseTag, L("Choose GGUF…", "Scegli GGUF…"), true)]
    }

    private var batteryModel: Binding<String> {
        Binding(get: { settings.prefs.batteryModelPath }, set: { value in
            var newPath = value
            if value == Self.chooseTag {
                guard let path = SettingsUI.chooseGGUF(startingAt: settings.prefs.modelPath) else { return }
                newPath = path
            }
            guard newPath != settings.prefs.batteryModelPath else { return }
            settings.prefs.batteryModelPath = newPath   // the app switches models automatically
        })
    }
}
