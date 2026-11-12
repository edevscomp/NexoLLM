import AppKit
import SwiftUI

/// In-app cards shown over the Settings window, which blurs behind them.
enum AppModal: Identifiable, Equatable {
    case whatsNew, bugReport, privacy, walkthrough, crashReport
    var id: Self { self }
}

final class ModalCenter: ObservableObject {
    static let shared = ModalCenter()
    @Published var current: AppModal?
}

struct ModalHost: View {
    let modal: AppModal
    var actions = SettingsActions.none

    var body: some View {
        let tour = modal == .walkthrough
        ZStack {
            Color.black.opacity(tour ? 0.52 : 0.32).ignoresSafeArea()
                .onTapGesture { if !tour { ModalCenter.shared.current = nil } }   // a stray click never ends the tour
            Group {
                switch modal {
                case .whatsNew: WhatsNewCard()
                case .bugReport: BugReportCard()
                case .privacy: PrivacyCard()
                case .walkthrough: WalkthroughCard(actions: actions)
                case .crashReport: CrashReportCard()
                }
            }
            .frame(width: tour ? 620 : 520)
            .fixedSize(horizontal: false, vertical: tour)   // the tour card follows each slide's height
            .frame(maxHeight: tour ? nil : 540)
            .padding(26)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.38), radius: 36, y: 16)
            .tint(Theme.accent)
            .buttonStyle(GlassButtonStyle())
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

private func close() { ModalCenter.shared.current = nil }

private struct CardHeader: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            SidebarIcon(symbol: symbol, color: Theme.accent, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }
}

// MARK: - What's New

private struct WhatsNewCard: View {
    /// CHANGELOG section as headings and paragraphs.
    private var blocks: [(heading: Bool, text: String)] {
        var out: [(Bool, String)] = []
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append((false, para.joined(separator: " "))); para = [] } }
        for raw in (WhatsNew.notes ?? "").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") { flush(); out.append((true, String(line.dropFirst(4)))) }
            else if line.isEmpty { flush() }
            else if line.hasPrefix("- ") { flush(); para = ["• " + line.dropFirst(2)] }
            else { para.append(line) }
        }
        flush()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(symbol: "sparkles", title: L("What's New", "Novità"), subtitle: "\(Brand.name) \(Brand.version)")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if blocks.isEmpty { Text(L("Bug fixes and improvements.", "Correzioni e miglioramenti.")).foregroundStyle(.secondary) }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        if b.heading {
                            Text(b.text).font(.system(size: 13.5, weight: .semibold)).padding(.top, 4)
                        } else {
                            Text((try? AttributedString(markdown: b.text)) ?? AttributedString(b.text))
                                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button(L("Got It", "Ho capito"), action: close).keyboardShortcut(.defaultAction) }
        }
    }
}

// MARK: - Report a bug

private struct BugReportCard: View {
    @State private var category = BugReportCard.categories[0]
    @State private var details = ""
    @State private var includeSystem = true
    @State private var copied = false
    private static var categories: [String] {
        [L("Suggestions", "Suggerimenti"), L("Interface", "Interfaccia"), L("Performance", "Prestazioni"), L("Other", "Altro")]
    }

    private var systemInfo: String {
        """
        \(Brand.name) \(Brand.version) (\(Brand.build))
        \(HardwareProfile.current.summary)
        System \(ProcessInfo.processInfo.operatingSystemVersionString)
        Engine: \(AppStatus.shared.engine)
        """
    }

    private var report: String {
        "\(Brand.name) bug report\nCategory: \(category)\n\n\(details.trimmingCharacters(in: .whitespacesAndNewlines))"
            + (includeSystem ? "\n\n---\n\(systemInfo)" : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "ladybug", title: L("Report a Bug", "Segnala un bug"),
                       subtitle: L("Nothing is sent. Copy or save the report and share it.", "Non viene inviato nulla. Copia o salva il resoconto e condividilo."))
            GlassSegmentedPicker(selection: $category, options: Self.categories) { $0 }
            TextEditor(text: $details)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(alignment: .topLeading) {
                    if details.isEmpty {
                        Text(L("What happened, and what did you expect?", "Cosa è successo, e cosa ti aspettavi?"))
                            .font(.system(size: 12.5)).foregroundStyle(.tertiary).padding(13).allowsHitTesting(false)
                    }
                }
            Toggle(L("Include version, system and model", "Includi versione, sistema e modello"), isOn: $includeSystem)
            if includeSystem {
                Text(systemInfo).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            HStack {
                Button(L("Cancel", "Annulla"), action: close)
                Spacer()
                Button(L("Save…", "Salva…"), action: save)
                Button(copied ? L("Copied", "Copiato") : L("Copy Report", "Copia resoconto")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
            }
            .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(Brand.name) Bug Report.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Privacy & license

private struct PrivacyCard: View {
    @ObservedObject private var settings = Settings.shared
    @State private var showLicense = false

    private static var points: [(symbol: String, title: String, text: String)] { [
        ("cpu", L("AI computed on this computer", "IA calcolata su questo computer"),
         L("Suggestions, rewrites, translations, summaries, screen reading and the optional audio plugin all run on this computer. What you write is never sent to an AI service.",
           "Suggerimenti, riscritture, traduzioni, riassunti, lettura dello schermo e il plugin audio facoltativo girano tutti su questo computer. Ciò che scrivi non viene mai inviato a un servizio di IA.")),
        ("lock.fill", L("Encrypted", "Cifrato"),
         L("Your history and memories are encrypted with AES-256. The key stays in your Keychain and is cleared from memory when the screen locks.",
           "Cronologia e memorie sono cifrate con AES-256. La chiave resta nel Portachiavi e viene cancellata dalla memoria quando lo schermo si blocca.")),
        ("eye.slash", L("Secrets skipped", "Segreti esclusi"),
         L("Password fields are never read. Text with a password, API key, card number or IBAN is never saved.",
           "I campi password non vengono mai letti. Il testo con password, chiavi API, numeri di carta o IBAN non viene mai salvato.")),
        ("antenna.radiowaves.left.and.right.slash", L("No tracking", "Nessun tracciamento"),
         L("No analytics, no account. \(Brand.name) connects only to download what you choose (models, plugin), to check GitHub for signed updates, and for Web Lookup when you press its shortcut.",
           "Niente analisi, niente account. \(Brand.name) si collega solo per scaricare ciò che scegli (modelli, plugin), per cercare su GitHub aggiornamenti firmati e per la ricerca web quando premi la sua scorciatoia.")),
        ("chevron.left.forwardslash.chevron.right", L("Open source", "Open source"),
         L("The full source code is public under the GNU GPL v3: anyone can check exactly what \(Brand.name) does.",
           "Il codice sorgente completo è pubblico con licenza GNU GPL v3: chiunque può verificare esattamente cosa fa \(Brand.name).")),
    ] }

    private var license: String {
        let raw = Bundle.main.url(forResource: "LICENSE", withExtension: nil).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? Brand.copyright
        return raw
            .components(separatedBy: "\n\n")
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "lock.shield", title: L("Privacy & License", "Privacy e licenza"),
                       subtitle: L("On-device AI · No data collection · GNU GPL v3", "IA sul dispositivo · Nessuna raccolta dati · GNU GPL v3"))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.mint)
                        Text(L("What you type, your screen and audio are processed on this computer and never collected, analyzed elsewhere or sold. Writing works without any connection; only downloads, update checks and Web Lookup use the network.",
                               "Ciò che scrivi, lo schermo e l'audio sono elaborati su questo computer e mai raccolti, analizzati altrove o venduti. La scrittura funziona senza connessione; solo download, controllo aggiornamenti e ricerca web usano la rete."))
                            .font(.system(size: 12, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.mint.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.mint.opacity(0.25), lineWidth: 1))
                    ForEach(Self.points, id: \.title) { p in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: p.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.system(size: 13, weight: .semibold))
                                Text(p.text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    DisclosureGroup(L("License", "Licenza"), isExpanded: $showLicense) {
                        Text(license)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.trailing, 4)
            }
            HStack { Spacer(); Button(L("Done", "Fine"), action: close).keyboardShortcut(.defaultAction) }
        }
    }
}

// MARK: - Crash report

private struct CrashReportCard: View {
    @ObservedObject private var crash = CrashReporter.shared
    @State private var copied = false

