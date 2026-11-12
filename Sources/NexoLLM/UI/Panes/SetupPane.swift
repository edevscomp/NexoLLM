import AppKit
import CoreGraphics
import SwiftUI

struct SetupPane: View {
    let actions: SettingsActions
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var net = NetworkMonitor.shared
    @State private var axTrusted = AX.isTrusted(prompt: false)
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var inlinePredictionOn = SystemTextPrefs.isOn(.inlinePrediction)
    @State private var autocorrectOn = SystemTextPrefs.isOn(.autocorrect)
    @State private var unconfirmed = false

    private var allSet: Bool { axTrusted && status.modelReady }

    var body: some View {
        GlassPage {
            header

            GlassSection(L("Permissions", "Permessi")) {
                SettingRow(L("Accessibility", "Accessibilità"),
                           L("Required to read the text around the cursor and insert suggestions.",
                             "Necessaria per leggere il testo intorno al cursore e inserire i suggerimenti.")) {
                    if axTrusted {
                        StatusLabel(text: L("Granted", "Concesso"))
                    } else {
                        Button(L("Grant", "Concedi")) { actions.openAccessibilitySettings() }
                    }
                }
                SettingRow(L("Screen Recording", "Registrazione schermo"),
                           L("Optional. Lets NexoLLM read the active window for context. Images are processed on this computer and discarded.",
                             "Facoltativa. Permette a NexoLLM di leggere la finestra attiva per il contesto. Le immagini vengono elaborate su questo computer e scartate.")) {
                    if screenRecording {
                        StatusLabel(text: L("Granted", "Concesso"))
                    } else {
                        Button(L("Grant", "Concedi")) { actions.requestScreenRecording() }
                    }
                }
            }

            GlassSection(L("Model", "Modello")) {
                SettingRow(L("Engine", "Motore"), detail: Fmt.status(status.engine)) {
                    HStack(spacing: 8) {
                        if status.modelReady {
                            StatusLabel(text: L("Ready", "Pronto"))
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button(L("Restart", "Riavvia")) { actions.restartServices() }
                    }
                }
            }

            GlassSection(L("Recommended", "Consigliati")) {
                SettingRow(L("System inline predictions", "Suggerimenti inline di sistema"),
                           L("The system's grey text after the cursor. It competes with NexoLLM's suggestions: turning it off is recommended.",
                             "Il testo grigio del sistema dopo il cursore. Si sovrappone ai suggerimenti di NexoLLM: disattivarlo è consigliato."),
                           detail: inlinePredictionOn ? L("On", "Attivi") : L("Off", "Disattivati")) {
                    systemToggle(.inlinePrediction, isOn: inlinePredictionOn)
                }
                SettingRow(L("System autocorrect", "Correzione automatica di sistema"),
                           L("The blue bubble that replaces a word as you type (\"cao\" → \"ciao\"). NexoLLM suggests its own fixes, so you can turn this off too.",
                             "Il fumetto blu che sostituisce una parola mentre scrivi (\"cao\" → \"ciao\"). NexoLLM propone le sue correzioni, quindi puoi disattivarla."),
                           detail: autocorrectOn ? L("On", "Attiva") : L("Off", "Disattivata")) {
                    systemToggle(.autocorrect, isOn: autocorrectOn)
                }
                if unconfirmed {
                    // Only when the system didn't store the change: say so and offer its keyboard settings.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                        Text(L("The system didn't confirm the change. Check it in the keyboard settings.",
                               "Il sistema non ha confermato la modifica. Controlla nelle impostazioni della tastiera."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L("Keyboard Settings", "Impostazioni Tastiera")) { SystemTextPrefs.openKeyboardSettings() }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 6)
                }
                ToggleRow(L("Use the clipboard", "Usa gli appunti"),
                          L("Recently copied text is used as context.", "Il testo copiato di recente viene usato come contesto."),
                          isOn: $settings.prefs.useClipboard)
            }
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .task {
            while !Task.isCancelled && (!axTrusted || !screenRecording) {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refresh()
            }
        }
    }

    @ViewBuilder private var header: some View {
        let p = Settings.shared.prefs
        if allSet {
            HeroBanner(symbol: "checkmark",
                       title: L("All set, NexoLLM is live", "Tutto pronto, NexoLLM è attivo"),
                       subtitle: L("Start typing anywhere. \(p.nextWordShortcut.display) accepts a word, \(p.fullCompletionShortcut.display) the whole suggestion, \(p.quickMenuShortcut.display) opens the menu.",
                                   "Inizia a scrivere ovunque. \(p.nextWordShortcut.display) accetta una parola, \(p.fullCompletionShortcut.display) l'intero suggerimento, \(p.quickMenuShortcut.display) apre il menu."),
                       colors: [Theme.mint, Theme.cyan, Theme.blue])
        } else {
            let missing = [axTrusted ? nil : L("Accessibility permission", "il permesso di Accessibilità"),
                           status.modelReady ? nil : L("a model (see Models)", "un modello (vedi Modelli)")].compactMap { $0 }
            HeroBanner(symbol: "sparkles",
                       title: L("Almost there", "Ci siamo quasi"),
                       subtitle: L("NexoLLM still needs ", "A NexoLLM serve ancora ") + missing.joined(separator: L(" and ", " e ")) + ".",
                       colors: [Theme.amber, Theme.rose, Theme.violet]) {
                if !status.modelReady { ProgressView().controlSize(.small) }
            }
        }
    }

    private func refresh() {
        axTrusted = AX.isTrusted(prompt: false)
        screenRecording = CGPreflightScreenCaptureAccess()
        inlinePredictionOn = SystemTextPrefs.isOn(.inlinePrediction)
        autocorrectOn = SystemTextPrefs.isOn(.autocorrect)
    }

    /// "Turn Off" / "Turn On Again", applied to every app and read back from the system right away.
    @ViewBuilder private func systemToggle(_ kind: SystemTextPrefs.Kind, isOn: Bool) -> some View {
        Button(isOn ? L("Turn Off", "Disattiva") : L("Turn On Again", "Riattiva")) {
            unconfirmed = !SystemTextPrefs.set(kind, on: !isOn)
            refresh()
        }
    }
}
