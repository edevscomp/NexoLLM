import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @ObservedObject private var settings = Settings.shared
    @State private var loginError: String?

    var body: some View {
        GlassPage {
            GlassSection("App") {
                VStack(alignment: .leading, spacing: 4) {
                    ToggleRow(L("Launch at login", "Avvia al login"), isOn: Binding(get: { settings.prefs.launchAtLogin }, set: setLaunchAtLogin))
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }
                ToggleRow(L("Show in menu bar", "Mostra nella barra dei menu"),
                          L("The menu bar icon shows the status: clear when active, a pause sign when paused in the current app, dimmed when off. If hidden, open NexoLLM again from your Applications folder to return here.",
                            "L'icona nella barra dei menu mostra lo stato: nitida quando è attiva, con una pausa quando è sospesa nell'app corrente, attenuata quando è spenta. Se è nascosta, riapri NexoLLM dalla cartella Applicazioni per tornare qui."),
                          isOn: $settings.prefs.showMenuBarIcon)
                SettingRow(L("Appearance", "Aspetto")) {
                    GlassSegmentedPicker($settings.prefs.appearance) { $0.label }
                }
                SettingRow(L("Language", "Lingua")) {
                    LanguagePickerButton()
                }
            }
            .onAppear {
                settings.prefs.launchAtLogin = LaunchAtLogin.isEnabled
            }

            GlassSection(L("Completions", "Completamenti")) {
                ToggleRow(L("Enable in all apps", "Attiva in tutte le app"),
                          L("Apps can still be turned on or off one by one in Apps.", "Puoi comunque attivare o disattivare le singole app in App."),
                          isOn: $settings.prefs.enabledByDefault)
                ToggleRow(L("Suggest inside existing text", "Suggerisci dentro il testo esistente"),
                          L("Also suggest when there is text after the cursor on the same line.", "Suggerisce anche quando c'è testo dopo il cursore sulla stessa riga."),
                          isOn: $settings.prefs.completeInsideText)
                EnumPickerRow(L("Suggestion length", "Lunghezza dei suggerimenti"),
                              L("Longer suggestions take more time and drift more often. Medium is the best balance.",
                                "I suggerimenti lunghi richiedono più tempo e sbagliano più spesso. Media è il miglior compromesso."),
                              selection: $settings.prefs.completionLength) { $0.label }
                SettingRow(L("Delay", "Ritardo"),
                           L("Time after your last keystroke before a suggestion is computed.", "Tempo dall'ultimo tasto premuto prima di calcolare un suggerimento.")) {
                    HStack {
                        Slider(value: $settings.prefs.debounceMs, in: 40...400, step: 10)
                            .frame(width: 180)
                        Text("\(Int(settings.prefs.debounceMs)) ms")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }

            GlassSection(L("Look and Sound", "Aspetto e suono")) {
                SettingRow(L("Sound when accepting", "Suono quando accetti"),
                           L("A soft mechanical key click when you accept a word or a suggestion.", "Un morbido clic da tastiera meccanica quando accetti una parola o un suggerimento.")) {
                    HStack(spacing: 10) {
                        Button(L("Preview", "Ascolta")) { KeyClickSound.play(force: true) }
                        Toggle("", isOn: Binding(get: { settings.prefs.acceptSound },
                                                 set: { settings.prefs.acceptSound = $0; if $0 { KeyClickSound.play(force: true) } }))
                            .labelsHidden()
                            .toggleStyle(AuroraToggleStyle())
                    }
                }
                SettingRow(L("Sound volume", "Volume del suono"), L("How loud the key click is.", "Quanto è forte il clic.")) {
                    HStack {
                        Slider(value: $settings.prefs.acceptSoundVolume, in: 0.1...1, step: 0.05) { editing in
                            if !editing { KeyClickSound.play(force: true) }
                        }
                        .frame(width: 180)
                        Text("\(Int((settings.prefs.acceptSoundVolume * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                ToggleRow(L("Tint suggestions", "Suggerimenti colorati"),
                          L("Draws the suggestion in a soft accent color instead of grey. It still adapts to light and dark pages.",
                            "Mostra il suggerimento in un colore tenue invece che grigio. Si adatta comunque a pagine chiare e scure."),
                          isOn: $settings.prefs.ghostTint)
                SettingRow(L("Suggestion opacity", "Opacità dei suggerimenti"), L("How strongly the suggestion stands out next to your text.", "Quanto risalta il suggerimento accanto al tuo testo.")) {
                    HStack {
                        Slider(value: $settings.prefs.ghostOpacity, in: 0.5...1, step: 0.05)
                            .frame(width: 180)
                        Text("\(Int((settings.prefs.ghostOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            }

            GlassSection(L("Spelling", "Ortografia")) {
                ToggleRow(L("Hold suggestions on typos", "Sospendi i suggerimenti sugli errori"),
                          L("No completion while the current word looks misspelled.", "Nessun completamento mentre la parola corrente sembra sbagliata."),
                          isOn: $settings.prefs.suppressOnTypo)
                ToggleRow(L("Suggest corrections", "Suggerisci correzioni"),
                          L("Offers the fix for a misspelled word you just finished. Only near misses in the language you're writing are corrected; names and your own words are left alone.",
                            "Propone la correzione di una parola appena scritta male. Corregge solo errori lievi nella lingua in cui scrivi; nomi e parole tue restano intatti."),
                          indent: true, isOn: $settings.prefs.showSuggestedFixes)
                    .disabled(!settings.prefs.suppressOnTypo)
            }

            GlassSection(L("Web Lookup", "Ricerca web")) {
                ToggleRow(L("Web Lookup (\(settings.prefs.webLookupShortcut.display))", "Ricerca web (\(settings.prefs.webLookupShortcut.display))"),
                          L("Sends the highlighted text or your question (at most 300 characters) to Wikipedia, Wiktionary, Wikiquote, DuckDuckGo and Google News, only when you press the shortcut. The summary is written on this computer.",
                            "Invia il testo evidenziato o la tua domanda (al massimo 300 caratteri) a Wikipedia, Wiktionary, Wikiquote, DuckDuckGo e Google News, solo quando premi la scorciatoia. Il riassunto è scritto su questo computer."),
                          isOn: $settings.prefs.webLookupEnabled)
            }

            GlassSection(L("Memory Use", "Uso della memoria")) {
                SettingRow(L("Unload the model when idle", "Scarica il modello quando inattivo"),
                           L("Frees the model's memory after this long without typing. It loads again in about a second.",
                             "Libera la memoria del modello dopo questo tempo senza scrivere. Si ricarica in circa un secondo.")) {
                    GlassMenuPicker(selection: $settings.prefs.unloadAfterMinutes,
                                    options: [(0, L("Never", "Mai")), (5, L("After 5 minutes", "Dopo 5 minuti")), (10, L("After 10 minutes", "Dopo 10 minuti")),
                                              (30, L("After 30 minutes", "Dopo 30 minuti")), (60, L("After 1 hour", "Dopo 1 ora"))])
                }
                SettingRow(L("Pause when you stop typing", "Pausa quando smetti di scrivere"),
                           L("Releases the prompt cache and GPU buffers and stops background work. The model stays ready; the next keystroke resumes instantly.",
                             "Libera la cache del prompt e i buffer della GPU e ferma il lavoro in background. Il modello resta pronto; il tasto successivo riprende subito.")) {
                    GlassMenuPicker(selection: $settings.prefs.sleepAfterSeconds,
                                    options: [(30, L("After 30 seconds", "Dopo 30 secondi")), (60, L("After 1 minute", "Dopo 1 minuto")), (120, L("After 2 minutes", "Dopo 2 minuti")),
                                              (300, L("After 5 minutes", "Dopo 5 minuti")), (0, L("Never", "Mai"))])
                }
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.setEnabled(on)
            settings.prefs.launchAtLogin = LaunchAtLogin.isEnabled
            loginError = nil
        } catch {
            loginError = L("Couldn't update the login item: ", "Impossibile aggiornare l'elemento di login: ") + error.localizedDescription
            settings.prefs.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