    private var text: String { crash.pendingReport ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "exclamationmark.triangle.fill",
                       title: L("Previous Session Ended Unexpectedly", "La sessione precedente si è chiusa in modo anomalo"),
                       subtitle: L("Nothing is sent automatically. You can inspect, copy or save this local diagnostic report.",
                                   "Non viene inviato nulla in automatico. Puoi controllare, copiare o salvare questo resoconto diagnostico locale."))
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            HStack {
                Button(L("Dismiss", "Chiudi")) { crash.dismiss(); close() }
                Spacer()
                Button(L("Save…", "Salva…")) {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "\(Brand.name) Crash Report.txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                Button(copied ? L("Copied", "Copiato") : L("Copy Report", "Copia resoconto")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Interactive tour

extension SettingsActions {
    /// No-op actions (previews, renders).
    static let none = SettingsActions(reloadModel: {}, openAccessibilitySettings: {}, requestScreenRecording: {}, revealModels: {})
}

/// The tour's sample text in one language.
struct TourExamples {
    let to: String, subject: String
    /// The sample message: the tour opens with its greeting typed ("Hi Alex,") and the rest suggested.
    let target: String
    /// Suggested once the sample message is complete.
    let followUp: String
    let altLead: String, altWords: [String], altWordTail: String, altPhrases: [String]
    let styleSample: String, chips: [String]
    let mailFact: String, slackPrefix: String, slackGhost: String
    let original: String, rewrites: [(title: String, text: String)]

    /// "Hi Alex," / "Ciao Marco,".
    var sampleStart: String { String(target.prefix { $0 != "," }) + "," }

    static func `for`(_ lang: ExampleLanguage) -> TourExamples {
        switch lang {
        case .english: return english
        case .italian: return italian
        case .spanish: return spanish
        case .french: return french
        case .german: return german
        case .portuguese: return portuguese
        }
    }

    static let english = TourExamples(
        to: "To: Alex Rivera", subject: "Subject: Friday launch",
        target: "Hi Alex, just following up on the launch timeline for Friday at 3 PM.",
        followUp: " Let me know if Friday at 3 PM works for you.",
        altLead: "Hi Alex, just following up on the launch timeline for ",
        altWords: ["Friday", "Monday", "tomorrow", "next week"], altWordTail: " at 3 PM.",
        altPhrases: ["Friday afternoon at the office", "Monday morning on Zoom", "right after the client call", "whenever works best for you"],
        styleSample: "“Hey Alex! Sending the deck over real quick, let me know what you think. Cheers, Edo”",
        chips: ["Hey Alex!", "real quick", "let me know", "Cheers"],
        mailFact: "Q3 budget confirmed at $45,000 for the September launch",
        slackPrefix: "For the September launch the budget is ", slackGhost: "$45,000, as confirmed by email.",
        original: "Hey Alex, wanna catch up tomorrow about the project?",
        rewrites: [("Improve Writing", "Hi Alex, could we catch up tomorrow about the project?"),
                   ("Make Formal", "Dear Alex, would you be available tomorrow to discuss the project?"),
                   ("Make Shorter", "Alex, sync tomorrow on the project?"),
                   ("Translate IT", "Ciao Alex, ci sentiamo domani per parlare del progetto?")])

    static let italian = TourExamples(
        to: "A: Marco Rossi", subject: "Oggetto: Riunione di domani",
        target: "Ciao Marco, ti scrivo per confermare che ci vediamo domani alle 15.",
        followUp: " Fammi sapere se per te va bene.",
        altLead: "Ciao Marco, ti scrivo per confermare che ci vediamo ",
        altWords: ["domani", "venerdì", "stasera", "lunedì"], altWordTail: " alle 15.",
        altPhrases: ["domani alle 15 in ufficio", "venerdì mattina su Meet", "appena finisco la call", "nel pomeriggio se ti va"],
        styleSample: "“Ciao Marco! Ti giro al volo il documento, fammi sapere. Un caro saluto, Edo”",
        chips: ["Ciao Marco!", "al volo", "fammi sapere", "Un caro saluto"],
        mailFact: "Budget Q3 confermato a 45.000€ per il lancio di settembre",
        slackPrefix: "Per il lancio di settembre il budget è ", slackGhost: "45.000€, come confermato via mail.",
        original: "Ciao Marco, ci becchiamo domani per parlare del progetto?",
        rewrites: [("Migliora il testo", "Ciao Marco, possiamo vederci domani per parlare del progetto?"),
                   ("Rendi formale", "Gentile Marco, sarebbe possibile incontrarci domani per discutere del progetto?"),
                   ("Accorcia", "Marco, ci vediamo domani per il progetto?"),
                   ("Traduci EN", "Hi Marco, shall we meet tomorrow to talk about the project?")])

    static let spanish = TourExamples(
        to: "Para: Lucía Martín", subject: "Asunto: Reunión de mañana",
        target: "Hola Lucía, te escribo para confirmar que nos vemos mañana a las 15:00.",
        followUp: " Avísame si te viene bien.",
        altLead: "Hola Lucía, te escribo para confirmar que nos vemos ",
        altWords: ["mañana", "el viernes", "esta tarde", "el lunes"], altWordTail: " a las 15:00.",
        altPhrases: ["mañana a las 15:00 en la oficina", "el viernes por la mañana en Meet", "en cuanto termine la llamada", "cuando mejor te venga"],
        styleSample: "“¡Hola Lucía! Te paso rápido el documento, dime qué te parece. Un abrazo, Edo”",
        chips: ["¡Hola Lucía!", "te paso rápido", "dime qué te parece", "Un abrazo"],
        mailFact: "Presupuesto Q3 confirmado en 45.000 € para el lanzamiento de septiembre",
        slackPrefix: "Para el lanzamiento de septiembre el presupuesto es de ", slackGhost: "45.000 €, según lo confirmado por correo.",
        original: "Hola Lucía, ¿quedamos mañana un rato para ver el proyecto?",
        rewrites: [("Mejorar texto", "Hola Lucía, ¿podemos reunirnos mañana para revisar el proyecto?"),
                   ("Hacer formal", "Estimada Lucía, ¿estaría disponible mañana para comentar el proyecto?"),
                   ("Acortar", "Lucía, ¿vemos mañana el proyecto?"),
                   ("Traducir EN", "Hi Lucía, could we meet tomorrow to review the project?")])

    static let french = TourExamples(
        to: "À : Camille Laurent", subject: "Objet : Réunion de demain",
        target: "Bonjour Camille, je vous écris pour confirmer notre rendez-vous demain à 15 h.",
        followUp: " Dites-moi si cet horaire vous convient.",
        altLead: "Bonjour Camille, je vous écris pour confirmer notre rendez-vous ",
        altWords: ["demain", "vendredi", "lundi", "ce soir"], altWordTail: " à 15 h.",
        altPhrases: ["demain à 15 h au bureau", "vendredi matin sur Meet", "juste après l'appel client", "au moment qui vous arrange"],
        styleSample: "« Salut Camille ! Je t'envoie vite le document, dis-moi ce que tu en penses. À très vite, Edo »",
        chips: ["Salut Camille !", "je t'envoie vite", "dis-moi", "À très vite"],
        mailFact: "Budget T3 confirmé à 45 000 € pour le lancement de septembre",
        slackPrefix: "Pour le lancement de septembre, le budget est de ", slackGhost: "45 000 €, comme confirmé par e-mail.",
        original: "Salut Camille, on se voit demain pour parler du projet ?",
        rewrites: [("Améliorer", "Bonjour Camille, pourrions-nous faire le point demain sur le projet ?"),
                   ("Rendre formel", "Chère Camille, seriez-vous disponible demain afin d'échanger sur le projet ?"),
                   ("Raccourcir", "Camille, point projet demain ?"),
                   ("Traduire EN", "Hi Camille, could we catch up tomorrow about the project?")])

    static let german = TourExamples(
        to: "An: Lukas Weber", subject: "Betreff: Treffen morgen",
        target: "Hallo Lukas, ich schreibe kurz, um unser Treffen morgen um 15 Uhr zu bestätigen.",
        followUp: " Sag mir bitte Bescheid, ob dir das passt.",
        altLead: "Hallo Lukas, ich schreibe kurz, um unser Treffen ",
        altWords: ["morgen", "am Freitag", "am Montag", "heute Abend"], altWordTail: " um 15 Uhr zu bestätigen.",
        altPhrases: ["morgen Nachmittag im Büro zu bestätigen", "am Freitagvormittag per Videoanruf zu planen", "direkt nach dem Kundengespräch anzusetzen", "wann immer es dir am besten passt zu vereinbaren"],
        styleSample: "„Hey Lukas! Ich schicke dir kurz die Unterlagen rüber, gib mir gern Bescheid. Viele Grüße, Edo“",
        chips: ["Hey Lukas!", "kurz rüber", "gib mir Bescheid", "Viele Grüße"],
        mailFact: "Q3-Budget von 45.000 € für den Start im September bestätigt",
        slackPrefix: "Für den Start im September liegt das Budget bei ", slackGhost: "45.000 €, wie per E-Mail bestätigt.",
        original: "Hey Lukas, wollen wir morgen kurz über das Projekt quatschen?",
        rewrites: [("Verbessern", "Hallo Lukas, können wir uns morgen kurz zum Projekt austauschen?"),
                   ("Formell", "Guten Tag Lukas, hätten Sie morgen Zeit, das Projekt gemeinsam zu besprechen?"),
                   ("Kürzen", "Lukas, morgen kurzes Projekt-Update?"),
                   ("Übersetzen EN", "Hi Lukas, can we catch up briefly tomorrow about the project?")])

    static let portuguese = TourExamples(
        to: "Para: Sofia Costa", subject: "Assunto: Reunião de amanhã",
        target: "Olá Sofia, escrevo para confirmar que nos encontramos amanhã às 15h.",
        followUp: " Diz-me se este horário te dá jeito.",
        altLead: "Olá Sofia, escrevo para confirmar que nos encontramos ",
        altWords: ["amanhã", "sexta-feira", "segunda-feira", "logo à tarde"], altWordTail: " às 15h.",
        altPhrases: ["amanhã às 15h no escritório", "sexta-feira de manhã no Meet", "assim que terminar a chamada", "quando te for mais conveniente"],
        styleSample: "«Olá Sofia! Envio-te já o documento, diz-me o que achas. Um abraço, Edo»",
        chips: ["Olá Sofia!", "envio-te já", "diz-me o que achas", "Um abraço"],
        mailFact: "Orçamento do 3.º trimestre confirmado em 45.000 € para o lançamento de setembro",
        slackPrefix: "Para o lançamento de setembro, o orçamento é de ", slackGhost: "45.000 €, conforme confirmado por e-mail.",
        original: "Olá Sofia, falamos amanhã um bocado sobre o projeto?",
        rewrites: [("Melhorar texto", "Olá Sofia, podemos reunir amanhã para falar sobre o projeto?"),
                   ("Tornar formal", "Cara Sofia, teria disponibilidade amanhã para analisarmos o projeto?"),
                   ("Encurtar", "Sofia, falamos amanhã sobre o projeto?"),
                   ("Traduzir EN", "Hi Sofia, can we meet tomorrow to discuss the project?")])
}

/// The tour's state. Slides 2–5 are scripted, instant demos: nothing touches the model, the history or other apps.
final class WalkthroughState: ObservableObject {
    enum Slide: Int { case welcome, setup, autocomplete, alternatives, memory, rewrite, webLookup, moreFeatures, done }

    static let shownKey = "walkthrough.v2.shown"
    static let stepCount = 9

    @Published var step = 0
    /// Direction of the last move, so slides enter from the right going forward and from the left going back.
    @Published var forward = true
    @Published private(set) var lang: ExampleLanguage
    @Published private(set) var typed = ""
    @Published private(set) var ghost = ""
    @Published private(set) var hasAcceptedOnce = false
    @Published private(set) var scope = AlternativesScope.word
    @Published private(set) var selected = 0
    @Published private(set) var chosen: String
    @Published private(set) var chosenIsPhrase = false
    @Published private(set) var memoryAccepted = false
    @Published private(set) var rewrite: Int?
    /// Off in tests and renders.
    var clicks = true
    /// The follow-up sentence arrives after a short beat, like a real suggestion. Off in tests and renders.
    var animated = true
    private var followedUp = false

    init(lang: ExampleLanguage = Settings.shared.prefs.exampleLanguage) {
        self.lang = lang
        chosen = TourExamples.for(lang).altWords[0]
        reset()
    }

    var ex: TourExamples { .for(lang) }
    var slide: Slide { Slide(rawValue: step) ?? .welcome }
    var items: [String] { scope == .word ? ex.altWords : ex.altPhrases }
    var nextWord: String { SuggestionText.splitNextWord(ghost, trailingSpace: false).word }
    var sentenceTail: String { chosenIsPhrase ? "." : ex.altWordTail }

    static func markShown() { UserDefaults.standard.set(true, forKey: shownKey) }

    private func click() { if clicks { KeyClickSound.play(force: true) } }

    func next() { forward = true; step = min(step + 1, Self.stepCount - 1) }
    func back() { forward = false; step = max(step - 1, 0) }

    /// New sample text everywhere; the demos start over.
    func setLanguage(_ l: ExampleLanguage) {
        guard l != lang else { return }
        lang = l
        reset()
        scope = .word
        selected = 0
        chosen = ex.altWords[0]
        chosenIsPhrase = false
        memoryAccepted = false
        rewrite = nil
    }

    /// The sample message with its greeting typed and the rest suggested.
    func reset() {
        typed = ex.sampleStart
        ghost = String(ex.target.dropFirst(typed.count))
        followedUp = false
        hasAcceptedOnce = false
    }

    func acceptWord() {
        guard !ghost.isEmpty else { return }
        let (word, rest) = SuggestionText.splitNextWord(ghost, trailingSpace: false)
        typed += word
        ghost = rest
        accepted()
    }

    func acceptAll() {
        guard !ghost.isEmpty else { return }
        typed += ghost
        ghost = ""
        accepted()
    }

    /// Click; once the sample message is complete, the next sentence is suggested, like the real chaining.
    private func accepted() {
        hasAcceptedOnce = true
        click()
        guard ghost.isEmpty, !followedUp else { return }
        followedUp = true
        let next = ex.followUp
        guard animated else { ghost = next; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.followedUp, self.ghost.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.18)) { self.ghost = next }
        }
    }

    func toggleScope() {
        scope = scope == .word ? .phrase : .word
        selected = 0
        click()
    }

    func move(_ delta: Int) { selected = (selected + delta + items.count) % items.count }

    func pick(_ index: Int? = nil) {
        let i = index ?? selected
        guard items.indices.contains(i) else { return }
        selected = i
        chosen = items[i]
        chosenIsPhrase = scope == .phrase
        click()
    }

    func acceptMemory() {
        guard !memoryAccepted else { return }
        memoryAccepted = true
        click()
    }

    /// Silent: the Quick Menu doesn't click.
    func pickRewrite(_ i: Int) {
        guard ex.rewrites.indices.contains(i) else { return }
        rewrite = i
    }

    /// A key pressed while the tour is open; true when it was used (then it goes nowhere else).
    /// ↩, ⎋ and ⌘ shortcuts are left alone so Next, closing and the menu keep working.
    func handle(code: Int64, flags: CGEventFlags, characters: String?) -> Bool {
        let p = Settings.shared.prefs
        let digit: Int? = [18: 0, 19: 1, 20: 2, 21: 3][code]
        switch slide {
        case .autocomplete:
            if p.nextWordShortcut.matches(code, flags) { acceptWord(); return true }
            if p.fullCompletionShortcut.matches(code, flags) { acceptAll(); return true }
        case .alternatives:
            if p.alternativesShortcut.matches(code, flags) || code == 123 || code == 124 { toggleScope(); return true }
            if code == 125 || code == 126 { move(code == 125 ? 1 : -1); return true }
            if code == 36 || code == 48 { pick(); return true }
            if let digit { pick(digit); return true }
        case .memory:
            if !memoryAccepted, code == 48 || p.nextWordShortcut.matches(code, flags) || p.fullCompletionShortcut.matches(code, flags) {
                acceptMemory()
                return true
            }
        case .rewrite:
            if let digit { pickRewrite(digit); return true }
        default: break
        }
        return false
    }
}

struct WalkthroughCard: View {
    let actions: SettingsActions
    @StateObject private var tour: WalkthroughState
    @ObservedObject private var settings = Settings.shared
    @State private var monitor: Any?
    private let confetti: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var dots

