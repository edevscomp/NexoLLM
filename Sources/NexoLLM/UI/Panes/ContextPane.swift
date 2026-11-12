import CoreGraphics
import SwiftUI

struct ContextPane: View {
    let actions: SettingsActions
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var audio = AudioContext.shared
    @ObservedObject private var screen = ScreenContext.shared
    @ObservedObject private var plugin = AudioPlugin.shared
    @State private var tick = 0
    @State private var showConsent = false
    @State private var confirmRemove = false

    var body: some View {
        GlassPage {
            GlassSection(L("Screen", "Schermo")) {
                SettingRow(L("Read the screen for context", "Leggi lo schermo per il contesto"),
                           L("Reads the text on your display to understand what you're referencing or replying to. The image is processed on this computer and discarded; only the text is kept in memory. Requires Screen Recording.",
                             "Legge il testo sullo schermo per capire a cosa fai riferimento o stai rispondendo. L'immagine viene elaborata su questo computer e scartata; in memoria resta solo il testo. Richiede la Registrazione schermo.")) {
                    GlassSegmentedPicker($settings.prefs.screenMode) { $0.label }
                }
                Text(modeExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(Theme.spring, value: settings.prefs.screenMode)
                SettingRow(L("Read the screen now", "Leggi lo schermo ora"),
                           L("Reads your full display right now, in every mode, including side-by-side windows, and keeps the captured context active for 10 minutes.",
                             "Legge subito l'intero schermo, in ogni modalità, incluse le finestre affiancate, e mantiene attivo il contesto acquisito per 10 minuti.")) {
                    ShortcutRecorder(shortcut: $settings.prefs.captureShortcut)
                }

                screenTranscriptMonitor
            }
            GlassSection(L("Window", "Finestra")) {
                ToggleRow(L("Read nearby fields", "Leggi i campi vicini"),
                          L("Reads short fields in the same window so names, dates and numbers stay consistent with them. Read once per field and never stored. Password fields are ignored.",
                            "Legge i campi brevi della stessa finestra così nomi, date e numeri restano coerenti. Letti una volta per campo e mai salvati. I campi password vengono ignorati."),
                          isOn: $settings.prefs.useWindowFields)
            }
            GlassSection(L("Clipboard", "Appunti")) {
                ToggleRow(L("Use the clipboard", "Usa gli appunti"),
                          L("Recently copied text is used as context.", "Il testo copiato di recente viene usato come contesto."),
                          isOn: $settings.prefs.useClipboard)
            }
            GlassSection(L("Experimental plugin · Audio Context", "Plugin sperimentale · Contesto audio")) {
                audioPluginSection
            }
            GlassSection("Privacy Inspector") {
                Text(L("Exactly what NexoLLM holds in memory right now, nothing else. Screenshots and audio are discarded as soon as their text is read; password fields are never read. None of this is written to disk and none of it is sent anywhere: it is all processed on this computer.",
                       "Esattamente ciò che NexoLLM tiene in memoria adesso, nient'altro. Le schermate e l'audio vengono scartati appena letto il testo; i campi password non vengono mai letti. Niente di tutto questo viene scritto su disco né inviato altrove: è tutto elaborato su questo computer."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                memoryRow(L("Screen text", "Testo dello schermo"), ScreenContext.shared.latestPreview?.text)
                memoryRow(L("Nearby window fields", "Campi vicini della finestra"), TempCache.windowFields)
                memoryRow(L("Clipboard", "Appunti"), TempCache.clipboardPreview)
                memoryRow(L("Microphone", "Microfono"), TempCache.audioPreview)
                HStack {
                    Spacer()
                    Button(L("Refresh", "Aggiorna")) { tick += 1 }
                    Button(L("Clear Now", "Svuota ora")) { TempCache.clear(); tick += 1 }
                }
            }
            .id(tick)
        }
        .onAppear { tick += 1; plugin.refresh() }
        .sheet(isPresented: $showConsent) { AudioPluginConsentSheet(isPresented: $showConsent) }
        .confirmationDialog(L("Remove the Audio Context plugin?", "Rimuovere il plugin Contesto audio?"), isPresented: $confirmRemove) {
            Button(L("Remove", "Rimuovi"), role: .destructive) { plugin.uninstall() }
        } message: {
            Text(L("The speech model is deleted and your consent is withdrawn. You can install it again later.",
                   "Il modello vocale viene eliminato e il consenso revocato. Potrai installarlo di nuovo in seguito."))
        }
        .onChange(of: settings.prefs.screenMode) { _, mode in
            if mode != .off && !CGPreflightScreenCaptureAccess() { actions.requestScreenRecording() }
        }
    }

    @ViewBuilder private func memoryRow(_ title: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            DisclosureGroup("\(title) · \(text.count) " + L("characters", "caratteri")) {
                ScrollView {
                    Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
        } else {
            SettingRow(title, detail: L("Nothing in memory", "Niente in memoria"))
        }
    }

    private var modeExplanation: String {
        switch settings.prefs.screenMode {
        case .off:
            return L("Never reads the screen on its own. The shortcut below still works.",
                     "Non legge mai lo schermo da solo. La scorciatoia qui sotto funziona comunque.")
        case .smart:
            return L("Reads when you start writing in a field, return to it after a while, or pause after a long stretch. Never while typing, never on a timer, at most every 10 seconds (20 on battery).",
                     "Legge quando inizi a scrivere in un campo, ci torni dopo un po' o fai una pausa dopo un lungo tratto. Mai mentre scrivi, mai a intervalli fissi, al massimo ogni 10 secondi (20 a batteria).")
        case .manual:
            return L("Reads only when you press the shortcut below or choose Read the Screen Now from the menu. The capture stays with that field for 10 minutes.",
                     "Legge solo quando premi la scorciatoia qui sotto o scegli Leggi lo schermo ora dal menu. La lettura resta associata a quel campo per 10 minuti.")
        }
    }

    private var currentScreenText: String {
        !screen.latestText.isEmpty ? screen.latestText : (screen.latestPreview?.text ?? "")
    }

    private var screenTranscriptMonitor: some View {
        let screenText = currentScreenText
        let lineCount = screenText.split(whereSeparator: \.isNewline).count
        let statsLabel = L("\(lineCount) lines · \(screenText.count) chars",
                           "\(lineCount) righe · \(screenText.count) caratteri")
        let placeholder = L("Press \(settings.prefs.captureShortcut.display) anywhere or click “Read Screen Now” above to see the full-screen text NexoLLM captures and uses as context.",
                            "Premi \(settings.prefs.captureShortcut.display) ovunque o clicca su “Leggi schermo ora” qui sopra per vedere il testo dell'intero schermo che NexoLLM acquisisce e usa come contesto.")
        let dotColor: Color = screen.isCapturing ? Theme.amber : (!screenText.isEmpty ? Theme.mint : Color.secondary.opacity(0.45))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(L("LIVE SCREEN TRANSCRIPT", "TRASCRIZIONE SCHERMO IN TEMPO REALE"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(L("Full Display", "Intero schermo"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                Spacer(minLength: 8)
                Button(screen.isCapturing ? L("Reading…", "Lettura…") : L("Read Screen Now", "Leggi schermo ora")) {
                    if !CGPreflightScreenCaptureAccess() {
                        actions.requestScreenRecording()
                    } else {
                        screen.captureNowForMonitor()
                    }
                }
                .controlSize(.small)
                .disabled(screen.isCapturing)
                Button(L("Clear", "Svuota")) {
                    screen.removeAll()
                    tick += 1
                }
                .controlSize(.small)
                .disabled(screenText.isEmpty)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L("What NexoLLM has read from your screen:", "Cosa ha appreso NexoLLM dallo schermo:"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !screenText.isEmpty {
                        Text(statsLabel)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                ScrollView {
                    Text(screenText.isEmpty ? placeholder : screenText)
                        .font(.system(size: 11.5, design: screenText.isEmpty ? .default : .monospaced))
                        .foregroundStyle(screenText.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 68, maxHeight: 135)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
    }

    private var audioTranscriptMonitor: some View {
        let wordCount = audio.transcript.split(whereSeparator: \.isWhitespace).count
        let wordsLabel = "\(wordCount) " + L("words", "parole")
        let levelPct = Int((audio.inputLevel * 100).rounded())
        let statusLine = audio.isListening
            ? L("Level \(levelPct)% · \(audio.packetCount) frames",
                "Livello \(levelPct)% · \(audio.packetCount) pacchetti")
            : (audio.statusText.isEmpty ? L("Audio stopped", "Ascolto fermo") : audio.statusText)
        let placeholder = audio.isListening
            ? L("Listening to room voices and online calls — words will appear here as NexoLLM hears and understands them…",
                "In ascolto di voci nella stanza e call online — le parole appariranno qui man mano che NexoLLM le sente e le comprende…")
            : L("Click “Start Listening” above to see what NexoLLM hears from your room or online calls in real time.",
                "Clicca su “Avvia ascolto” qui sopra per vedere cosa sente e trascrive NexoLLM dalla stanza o dalle call online in tempo reale.")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(audio.isListening ? Theme.mint : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8)
                Text(L("LIVE AUDIO TRANSCRIPT", "TRASCRIZIONE AUDIO IN TEMPO REALE"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(audio.capturesSystemAudio ? L("Room + Calls", "Ambiente + Call") : L("Room", "Ambiente"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Theme.mint.opacity(0.14)))
                if !audio.recognizerLocale.isEmpty {
                    Text(audio.recognizerLocale)
                        .font(.system(size: 9.5, weight: .semibold).monospaced())
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                }
                Spacer(minLength: 8)
                Menu {
                    Button(L("Automatic (Multilingual)", "Automatico (Multilingua)")) { audio.overrideLocale = nil }
                    Divider()
                    ForEach(AudioContext.speechLocales, id: \.locale) { item in
                        Button("\(item.flag) \(item.label)") { audio.overrideLocale = item.locale }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.system(size: 10))
                        Text(audio.overrideLocale.flatMap { loc in
                            AudioContext.speechLocales.first { $0.locale == loc || $0.iso == String(loc.prefix(2)).lowercased() }?.label ?? loc
                        } ?? L("Auto", "Auto")).font(.system(size: 10.5, weight: .medium))
                    }
                }
                .controlSize(.small)
                Button(settings.prefs.micContextEnabled ? L("Stop Listening", "Ferma ascolto") : L("Start Listening", "Avvia ascolto")) {
                    settings.prefs.micContextEnabled.toggle()
                }
                .controlSize(.small)
                Button(L("Clear", "Svuota")) {
                    audio.clear()
                    tick += 1
                }
                .controlSize(.small)
                .disabled(audio.transcript.isEmpty)
            }

            HStack(spacing: 10) {
                Image(systemName: audio.isListening ? "waveform" : "mic.slash")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(audio.isListening ? Theme.accent : .secondary)
                    .frame(width: 16)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(audio.inputLevel > 0.65 ? Theme.mint : Theme.accent)
                            .frame(width: max(4, geo.size.width * CGFloat(audio.inputLevel)))
                            .animation(.easeOut(duration: 0.08), value: audio.inputLevel)
                    }
                }
                .frame(height: 6)
                Text(statusLine)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(L("What NexoLLM hears & transcribes live:", "Cosa sente e trascrive NexoLLM in tempo reale:"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !audio.transcript.isEmpty {
                        Text(wordsLabel)
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                ScrollView {
                    Text(audio.transcript.isEmpty ? placeholder : audio.transcript)
                        .font(.system(size: 12, design: audio.transcript.isEmpty ? .default : .monospaced))
                        .foregroundStyle(audio.transcript.isEmpty ? .tertiary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 68, maxHeight: 120)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8))
                if audio.isListening {
                    Label(L("Transcribed on this computer by Whisper. Audio is never saved or sent.",
                            "Trascritto su questo computer da Whisper. L'audio non viene mai salvato né inviato."),
                          systemImage: "lock.fill")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
    }

    @ViewBuilder private var audioPluginSection: some View {
        Text(L("Uses what is said in the room (a lecture, a meeting) or in a call as context for your suggestions. Speech is transcribed by Whisper on this computer: no audio or text leaves it, and audio is never saved. This plugin is optional and not installed with the app.",
               "Usa ciò che viene detto nella stanza (una lezione, una riunione) o in una call come contesto per i suggerimenti. Il parlato è trascritto da Whisper su questo computer: né l'audio né il testo escono da qui, e l'audio non viene mai salvato. Il plugin è facoltativo e non è installato con l'app."))
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if let p = plugin.progress {
            SettingRow(plugin.verifying ? L("Verifying the download…", "Verifica del download…") : L("Downloading the speech model…", "Download del modello vocale…"),
                       detail: "\(Int((p * 100).rounded()))%") {
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 140)
                    Button(L("Cancel", "Annulla")) { plugin.cancel() }
                }
            }
        } else if let m = plugin.installed, plugin.hasConsent {
            ToggleRow(L("Listen to the room & online calls", "Ascolta la stanza e le call online"),
                      L("Always off when NexoLLM starts. Stops by itself when the screen locks, the computer sleeps or after an hour without typing. While listening, the menu bar icon can't be hidden.",
                        "Sempre spento all'avvio di NexoLLM. Si ferma da solo quando lo schermo si blocca, il computer va in stop o dopo un'ora senza scrivere. Durante l'ascolto l'icona nella barra dei menu non può essere nascosta."),
                      isOn: $settings.prefs.micContextEnabled)
            SettingRow(L("Plugin", "Plugin"), detail: "\(m.name) · \(Fmt.bytes(m.bytes))") {
                HStack(spacing: 8) {
                    Button(L("Legal Notice", "Note legali")) { showConsent = true }
                    Button(L("Remove Plugin", "Rimuovi plugin")) { confirmRemove = true }
                }
            }
            audioTranscriptMonitor
        } else {
            SettingRow(L("Not installed", "Non installato"),
                       L("Read the legal notice, then choose a speech model to download (190–575 MB).",
                         "Leggi le note legali, poi scegli un modello vocale da scaricare (190–575 MB)."),
                       detail: L("Optional plugin", "Plugin facoltativo")) {
                Button(L("Install Plugin…", "Installa plugin…")) { showConsent = true }
            }
        }
        if let e = plugin.error {
            Text(e).font(.caption).foregroundStyle(Theme.rose).fixedSize(horizontal: false, vertical: true)
        }
        if !audio.statusText.isEmpty, !audio.isListening {
            Text(audio.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The legal notice of the Audio Context plugin. Both statements must be ticked before anything is downloaded.
struct AudioPluginConsentSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var plugin = AudioPlugin.shared
    @State private var understood = AudioPlugin.shared.hasConsent
    @State private var lawful = AudioPlugin.shared.hasConsent
    @State private var choice = AudioPlugin.turbo

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.mic").font(.system(size: 22)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Audio Context · Legal notice", "Contesto audio · Note legali")).font(.system(size: 16, weight: .semibold))
                    Text(L("Experimental plugin", "Plugin sperimentale")).font(.caption).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    section(L("How it works", "Come funziona"),
                            L("Speech from the microphone (and, when screen and audio capture is allowed, from calls and videos) is transcribed by Whisper on this computer. No audio and no transcript is ever sent anywhere. Audio stays in memory only for the few seconds needed to transcribe it and is then overwritten; it is never written to disk. The transcript (about the last minute) is kept in memory only and is erased when listening stops, the screen locks or the computer sleeps.",
                              "Il parlato del microfono (e, se la cattura di schermo e audio è consentita, di call e video) viene trascritto da Whisper su questo computer. Nessun audio e nessuna trascrizione vengono mai inviati altrove. L'audio resta in memoria solo per i pochi secondi necessari a trascriverlo e poi viene sovrascritto; non viene mai scritto su disco. La trascrizione (circa l'ultimo minuto) resta solo in memoria e viene cancellata quando l'ascolto si ferma, lo schermo si blocca o il computer va in stop."))
                    section(L("Your responsibility", "La tua responsabilità"),
                            L("Recording or transcribing other people's voices may be subject to privacy and consent rules where you are. Use the plugin for your own voice, for public content, when the people speaking are informed and agree, or when you have an appropriate authorization (for example from your school, university or employer). Never use it to capture conversations covertly or conversations you are not part of.",
                              "Registrare o trascrivere la voce di altre persone può essere soggetto a regole su privacy e consenso nel luogo in cui ti trovi. Usa il plugin per la tua voce, per contenuti pubblici, quando chi parla è informato ed è d'accordo, o quando hai un'autorizzazione adeguata (ad esempio della scuola, dell'università o del datore di lavoro). Non usarlo mai per catturare conversazioni di nascosto o conversazioni di cui non fai parte."))
                    section(L("Built-in safeguards", "Tutele integrate"),
                            L("Listening is always off when NexoLLM starts. While it's on, the status icon stays visible and can't be hidden, next to the system's own microphone indicator. Listening stops by itself when the screen locks, when the computer sleeps or after an hour without typing. You can clear the transcript or remove the plugin at any time.",
                              "L'ascolto è sempre spento all'avvio di NexoLLM. Mentre è attivo, l'icona di stato resta visibile e non può essere nascosta, accanto all'indicatore del microfono del sistema. L'ascolto si ferma da solo quando lo schermo si blocca, quando il computer va in stop o dopo un'ora senza scrivere. Puoi svuotare la trascrizione o rimuovere il plugin in qualsiasi momento."))
                }
                .padding(.trailing, 6)
            }
            .frame(height: 250)
            Toggle(isOn: $understood) {
                Text(L("I understand that audio is processed only on this computer, never saved and never sent.",
                       "Ho capito che l'audio è elaborato solo su questo computer, mai salvato e mai inviato."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: $lawful) {
                Text(L("I will use it only for my own voice, for public content, or when the people speaking are informed and agree.",
                       "Lo userò solo per la mia voce, per contenuti pubblici, o quando chi parla è informato ed è d'accordo."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if plugin.installed == nil {
                Picker(L("Speech model", "Modello vocale"), selection: $choice) {
                    ForEach(AudioPlugin.models) { m in
                        Text("\(m.name) · \(Fmt.bytes(m.bytes)) — \(m.detail)").tag(m)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            HStack {
                Spacer()
                Button(L("Cancel", "Annulla")) { isPresented = false }
                Button(plugin.installed == nil ? L("Agree & Download", "Accetto e scarica") : L("Agree", "Accetto")) {
                    plugin.recordConsent()
                    if plugin.installed == nil { plugin.install(choice) }
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!(understood && lawful))
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
