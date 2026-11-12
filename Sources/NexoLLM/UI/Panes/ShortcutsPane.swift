import SwiftUI

struct ShortcutsPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        GlassPage {
            GlassSection(L("Accepting", "Accettare")) {
                SettingRow(L("Accept next word", "Accetta la parola successiva"),
                           L("Inserts one word at a time. Punctuation takes its own press, so an unwanted mark is never added.",
                             "Inserisce una parola alla volta. La punteggiatura richiede una pressione a sé, così non viene mai aggiunto un segno indesiderato.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.nextWordShortcut)
                }
                ToggleRow(L("Add a space after the word", "Aggiungi uno spazio dopo la parola"), indent: true, isOn: $settings.prefs.trailingSpace)
                ToggleRow(L("Keep Tab for indenting", "Mantieni Tab per il rientro"),
                          L("After a list marker or at the start of an indented line, Tab indents as usual. Accept there with the full suggestion key.",
                            "Dopo un punto elenco o all'inizio di una riga rientrata, Tab fa il rientro come al solito. Lì accetta con il tasto del suggerimento intero."),
                          indent: true, isOn: $settings.prefs.smartTab)
                SettingRow(L("Accept whole suggestion", "Accetta l'intero suggerimento"),
                           L("Inserts the entire suggestion at once (⇧⇥ by default).", "Inserisce tutto il suggerimento in una volta (⇧⇥ di default).")) {
                    ShortcutRecorder(shortcut: $settings.prefs.fullCompletionShortcut)
                }
            }

            GlassSection(L("Control", "Controllo")) {
                EnumPickerRow(L("Escape", "Esc"),
                              selection: $settings.prefs.escapeBehavior) { $0.label }
                SettingRow(L("Suggest now", "Suggerisci ora"),
                           L("Shows a suggestion immediately, even where NexoLLM is off or paused.",
                             "Mostra subito un suggerimento, anche dove NexoLLM è spento o in pausa.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.forceShortcut)
                }
                SettingRow(L("Pause in current app", "Pausa nell'app corrente"),
                           L("Pauses or resumes NexoLLM in the app you're using.", "Mette in pausa o riprende NexoLLM nell'app che stai usando.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.toggleAppShortcut)
                }
                SettingRow(L("Turn on or off everywhere", "Attiva o disattiva ovunque")) {
                    ShortcutRecorder(optional: $settings.prefs.globalToggleShortcut)
                }
                SettingRow(L("Alternatives", "Alternative"),
                           L("Lists other words for the one you're typing, or other ways to continue the sentence. Press again to switch between the two. With a word selected, lists synonyms.",
                             "Elenca altre parole per quella che stai scrivendo, o altri modi di continuare la frase. Premi di nuovo per passare dall'una all'altra. Con una parola selezionata, elenca i sinonimi.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.alternativesShortcut)
                }
                SettingRow(L("Read the screen now", "Leggi lo schermo ora"),
                           L("Reads the active window for context.", "Legge la finestra attiva per il contesto.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.captureShortcut)
                }
                SettingRow(L("Look up on the web", "Cerca sul web"),
                           L("Searches the web for the selected text or question and shows a compact summary card at the cursor (requires Wi-Fi).",
                             "Cerca sul web il testo o la domanda selezionata e mostra una scheda riassuntiva al cursore (richiede Wi-Fi).")) {
                    ShortcutRecorder(shortcut: $settings.prefs.webLookupShortcut)
                }
                SettingRow(L("Open the menu", "Apri il menu"),
                           L("Opens the NexoLLM menu at the cursor, with status, pause options, writing tools and settings.",
                             "Apre il menu di NexoLLM al cursore, con stato, opzioni di pausa, strumenti di scrittura e impostazioni.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.quickMenuShortcut)
                }
                SettingRow(L("Restart NexoLLM services", "Riavvia i servizi di NexoLLM"),
                           L("Restarts the keyboard listener, model cache and overlays without closing the app.",
                             "Riavvia l'ascolto della tastiera, la cache del modello e gli overlay senza chiudere l'app.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.restartShortcut)
                }
            }
        }
    }
}