    /// `previewStep` is for `--render-ui`: opens on that slide, without sounds, delays or confetti.
    init(actions: SettingsActions = .none, previewStep: Int? = nil) {
        self.actions = actions
        let state = WalkthroughState()
        if let previewStep {
            state.step = previewStep
            state.clicks = false
            state.animated = false
        }
        _tour = StateObject(wrappedValue: state)
        confetti = previewStep == nil
    }

    private var prefs: Prefs { settings.prefs }
    private var ex: TourExamples { tour.ex }
    private var isLast: Bool { tour.slide == .done }
    private var ghostColors: (head: Color, tail: Color) { GhostPalette.colors(scheme == .dark ? .dark : .light) }
    private var slideAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86) }

    var body: some View {
        VStack(spacing: 22) {
            ZStack(alignment: .top) {
                slideView
                    .id(tour.step)
                    .transition(.asymmetric(
                        insertion: .move(edge: tour.forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: tour.forward ? .leading : .trailing).combined(with: .opacity)))
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            // Room for buttons growing on hover, so the clip never cuts their border.
            .padding(.horizontal, 6).padding(.vertical, 4)
            .clipped()
            .padding(.horizontal, -6).padding(.vertical, -4)
            navBar
        }
        .overlay {
            if confetti, !reduceMotion, tour.slide == .welcome || tour.slide == .done {
                ConfettiBurst().id(tour.step).allowsHitTesting(false)
            }
        }
        .onChange(of: settings.prefs.exampleLanguage) { _, lang in withAnimation { tour.setLanguage(lang) } }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [tour] e in
                let used = withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tour.handle(code: Int64(e.keyCode), flags: e.cgEvent?.flags ?? [], characters: e.characters)
                }
                return used ? nil : e
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }

    @ViewBuilder private var slideView: some View {
        switch tour.slide {
        case .welcome: welcome
        case .setup: SetupSlide(actions: actions)
        case .autocomplete: autocomplete
        case .alternatives: alternatives
        case .memory: memory
        case .rewrite: rewriteSlide
        case .webLookup: webLookupSlide
        case .moreFeatures: moreFeaturesSlide
        case .done: done
        }
    }

    /// Sets the direction first (so the leaving slide exits the right way), then moves with a spring.
    private func go(to index: Int) {
        let i = max(0, min(index, WalkthroughState.stepCount - 1))
        guard i != tour.step else { return }
        tour.forward = i > tour.step
        DispatchQueue.main.async { withAnimation(slideAnimation) { tour.step = i } }
    }

    private func finish(click: Bool) {
        WalkthroughState.markShown()
        if click { KeyClickSound.play(force: true) }
        close()
    }

    // MARK: Navigation

    private var navBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(0..<WalkthroughState.stepCount, id: \.self) { i in
                    Button { go(to: i) } label: {
                        ZStack {
                            Capsule().fill(Color.primary.opacity(0.18)).frame(width: 6, height: 6)
                            if i == tour.step {
                                Capsule().fill(Theme.accent).frame(width: 20, height: 6)
                                    .matchedGeometryEffect(id: "dot", in: dots)
                            }
                        }
                        .frame(width: i == tour.step ? 20 : 6, height: 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                if tour.slide != .welcome, !isLast {
                    Button(L("Skip", "Salta")) { finish(click: false) }.lineLimit(1).fixedSize()
                }
                Spacer()
                if tour.step > 0, !isLast {
                    Button { go(to: tour.step - 1) } label: {
                        HStack(spacing: 5) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)); Text(L("Back", "Indietro")) }
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                Button { isLast ? finish(click: true) : go(to: tour.step + 1) } label: {
                    HStack(spacing: 5) {
                        Text(tour.slide == .welcome ? L("Get Started", "Inizia")
                             : isLast ? L("Start Using \(Brand.name)", "Inizia a usare \(Brand.name)") : L("Next", "Avanti"))
                        if !isLast { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
                .lineLimit(1)
                .fixedSize()
            }
        }
    }

    /// Instruction line where keys are drawn as accent key caps, like in the Quick Menu.
    private enum Seg { case t(String), k(String) }

    /// Wraps word by word (key caps never split), so a long translation stays inside the card.
    private func keyHint(_ font: Font = .callout, _ segs: Seg...) -> some View {
        let pieces: [Seg] = segs.flatMap { s -> [Seg] in
            if case .t(let text) = s { return text.split(separator: " ").map { .t(String($0)) } }
            return [s]
        }
        return FlowLayout(hSpacing: 4, vSpacing: 5, alignToBaseline: true) {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, s in
                switch s {
                case .t(let text): Text(text).fixedSize()
                case .k(let key): KeyCap(label: key, highlighted: true)
                }
            }
        }
        .font(font)
        .foregroundStyle(.secondary)
    }

    // MARK: Slides

    private var welcome: some View {
        VStack(spacing: 12) {
            BrandOrb(size: 64).padding(.top, 6)
            Text(L("Welcome to \(Brand.name)", "Benvenuto in \(Brand.name)")).font(.system(size: 24, weight: .semibold))
            Text(L("On-device autocomplete, alternatives and writing tools for every app on your computer.",
                   "Completamento automatico, alternative e strumenti di scrittura sul tuo computer, in ogni app."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Label(L("App language", "Lingua dell'app"), systemImage: "globe")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                LanguagePickerButton()
            }
            .padding(.top, 2)
            HStack(alignment: .top, spacing: 10) {
                feature("lock.shield", L("Private", "Privato"), L("The AI runs on this computer. What you type is never sent to an AI service.", "L'IA gira su questo computer. Ciò che scrivi non viene mai inviato a un servizio di IA."))
                feature("sparkles", L("Every app", "Ogni app"), L("Mail, Notes, Slack, Safari, Obsidian and more.", "Mail, Note, Slack, Safari, Obsidian e altre."))
                feature("brain.head.profile", L("Adapts to you", "Si adatta a te"), L("Learns your expressions and recent topics.", "Impara le tue espressioni e gli argomenti recenti."))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.12)))
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private var autocomplete: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "text.cursor", title: L("Suggestions as you type", "Suggerimenti mentre scrivi"),
                       subtitle: L("Works in every app: Mail, Notes, Slack, your browser.", "Funziona in ogni app: Mail, Note, Slack, il browser."))
            keyHint(.callout, .t(L("Press", "Premi")), .k(prefs.nextWordShortcut.display),
                    .t(L("to accept one word at a time, or", "per accettare una parola alla volta, oppure")),
                    .k(prefs.fullCompletionShortcut.display), .t(L("for the whole sentence.", "per tutta la frase.")))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) { Text(ex.to); Text(ex.subject) }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Divider()
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let caretOn = Int(ctx.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                    let head = tour.nextWord
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        (Text(tour.typed).foregroundColor(.primary)
                         + (tour.ghost.isEmpty ? Text("|").fontWeight(.light).foregroundColor(caretOn ? Theme.accent : .clear) : Text(""))
                         + Text(head).foregroundColor(ghostColors.head)
                         + Text(String(tour.ghost.dropFirst(head.count))).foregroundColor(ghostColors.tail))
                            .font(.system(size: 15))
                        if !tour.ghost.isEmpty {
                            KeyCap(label: prefs.nextWordShortcut.display, highlighted: true).transition(.opacity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            }
            .padding(14)
            .glassCard()
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1))
            HStack(spacing: 6) {
                if tour.hasAcceptedOnce {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
                    keyHint(.callout, .t(L("Great! Keep pressing", "Ottimo! Continua a premere")), .k(prefs.nextWordShortcut.display),
                            .t(L("or click", "oppure clicca")), .k(L("Next", "Avanti")))
                    Spacer()
                    Button(L("Reset", "Ricomincia")) { withAnimation { tour.reset() } }
                        .fixedSize()
                }
            }
            .frame(minHeight: 28)
        }
    }

    private var alternatives: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "list.bullet.rectangle", title: L("Alternatives", "Alternative"),
                       subtitle: L("Not quite the word you wanted? Pick another one.", "Non è la parola che volevi? Scegline un'altra."))
            VStack(alignment: .leading, spacing: 6) {
                keyHint(.callout, .t(L("Press", "Premi")), .k(prefs.alternativesShortcut.display), .t(L("or", "o")), .k("← →"),
                        .t(L("to switch between words and phrases.", "per passare tra parole e frasi.")))
                keyHint(.callout, .k("↑ ↓"), .t(L("to move,", "per spostarti,")), .k("↩"), .t(L("or", "o")), .k("1–4"),
                        .t(L("to pick.", "per scegliere.")))
            }
            (Text(ex.altLead) + Text(tour.chosen).bold().foregroundColor(Theme.accent) + Text(tour.sentenceTail))
                .font(.system(size: 15))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            HStack(alignment: .top) {
                ListPanelView(header: L("Alternatives", "Alternative"), items: tour.items.map { ListItem(leading: "", title: $0) },
                              scope: tour.scope, switchKey: prefs.alternativesShortcut.display, selected: tour.selected,
                              onSelect: { i in withAnimation(.spring(response: 0.3)) { tour.pick(i) } })
                    .frame(width: 340)
                Spacer()
                Button(tour.scope == .word ? L("Show Phrases", "Mostra frasi") : L("Show Words", "Mostra parole")) {
                    withAnimation(.spring(response: 0.3)) { tour.toggleScope() }
                }
                .fixedSize()
                .padding(.top, 14)
            }
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "brain.head.profile", title: L("Learns from you", "Impara da te"),
                       subtitle: L("Your style and recent topics, encrypted on this computer.", "Il tuo stile e gli argomenti recenti, cifrati su questo computer."))
            VStack(alignment: .leading, spacing: 8) {
                Label(L("Your style", "Il tuo stile"), systemImage: "person.text.rectangle").font(.system(size: 13, weight: .semibold))
                Text(ex.styleSample).font(.system(size: 12.5)).italic().foregroundStyle(.secondary)
                StyleChips(chips: ex.chips).id(tour.lang)
                Text(L("\(Brand.name) picks up your greetings, sign-offs and favourite expressions, so suggestions sound like you.",
                       "\(Brand.name) impara i tuoi saluti, le chiusure e le espressioni preferite, così i suggerimenti suonano come te."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L("Remembers topics across apps", "Ricorda gli argomenti tra le app"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Label("AES-256", systemImage: "lock.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.mint)
                }
                HStack(spacing: 8) {
                    Image(systemName: "envelope.fill").foregroundStyle(Theme.blue).frame(width: 18)
                    Text(L("Mail · 10 min ago", "Mail · 10 min fa")).font(.caption).foregroundStyle(.secondary)
                    Text(ex.mailFact).font(.system(size: 12.5)).lineLimit(1)
                }
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Image(systemName: "number").foregroundStyle(Theme.violet).frame(width: 18)
                    (Text(ex.slackPrefix)
                     + Text(ex.slackGhost).foregroundColor(tour.memoryAccepted ? .primary : ghostColors.tail))
                        .font(.system(size: 13))
                    if tour.memoryAccepted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint).transition(.scale)
                    } else {
                        KeyCap(label: prefs.nextWordShortcut.display, highlighted: true)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                HStack {
                    keyHint(.caption, .t(L("Now you're in Slack: press", "Ora sei su Slack: premi")), .k(prefs.nextWordShortcut.display),
                            .t(L("and \(Brand.name) fills in what you read in Mail.", "e \(Brand.name) completa con ciò che hai letto in Mail.")))
                    Spacer()
                    Button(L("Accept", "Accetta")) { withAnimation(.spring(response: 0.3)) { tour.acceptMemory() } }
                        .disabled(tour.memoryAccepted)
                        .fixedSize()
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard()
        }
    }

    private var rewriteSlide: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "command", title: L("Quick Menu & Writing Tools", "Menu rapido e Strumenti di scrittura"),
                       subtitle: L("Rewrite, polish, shorten or translate your paragraph in place.",
                                   "Riscrivi, correggi, rendi formale, accorcia o traduci il paragrafo sul posto."))
            VStack(alignment: .leading, spacing: 5) {
                keyHint(.callout, .k(prefs.quickMenuShortcut.display),
                        .t(L("opens the Quick Menu (1–8). Open Writing Tools (1 or →) and press",
                             "apre il menu rapido (1–8). Apri Strumenti di scrittura (1 o →) e premi")),
                        .k("⇧1–⇧5"),
                        .t(L("or click to improve, fix grammar, make formal, shorten or translate.",
                             "o clicca per migliorare, correggere, rendere formale, accorciare o tradurre.")))
            }
            Text(tour.rewrite.map { ex.rewrites[$0].text } ?? ex.original)
                .font(.system(size: 14.5))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.accent.opacity(0.22)))
                .id(tour.rewrite ?? -1)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            FlowLayout(hSpacing: 8, vSpacing: 8) {
                ForEach(Array(ex.rewrites.enumerated()), id: \.offset) { i, r in
                    Button { withAnimation(.spring(response: 0.35)) { tour.pickRewrite(i) } } label: {
                        HStack(spacing: 6) { KeyCap(label: "⇧\(i + 1)", highlighted: tour.rewrite == i); Text(r.title).lineLimit(1) }
                    }
                    .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var webLookupSlide: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "sparkle.magnifyingglass", title: L("Smart Web Lookup", "Ricerca Web intelligente"),
                       subtitle: L("Instant web search, definitions, idioms & fast AI summaries in any app.",
                                   "Ricerca web istantanea, definizioni, modi di dire e sunto veloce in qualsiasi app."))
            keyHint(.callout, .t(L("Press", "Premi")), .k(prefs.webLookupShortcut.display),
                    .t(L("in any app to look up selected text, drag over a screen region, or ask a question.",
                         "in qualsiasi app per cercare il testo evidenziato, selezionare un'area o fare una domanda.")))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "globe").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(L("WEB LOOKUP · FAST SUMMARY", "RICERCA WEB · SUNTO VELOCE"))
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Text(L("Online Search + AI", "Ricerca Online + IA"))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                }
                Text(L("“What does ‘avere il coltello dalla parte del manico’ mean?”",
                       "“Cosa significa ‘avere il coltello fra i denti’?”"))
                    .font(.system(size: 13.5, weight: .semibold))
                Text(L("It is an Italian idiom meaning to be in a position of advantage or control in a situation, or to face a challenge with fierce determination.",
                       "È un modo di dire italiano che indica l'affrontare una sfida, una gara o una situazione difficile con estrema grinta, determinazione e combattività."))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            HStack(alignment: .top, spacing: 10) {
                feature("highlighter", L("Highlight any text", "Evidenzia un testo"),
                        L("Select a word, idiom or message in any browser, chat or PDF and press \(prefs.webLookupShortcut.display) for an instant summary.",
                          "Evidenzia una parola, un modo di dire o un messaggio in browser, chat o PDF e premi \(prefs.webLookupShortcut.display) per un sunto immediato."))
                feature("viewfinder", L("Drag to select area", "Seleziona un'area"),
                        L("Nothing selected? Drag the crosshair over any part of your screen to read and search it.",
                          "Nulla di evidenziato? Trascina il mirino a croce su qualsiasi zona dello schermo per leggerla e cercarla."))
                feature("text.magnifyingglass", L("Ask anything", "Chiedi qualsiasi cosa"),
                        L("Type any question, topic or news query in the search bar for a fast online summary in your language.",
                          "Scrivi qualsiasi domanda, argomento o ricerca nella barra in alto per un sunto veloce online nella tua lingua."))
            }
        }
    }

    private var moreFeaturesSlide: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "sparkles.rectangle.stack", title: L("And There's Much More!", "E non c'è solo questo!"),
                       subtitle: L("Explore everything \(Brand.name) does in the background to speed up your workflow.",
                                   "Scopri tutto ciò che \(Brand.name) mette a tua disposizione per velocizzare il tuo lavoro."))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], spacing: 10) {
                feature("text.viewfinder", L("Full-Screen Context (\(prefs.captureShortcut.display))", "Contesto intero schermo (\(prefs.captureShortcut.display))"),
                        L("Reads active and side-by-side windows so completions match the documents you have open.",
                          "Legge la finestra attiva e quelle affiancate così i suggerimenti seguono i documenti che hai davanti."))
                feature("waveform.badge.mic", L("Ambient & Call Audio", "Audio ambientale e Call"),
                        L("Experimental live transcription of room voices and online meetings for real-time context.",
                          "Trascrizione live sperimentale delle voci nella stanza e delle call online per dare contesto in tempo reale."))
                feature("app.badge.checkmark", L("Per-App Rules", "Regole per singola app"),
                        L("Enable, pause, or customize \(Brand.name) individually for any app or terminal.",
                          "Attiva, metti in pausa o personalizza \(Brand.name) singolarmente per ogni applicazione o terminale."))
                feature("battery.100.bolt", L("Battery & 100% Offline", "Batteria e 100% Offline"),
                        L("Automatically switches to lighter models on battery; writing works without any connection.",
                          "Passa in automatico a modelli più leggeri a batteria; la scrittura funziona senza connessione."))
                feature("textformat.abc.dottedunderline", L("Smart Autocorrect & Emoji", "Autocorrezione ed Emoji"),
                        L("Fixes typos on Space, adds missing accents, and expands :shortcodes into emoji.",
                          "Corregge i refusi con Spazio, aggiunge gli accenti mancanti e trasforma :shortcode in emoji."))
                feature("arrow.clockwise.circle", L("Instant Service Restart (\(prefs.restartShortcut.display))", "Riavvio rapido servizi (\(prefs.restartShortcut.display))"),
                        L("Reloads accessibility hooks and the local AI engine at any time with a single shortcut.",
                          "Ricarica i permessi di accessibilità e il motore IA locale in qualsiasi momento con una scorciatoia."))
            }
        }
    }

    private var done: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Theme.mint))
                .padding(.top, 6)
            Text(L("All Done, You're Ready!", "Fatto, sei pronto!")).font(.system(size: 24, weight: .semibold))
            Text(L("\(Brand.name) lives in the menu bar. Start typing in any app.", "\(Brand.name) vive nella barra dei menu. Inizia a scrivere in qualsiasi app."))
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
                shortcut(prefs.nextWordShortcut.display, L("Accept the next word", "Accetta la parola successiva"))
                shortcut(prefs.fullCompletionShortcut.display, L("Accept the whole suggestion", "Accetta l'intero suggerimento"))
                shortcut(prefs.alternativesShortcut.display, L("Show alternatives", "Mostra alternative"))
                shortcut(prefs.quickMenuShortcut.display, L("Quick Menu & Writing Tools", "Menu rapido e scrittura"))
                shortcut(prefs.webLookupShortcut.display, L("Smart Web Lookup & Area OCR", "Ricerca Web e area schermo"))
                shortcut(prefs.captureShortcut.display, L("Read the Screen Now", "Leggi lo schermo ora"))
            }
            .padding(14)
            .glassCard()
            .padding(.top, 6)
            Button { NSWorkspace.shared.open(Brand.coffee) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "cup.and.saucer.fill").foregroundStyle(.primary)
                    Text(L("Support \(Brand.author) · Buy Me a Coffee", "Supporta \(Brand.author) · Offrimi un caffè"))
                        .font(.system(size: 12.5, weight: .semibold))
                }
            }
            .buttonStyle(GlassButtonStyle(capsule: true))
            .padding(.top, 4)
            Text(LocalizedStringKey(L("Replay this tour anytime with **Tour** at the top right of the window.",
                                      "Rivedi questo tour quando vuoi con **Tour** in alto a destra nella finestra.")))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func shortcut(_ key: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            KeyCap(label: key, highlighted: true)
            Text(text).font(.system(size: 12.5))
        }
    }
}

/// Slide 2: permissions, the system's inline predictions and the model, live. The recommended model comes first;
/// any other can be picked.
private struct SetupSlide: View {
    let actions: SettingsActions
    @ObservedObject private var models = ModelManager.shared
    @ObservedObject private var settings = Settings.shared
    @State private var axTrusted = AX.isTrusted(prompt: false)
    @State private var screen = CGPreflightScreenCaptureAccess()
    @State private var inlinePredictionOn = SystemTextPrefs.isOn(.inlinePrediction)
    @State private var picked = CatalogModel.all.first { $0 != HardwareProfile.current.recommended.pluggedIn } ?? CatalogModel.all[0]
    private let hardware = HardwareProfile.current

    var body: some View {
        let rec = hardware.recommended.pluggedIn
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(symbol: "lock.shield", title: L("Set up \(Brand.name)", "Configura \(Brand.name)"),
                       subtitle: L("One permission and a model, then you're ready.", "Un permesso e un modello, poi sei pronto."))
            VStack(spacing: 0) {
                row("hand.raised", L("Accessibility", "Accessibilità"),
                    L("Required. Reads the text around your cursor and types suggestions.", "Obbligatoria. Legge il testo intorno al cursore e scrive i suggerimenti.")) {
                    if axTrusted { StatusPill(text: L("Granted", "Concesso")).fixedSize() } else { Button(L("Grant Access", "Consenti")) { actions.openAccessibilitySettings() }.fixedSize() }
                }
                Divider()
                row("rectangle.dashed", L("Screen Recording", "Registrazione schermo"),
                    L("Optional. Reads the active window for extra context, on this computer.", "Facoltativa. Legge la finestra attiva per più contesto, su questo computer.")) {
                    if screen { StatusPill(text: L("Granted", "Concesso")).fixedSize() } else { Button(L("Grant Access", "Consenti")) { actions.requestScreenRecording() }.fixedSize() }
                }
                Divider()
                row("keyboard.badge.ellipsis", L("System inline predictions", "Suggerimenti inline di sistema"),
                    L("Recommended. Turn off the system's grey suggestions so they don't get in the way of \(Brand.name). You can turn them back on anytime in Overview.",
                      "Consigliato. Disattiva i suggerimenti grigi del sistema perché non interferiscano con \(Brand.name). Puoi riattivarli quando vuoi in Panoramica.")) {
                    HStack(spacing: 8) {
                        if !inlinePredictionOn { StatusPill(text: L("Off", "Disattivati")) }
                        Button(inlinePredictionOn ? L("Turn Off", "Disattiva") : L("Turn On Again", "Riattiva")) {
                            SystemTextPrefs.set(.inlinePrediction, on: !inlinePredictionOn)
                            inlinePredictionOn = SystemTextPrefs.isOn(.inlinePrediction)
                        }
                    }
                    .fixedSize()
                }
                Divider()
                row("shippingbox.fill", rec.name, "\(Fmt.bytes(rec.bytes)) · " + L("best for", "ideale per") + " \(hardware.summary)",
                    badge: L("Recommended", "Consigliato")) {
                    modelAction(rec) { models.applyRecommended() }.fixedSize()
                }
                Divider()
                row("square.stack.3d.down.right", L("Other models", "Altri modelli"),
                    L("Prefer another one? You can switch anytime in Models.", "Ne preferisci un altro? Puoi cambiarlo quando vuoi in Modelli.")) {
                    HStack(spacing: 8) {
                        GlassMenuPicker(selection: $picked, options: CatalogModel.all.filter { $0 != rec }.map { m -> (CatalogModel, String) in
                            (m, "\(m.name) · \(Fmt.bytes(m.bytes))\(m == hardware.recommended.battery ? " ★" : "")")
                        })
                        .frame(maxWidth: 200)
                        modelAction(picked) { models.download(picked, thenUseFor: false) }
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 14)
            .glassCard()
            Text(L("Downloads continue in the background, so you can keep going.", "I download continuano in background, puoi andare avanti."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .task {
            while !Task.isCancelled {
                axTrusted = AX.isTrusted(prompt: false)
                screen = CGPreflightScreenCaptureAccess()
                inlinePredictionOn = SystemTextPrefs.isOn(.inlinePrediction)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    /// Progress while downloading, "In use" / Use when installed, Download otherwise.
    @ViewBuilder private func modelAction(_ m: CatalogModel, download: @escaping () -> Void) -> some View {
        if let d = models.downloads[m.id] {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: d.fraction).frame(width: 110)
                Text(d.verifying ? L("Verifying…", "Verifica…") : "\(Int(d.fraction * 100))%")
                    .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
            }
        } else if let installed = models.installed(m) {
            if settings.prefs.modelPath == installed.path {
                StatusPill(text: L("In use", "In uso"))
            } else {
                Button(L("Use", "Usa")) { models.use(installed.path, battery: false) }
            }
        } else {
            Button(L("Download", "Scarica"), action: download)
                .disabled(!NetworkMonitor.shared.isOnline)
        }
    }

    private func row<A: View>(_ symbol: String, _ title: String, _ detail: String, badge: String? = nil,
                              @ViewBuilder accessory: () -> A) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    }
                }
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.vertical, 12)
    }
}

/// Filled accent button for the tour's main action, same shape and size as `GlassButtonStyle`.
private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(shape.fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}

/// One short burst of confetti in the palette colors; removes itself after 2.4 s (no idle animation).
private struct ConfettiBurst: View {
    private static let colors = [Theme.accent, Theme.mint, Theme.cyan, Theme.violet, Theme.amber, Theme.rose]
    private static let duration = 2.4
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        if !finished {
            TimelineView(.animation) { ctx in
                Canvas { g, size in
                    let t = ctx.date.timeIntervalSince(start)
                    let travel = (1 - exp(-2.4 * t)) / 2.4   // air drag
                    let alpha = min(1, max(0, (Self.duration - t) / 0.6))
                    for i in 0..<48 {
                        var r = UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15
                        func rnd() -> Double {
                            r ^= r >> 12; r ^= r << 25; r ^= r >> 27
                            return Double((r &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53)
                        }
                        let angle = -Double.pi / 2 + (rnd() - 0.5) * 2.4
                        let speed = 320 + rnd() * 420
                        let spin = (rnd() - 0.5) * 10
                        let w = 5 + rnd() * 4, h = 8 + rnd() * 5
                        var p = g
                        p.opacity = alpha
                        p.translateBy(x: size.width / 2 + cos(angle) * speed * travel,
                                      y: size.height * 0.3 + sin(angle) * speed * travel + 170 * t * t)
                        p.rotate(by: .radians(spin * t))
                        let fw = w * abs(cos(t * (4 + spin))) + 1   // flutter
                        p.fill(Path(roundedRect: CGRect(x: -fw / 2, y: -h / 2, width: fw, height: h), cornerRadius: 1.5),
                               with: .color(Self.colors[i % Self.colors.count]))
                    }
                }
            }
            .onAppear {
                start = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) { finished = true }
            }
        }
    }
}

/// Style badges popping in one after another.
private struct StyleChips: View {
    let chips: [String]
    @State private var shown = false

    var body: some View {
        FlowLayout(hSpacing: 6, vSpacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
                Text(chip)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    .opacity(shown ? 1 : 0)
                    .scaleEffect(shown ? 1 : 0.6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15 + Double(i) * 0.12), value: shown)
            }
        }
        .onAppear { shown = true }
    }
}
