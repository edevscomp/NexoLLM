import AppKit
import Network

// MARK: - Network

/// Live connectivity. NexoLLM works fully offline; only downloads, updates and Web Lookup need it.
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { if self?.isOnline != online { self?.isOnline = online } }
        }
        monitor.start(queue: DispatchQueue(label: "nexollm.network"))
    }
}

// MARK: - Menu bar icon

/// The NexoLLM mark (rounded tile + text cursor) drawn as a template image, one variant per state.
enum MenuBarIcon {
    enum State: Hashable { case active, smartScreen, paused, off, loading, reading, readingScreen, error }

    private static var cache: [State: NSImage] = [:]

    static func image(for state: State) -> NSImage {
        if let img = cache[state] { return img }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            func fill(_ r: NSRect, _ alpha: CGFloat = 1) {
                NSColor.black.withAlphaComponent(alpha).setFill()
                let k = min(r.width, r.height) / 2
                NSBezierPath(roundedRect: r, xRadius: k, yRadius: k).fill()
            }
            func cursor(_ a: CGFloat = 1) {
                fill(NSRect(x: 5.3, y: 5, width: 1.5, height: 8), a)
                fill(NSRect(x: 4.1, y: 12.1, width: 3.9, height: 1.3), a)
                fill(NSRect(x: 4.1, y: 4.6, width: 3.9, height: 1.3), a)
            }
            func ghost(_ a: CGFloat = 1) {
                fill(NSRect(x: 8.7, y: 9.6, width: 5.6, height: 1.8), a)
                fill(NSRect(x: 8.7, y: 6.4, width: 3.8, height: 1.8), a * 0.55)
            }
            func eyeBadge(_ center: NSPoint) {
                NSColor.black.setStroke()
                let eye = NSBezierPath(ovalIn: NSRect(x: center.x - 2.6, y: center.y - 1.7, width: 5.2, height: 3.4))
                eye.lineWidth = 1.15
                eye.stroke()
                fill(NSRect(x: center.x - 0.85, y: center.y - 0.85, width: 1.7, height: 1.7))
            }
            NSColor.black.setStroke()
            let tile = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 4.2, yRadius: 4.2)
            tile.lineWidth = 1.5
            tile.stroke()
            switch state {
            case .active:
                cursor(); ghost()
            case .smartScreen:
                cursor()
                fill(NSRect(x: 8.7, y: 10.6, width: 5.4, height: 1.6))
                eyeBadge(NSPoint(x: 11.4, y: 6.4))
            case .paused:
                fill(NSRect(x: 6.4, y: 5.5, width: 1.9, height: 7))
                fill(NSRect(x: 9.7, y: 5.5, width: 1.9, height: 7))
            case .off:
                cursor(0.45); ghost(0.45)
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3.6, y: 3.6)); slash.line(to: NSPoint(x: 14.4, y: 14.4))
                slash.lineWidth = 1.6; slash.lineCapStyle = .round
                slash.stroke()
            case .loading:
                cursor()
                for x in [9.4, 11.7, 14.0] { fill(NSRect(x: x - 0.9, y: 8.1, width: 1.8, height: 1.8)) }
            case .reading:
                for (x, h) in [(5.0, 4.0), (7.6, 8.0), (10.2, 6.0), (12.8, 3.0)] { fill(NSRect(x: x, y: 9 - h / 2, width: 1.5, height: h)) }
            case .readingScreen:
                let brackets = NSBezierPath()
                // Viewfinder corners + center eye pupil when actively scanning the screen
                brackets.move(to: NSPoint(x: 4.5, y: 10.8)); brackets.line(to: NSPoint(x: 4.5, y: 13.0)); brackets.line(to: NSPoint(x: 6.7, y: 13.0))
                brackets.move(to: NSPoint(x: 11.3, y: 13.0)); brackets.line(to: NSPoint(x: 13.5, y: 13.0)); brackets.line(to: NSPoint(x: 13.5, y: 10.8))
                brackets.move(to: NSPoint(x: 4.5, y: 7.2)); brackets.line(to: NSPoint(x: 4.5, y: 5.0)); brackets.line(to: NSPoint(x: 6.7, y: 5.0))
                brackets.move(to: NSPoint(x: 11.3, y: 5.0)); brackets.line(to: NSPoint(x: 13.5, y: 5.0)); brackets.line(to: NSPoint(x: 13.5, y: 7.2))
                brackets.lineWidth = 1.35; brackets.lineCapStyle = .round; brackets.lineJoinStyle = .round
                brackets.stroke()
                fill(NSRect(x: 7.7, y: 7.7, width: 2.6, height: 2.6))
            case .error:
                fill(NSRect(x: 8.1, y: 7.3, width: 1.8, height: 6.2))
                fill(NSRect(x: 7.95, y: 3.9, width: 2.1, height: 2.1))
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = Brand.name
        cache[state] = img
        return img
    }
}

// MARK: - Crash reporter

/// Local only: a crash (signal, uncaught exception) or an unexpected exit is shown as a report on the next
/// launch. Nothing is ever sent anywhere.
final class CrashReporter: ObservableObject {
    static let shared = CrashReporter()
    @Published var pendingReport: String?

    private let sentinelURL = AppPaths.support.appendingPathComponent("session.sentinel")
    private let reportURL = AppPaths.support.appendingPathComponent("crash-report.txt")
    private static var reportPath = ""
    private var termSource: DispatchSourceSignal?

    func install() {
        let args = CommandLine.arguments
        guard !args.contains("--render-ui"), !args.contains("--selftest") else { return }
        let fm = FileManager.default
        let previous = SecureFile.read(sentinelURL).flatMap { String(data: $0, encoding: .utf8) }
        let cause = SecureFile.read(reportURL).flatMap { String(data: $0, encoding: .utf8) }
            ?? previous.map { _ in "Unexpected exit: no error was recorded (the system may have stopped the app)." }
        if let cause { pendingReport = Self.report(cause: cause, previous: previous ?? "") }
        try? fm.removeItem(at: reportURL)
        Self.reportPath = reportURL.path
        note(engine: "Starting…")

        NSSetUncaughtExceptionHandler { e in
            CrashReporter.write("Uncaught exception: \(e.name.rawValue): \(e.reason ?? "")\n" + e.callStackSymbols.joined(separator: "\n"))
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                CrashReporter.write("Signal \(s) (\(String(cString: strsignal(s))))\n" + Thread.callStackSymbols.joined(separator: "\n"))
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        // `kill` / `pkill`: quit normally (saves data, no false crash report).
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { NSApp.terminate(nil) }
        src.resume()
        termSource = src
    }

    /// Records the session as running (with the engine state, for the next report if this one ends badly).
    func note(engine: String) {
        guard !Self.reportPath.isEmpty else { return }
        let text = "\(Brand.name) \(Brand.version) (\(Brand.build)) · started \(Date())\nEngine: \(engine)\n"
        SecureFile.write(Data(text.utf8), to: sentinelURL)
    }

    func markCleanExit() { try? FileManager.default.removeItem(at: sentinelURL) }

    func dismiss() {
        pendingReport = nil
        try? FileManager.default.removeItem(at: reportURL)
    }

    private static func write(_ text: String) {
        guard !reportPath.isEmpty else { return }
        FileManager.default.createFile(atPath: reportPath, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600])
    }

    private static func report(cause: String, previous: String) -> String {
        let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/\(Brand.name).log")
        let tail = (SecureFile.read(log).flatMap { String(data: $0, encoding: .utf8) } ?? "")
            .split(separator: "\n").suffix(25).map { Log.redact(String($0)) }.joined(separator: "\n")
        return """
        \(Brand.name) crash report · \(Date())
        \(Brand.name) \(Brand.version) (\(Brand.build))
        \(HardwareProfile.current.summary)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)

        Previous session:
        \(previous.trimmingCharacters(in: .whitespacesAndNewlines))

        What happened:
        \(cause)

        Last log lines:
        \(tail)
        """
    }
}

// MARK: - Web lookup

/// Full online web search + fast AI summary ("sunto veloce"): searches organic web results, Wikipedia,
/// Wiktionary (including idioms/phrases) and live news — always summarizing in the app's selected language.
enum WebLookup {
    /// The only hosts Web Lookup talks to (see PRIVACY.md).
    static func isLookupHost(_ host: String) -> Bool {
        let roots = ["wikipedia.org", "wiktionary.org", "wikiquote.org"]
        if roots.contains(where: { host.hasSuffix("." + $0) }) { return true }
        return ["api.duckduckgo.com", "news.google.com"].contains(host)
    }

    struct SourceItem: Identifiable { let id = UUID(); let title: String; let source: String; let url: URL }
    struct WebSnippet { let title: String; let snippet: String; let source: String; let url: URL }
    struct ResultCard {
        let query: String
        let isDefinition: Bool
        let summary: String
        let bullets: [String]
        let bulletTitle: String
        let sources: [SourceItem]
    }

    private static let prefixes = ["do you know what happened", "sai cosa è successo", "sai cos'è successo", "sai cos’è successo",
                                   "cosa è successo", "cos'è successo", "cos’è successo", "what happened", "che succede",
                                   "search for", "look up", "cerca"]

    /// The subject of a question: quotes and conversational openings removed.
    static func cleanQuery(_ raw: String) -> String {
        var q = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”«»")))
        if let p = prefixes.first(where: { q.lowercased().hasPrefix($0) }) { q = String(q.dropFirst(p.count)) }
        return q.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",:")))
    }

    /// True only when the query explicitly asks a question or requests current news/events (NOT idioms or multi-word concepts).
    static func isQuestionOrNews(_ raw: String) -> Bool {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.contains("?") { return true }
        let words = q.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let cues: Set<String> = [
            "chi", "cosa", "cos", "come", "quando", "perché", "perche", "dove", "quale", "quali", "quanto", "quanti",
            "oggi", "ieri", "domani", "notizie", "prezzi", "aumenteranno", "succede", "successo", "ultime", "cronaca",
            "what", "why", "how", "when", "where", "who", "which", "will", "did", "does", "news", "today", "price", "prices", "latest"
        ]
        return words.contains { cues.contains($0) }
    }

    /// Significant content words (>= 4 letters) used to filter out unrelated news/wiki hits. Stopwords,
    /// question words and conversational verbs ("succedendo", "significa", "happening") never appear in
    /// headlines, so they are not required to match.
    static func contentWords(in text: String) -> [String] {
        let stop: Set<String> = [
            "avere", "essere", "fare", "dire", "sono", "della", "delle", "dello", "degli", "nella", "nelle", "nello",
            "sulla", "sulle", "dopo", "prima", "come", "quando", "dove", "perché", "perche", "cosa", "quale", "quali",
            "questo", "questa", "questi", "queste", "quello", "quella", "anche", "tutto", "tutti", "molto", "senza",
            "dalla", "dalle", "dallo", "dagli", "alla", "alle", "allo", "agli", "parte", "stato", "stata", "stati", "state",
            "stanno", "fatto", "fanno", "vuol", "vuole", "significa", "significato", "sapere", "dimmi", "spiegami",
            "succede", "succedendo", "successo", "succedere", "accade", "accadendo", "accaduto", "ultime", "notizie", "oggi",
            "with", "from", "that", "this", "what", "when", "where", "which", "will", "have", "about", "there", "their",
            "happening", "happened", "happen", "means", "meaning", "tell", "latest", "news", "does", "explain", "today"
        ]
        return text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 4 && !stop.contains($0) }
    }

    /// The query with obvious typos fixed ("coaa sta succednedo in palestina?" → "cosa sta succedendo in palestina"),
    /// so the sources are searched and filtered with real words.
    static func normalizedSearchQuery(_ raw: String) -> String {
        let q = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?!.")))
        var out = ""
        var word = ""
        func flush() {
            guard !word.isEmpty else { return }
            if let t = Spelling.typoMap[word.lowercased()] {
                out += word.first?.isUppercase == true ? t.prefix(1).uppercased() + t.dropFirst() : t
            } else if word.count >= 5, word.first?.isLowercase == true, let fix = Spelling.correction(for: word, context: q) {
                out += fix
            } else {
                out += word
            }
            word = ""
        }
        for ch in q {
            if ch.isLetter || ch == "'" || ch == "’" { word.append(ch) } else { flush(); out.append(ch) }
        }
        flush()
        return out
    }

    /// "it" or "en": the language the user searched in, independent of the app UI language.
    static func queryLanguage(_ query: String) -> String {
        if let m = Spelling.markerLanguage(of: query) { return m }
        return Spelling.dominantLanguageCode(of: query) == "it" ? "it" : "en"
    }

    /// True when a news headline actually shares key terms with the user's query (prevents random sports/politics hits).
    /// Questions/news need one key term (typos fixed); phrases and idioms need two.
    static func isRelevantNewsItem(title: String, forQuery query: String) -> Bool {
        let normalized = normalizedSearchQuery(query)
        let keys = contentWords(in: normalized)
        guard !keys.isEmpty else { return true }
        let lowerTitle = title.lowercased()
        let matched = keys.filter { mentions(lowerTitle, $0) }.count
        let isQA = isQuestionOrNews(query) || isQuestionOrNews(normalized)
        let required = isQA ? 1 : (keys.count >= 2 ? 2 : 1)
        return matched >= required
    }

    /// The last sentence or question of a draft.
    static func lastSentence(_ text: String) -> String {
        String(text.suffix(300)).components(separatedBy: CharacterSet(charactersIn: ".!\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
    }

    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))

    /// Identifies the app to Wikimedia and Google News, as their API etiquette asks (no browser impersonation).
    static var userAgent: String { "\(Brand.name)/\(Brand.version) (\(Brand.website.absoluteString))" }

    /// Common idioms with their figurative meaning, in the idiom's own language: an instant, offline, exact answer.
    /// Keys are full phrases; they are matched on their `phraseCore` (verb and articles at the start removed).
    static let idioms: [String: String] = [
        "avere il coltello dalla parte del manico": "Essere in una posizione di vantaggio o di forza: avere il controllo della situazione e il potere di decidere.",
        "avere il coltello fra i denti": "Affrontare qualcosa con grande grinta e determinazione, pronti a lottare fino in fondo.",
        "avere il coltello tra i denti": "Affrontare qualcosa con grande grinta e determinazione, pronti a lottare fino in fondo.",
        "avere l'acqua alla gola": "Essere in grave difficoltà, soprattutto per mancanza di tempo o di denaro.",
        "volere la botte piena e la moglie ubriaca": "Voler ottenere due vantaggi che si escludono a vicenda.",
        "can che abbaia non morde": "Chi minaccia molto a parole di solito non passa ai fatti.",
        "in bocca al lupo": "Augurio di buona fortuna prima di una prova; si risponde «crepi» (o «viva il lupo»).",
        "piove sul bagnato": "Le disgrazie (o le fortune) capitano proprio a chi ne ha già avute.",
        "prendere due piccioni con una fava": "Ottenere due risultati con un'unica azione.",
        "rompere il ghiaccio": "Superare l'imbarazzo iniziale e avviare una conversazione o un rapporto.",
        "essere al verde": "Non avere più soldi.",
        "costare un occhio della testa": "Costare moltissimo.",
        "avere le mani in pasta": "Essere coinvolti in un affare o conoscere bene un ambiente, spesso con una certa influenza.",
        "fare orecchie da mercante": "Fingere di non sentire o di non capire per non dover rispondere o agire.",
        "tagliare la testa al toro": "Prendere una decisione netta per chiudere definitivamente una questione.",
        "menare il can per l'aia": "Tirarla per le lunghe, evitando di arrivare al punto.",
        "avere la coda di paglia": "Sentirsi in colpa e reagire in modo sospettoso o permaloso.",
        "non avere peli sulla lingua": "Dire apertamente ciò che si pensa, senza timori né riguardi.",
        "cadere dalle nuvole": "Essere sorpresi da qualcosa di cui non si sapeva nulla.",
        "avere un diavolo per capello": "Essere molto arrabbiati o nervosi.",
        "prendere lucciole per lanterne": "Fraintendere, scambiare una cosa per un'altra.",
        "gettare la spugna": "Arrendersi, rinunciare a continuare.",
        "salvare capra e cavoli": "Risolvere una situazione salvaguardando due interessi opposti.",
        "break the ice": "To make people feel relaxed at the start of a conversation or meeting.",
        "piece of cake": "Something very easy to do.",
        "under the weather": "Feeling slightly ill.",
        "spill the beans": "To reveal a secret.",
        "bite the bullet": "To force yourself to do something unpleasant that can't be avoided.",
        "hit the nail on the head": "To describe exactly what is causing a situation or problem.",
        "cost an arm and a leg": "To be very expensive.",
        "let the cat out of the bag": "To reveal a secret by mistake.",
        "the ball is in your court": "It's your turn to take action or make a decision.",
    ]

    /// The distinctive part of a phrase: leading verbs in the infinitive, negations and articles removed
    /// ("avere il coltello fra i denti" → "coltello fra i denti"), so "tenere/avere il coltello…" and
    /// "col coltello…" all meet on the same words.
    static func phraseCore(_ phrase: String) -> String {
        let droppable: Set<String> = ["non", "il", "lo", "la", "i", "gli", "le", "l", "un", "una", "uno", "col", "con", "coi",
                                      "to", "the", "a", "an", "ha", "hai", "ho", "hanno", "avere", "essere", "tenere", "fare"]
        var words = phrase.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .flatMap { w -> [String] in
                // "l'acqua" → "l", "acqua"
                let parts = w.split(separator: "'").map(String.init)
                return parts.count == 2 && parts[0].count <= 2 ? parts : [String(w)]
            }
        while let first = words.first, words.count > 1,
              droppable.contains(first) || (first.count >= 5 && ["are", "ere", "ire"].contains(where: { first.hasSuffix($0) })) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// Meaning of a known idiom contained in `query` (conjugated forms included: "ha il coltello dalla parte del manico").
    static func idiomMeaning(_ query: String) -> String? {
        let q = phraseCore(query)
        guard q.split(separator: " ").count >= 1 else { return nil }
        for (phrase, meaning) in idioms {
            let core = phraseCore(phrase)
            if core.contains(" ") {
                if (" " + q + " ").contains(" " + core + " ") { return meaning }
            } else if q == core, let verb = phrase.split(separator: " ").first,
                      query.lowercased().split(separator: " ").contains(verb) {
                // One-word core ("rompere il ghiaccio" → "ghiaccio"): the verb must be there too, or "ghiaccio" alone would match.
                return meaning
            }
        }
        return nil
    }

    /// True when `text` mentions `key` or a word sharing its stem ("palestina" → "palestinese", "palestinesi").
    static func mentions(_ text: String, _ key: String) -> Bool {
        let stem = key.count >= 7 ? String(key.prefix(key.count - 2)) : key
        return text.contains(stem)
    }

    /// The sentence of `text` that contains `core` ("…coi denti. Col coltello fra i denti - Con grande tenacia. …").
    static func focusedSentence(_ text: String, on core: String) -> String? {
        guard !core.isEmpty, let r = text.range(of: core, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let head = text[..<r.lowerBound]
        let start = [". ", "? ", "! ", ") ", "» "].compactMap { head.range(of: $0, options: .backwards)?.upperBound }.max() ?? text.startIndex
        let tail = text[r.upperBound...]
        let end = [". ", "? ", "! ", " [", "..."].compactMap { tail.range(of: $0)?.lowerBound }.min() ?? text.endIndex
        let out = text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]…")))
        return out.isEmpty ? nil : (out.hasSuffix(".") ? out : out + ".")
    }

    /// A real sentence using the idiom: not a fragment, a bibliography line or a book title ("Henri Barbusse, Il coltello fra i denti, Casa ed.").
    static func isUsageExample(_ s: String, core: String) -> Bool {
        guard s.count >= 25, s.count <= 240, s.first?.isUppercase == true else { return false }
        let words = s.split(separator: " ")
        let capitalized = words.dropFirst().filter { $0.first?.isUppercase == true }.count
        if Double(capitalized) / Double(max(1, words.count - 1)) > 0.3 { return false }
        if let r = s.range(of: core, options: .caseInsensitive), r.lowerBound > s.startIndex {
            let before = s[..<r.lowerBound].split(separator: " ").last.map(String.init) ?? ""
            if before.first?.isUppercase == true, s[..<r.lowerBound].count > before.count + 1 { return false }   // mid-sentence title
        }
        return true
    }

    /// Encyclopedia text without maintenance banners, disambiguation notes and emptied parentheses
    /// ("(in arabo …?, , nel dialetto locale )").
    static func cleanEncyclopedia(_ text: String) -> String {
        let banners = ["disambiguazione", "rimanda qui", "se stai cercando", "questa voce", "prospettiva storica",
                       "may refer to", "redirects here", "this article"]
        let noParens = text.replacingOccurrences(of: "\\s*\\([^()]*\\)", with: "", options: .regularExpression)
        return noParens
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .filter { s in !banners.contains { s.lowercased().contains($0) } }
            .joined(separator: ". ")
            .replacingOccurrences(of: "\\s+([,.])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func search(rawQuery: String,
                       answerWith: ((_ instruction: String, @escaping (String?) -> Void) -> Void)? = nil,
                       completion: @escaping (Result<ResultCard, Error>) -> Void) {
        let query = String(cleanQuery(rawQuery).prefix(maxQueryLength))
        let terms = normalizedSearchQuery(query)
        // Sources and summary follow the language of the query, not the app UI ("avere il coltello dalla parte del
        // manico" with the app in English is still looked up on the Italian Wiktionary/Wikipedia/News).
        let lang = queryLanguage(terms)
        let italian = lang == "it"
        let altLang = italian ? "en" : "it"
        guard !terms.isEmpty, let q = terms.addingPercentEncoding(withAllowedCharacters: queryAllowed) else {
            completion(.failure(URLError(.badURL))); return
        }
        let isQA = isQuestionOrNews(rawQuery) || isQuestionOrNews(terms)
        let keys = contentWords(in: terms)
        let wordCount = terms.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
        let isIdiom = !isQA && wordCount >= 3
        let core = phraseCore(terms)
        // Headlines and encyclopedia titles never contain "cosa sta succedendo": questions search the key terms.
        let keyTerms = isQA && !keys.isEmpty ? keys.joined(separator: " ") : terms
        let kq = keyTerms.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? q
        let coreQ = ("\"" + core + "\"").addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? q
        let dictionaryMeaning = isIdiom || wordCount >= 2 ? idiomMeaning(terms) : nil

        // Only the services listed in the privacy policy, over HTTPS; redirects can't lead anywhere else.
        let session = SecureNet.session(timeout: 10) { WebLookup.isLookupHost($0.host?.lowercased() ?? "") }
        let group = DispatchGroup()
        let lock = NSLock()
        var ddgInstant: (text: String, url: URL)?
        var rawNews: [SourceItem] = []
        var wiki: (title: String, text: String, url: URL)?
        var wiktionary: (title: String, text: String, url: URL)?
        var fallbackWiki: (title: String, text: String, url: URL)?
        var wikiSnippets: [WebSnippet] = []
        var wiktSnippets: [WebSnippet] = []
        var quoteSnippets: [WebSnippet] = []

        func fetch(_ urlString: String, timeout: TimeInterval = 8, _ handle: @escaping (Data?) -> Void) {
            guard let url = URL(string: urlString) else { return }
            group.enter()
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(italian ? "it-IT,it;q=0.9,en;q=0.8" : "en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            session.dataTask(with: req) { data, _, _ in
                lock.lock(); handle(data); lock.unlock()
                group.leave()
            }.resume()
        }
        func mediaWiki(_ host: String, _ params: String) -> String { "https://\(host)/w/api.php?\(params)&format=json" }

        // 1. DuckDuckGo Instant Answer API (official JSON endpoint).
        fetch("https://api.duckduckgo.com/?q=\(q)&format=json&no_html=1&skip_disambig=1", timeout: 6) { data in
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let abstract = (json["AbstractText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !abstract.isEmpty,
               let link = (json["AbstractURL"] as? String).flatMap(URL.init(string:)), isWebLink(link) {
                ddgInstant = (abstract, link)
            }
        }
        // 2. Wiktionary + Wikiquote in the query's language: the phrase's own entry, the entries that list it
        //    ("manico"), and real usage examples of an idiom.
        if !isQA {
            fetch(mediaWiki("\(lang).wiktionary.org", "action=query&generator=search&gsrsearch=\(q)&gsrlimit=1&prop=extracts|info&inprop=url&explaintext=1&exsentences=4&redirects=1")) { data in
                wiktionary = parseMediaWiki(data: data)
            }
            fetch(mediaWiki("\(lang).wiktionary.org", "action=query&list=search&srsearch=\(isIdiom ? coreQ : q)&srlimit=3&srprop=snippet")) { data in
                wiktSnippets = parseMediaWikiSearch(data: data, host: "\(lang).wiktionary.org")
            }
            if isIdiom {
                fetch(mediaWiki("\(lang).wikiquote.org", "action=query&list=search&srsearch=\(coreQ)&srlimit=4&srprop=snippet")) { data in
                    quoteSnippets = parseMediaWikiSearch(data: data, host: "\(lang).wikiquote.org")
                }
            }
        }
        // 3. Wikipedia in the query's language (key terms for questions): intro of the best page + full-text snippets.
        fetch(mediaWiki("\(lang).wikipedia.org", "action=query&generator=search&gsrsearch=\(kq)&gsrlimit=1&prop=extracts|info&inprop=url&exintro=1&explaintext=1&exsentences=4&redirects=1")) { data in
            wiki = parseMediaWiki(data: data)
        }
        fetch(mediaWiki("\(lang).wikipedia.org", "action=query&list=search&srsearch=\(isIdiom ? coreQ : kq)&srlimit=3&srprop=snippet")) { data in
            wikiSnippets = parseMediaWikiSearch(data: data, host: "\(lang).wikipedia.org")
        }
        // 4. Wikipedia in the other language.
        fetch(mediaWiki("\(altLang).wikipedia.org", "action=query&generator=search&gsrsearch=\(kq)&gsrlimit=1&prop=extracts|info&inprop=url&exintro=1&explaintext=1&exsentences=3&redirects=1")) { data in
            fallbackWiki = parseMediaWiki(data: data)
        }
        // 5. Google News RSS in the query's language (an idiom is not news: skipped).
        if !isIdiom {
            fetch("https://news.google.com/rss/search?q=\(kq)&hl=\(italian ? "it" : "en-US")&gl=\(italian ? "IT" : "US")&ceid=\(italian ? "IT:it" : "US:en")") { data in
                if let xml = data.flatMap({ String(data: $0, encoding: .utf8) }) { rawNews = parseRSS(xml) }
            }
        }

        group.notify(queue: .main) {
            session.finishTasksAndInvalidate()
            let termsLower = terms.lowercased()
            let news = rawNews.filter { isRelevantNewsItem(title: $0.title, forQuery: terms) }
            // An idiom must appear as such (its core words, in order); otherwise the usual relevance rules apply.
            func aboutQuery(title: String, text: String) -> Bool {
                if isIdiom { return text.lowercased().contains(core) || title.lowercased().contains(core) }
                return isRelevantWikiExtract(title: title, text: text, forQuery: terms)
            }
            let validWiki = [wiki, fallbackWiki].compactMap { $0 }.first { aboutQuery(title: $0.title, text: $0.text) }
            // A Wiktionary page counts as the answer only if it is about the phrase itself (not the "manico" entry).
            let validWiktionary = wiktionary.flatMap { w -> (title: String, text: String, url: URL)? in
                if wordCount <= 2 || w.title.lowercased() == termsLower || w.text.lowercased().contains(core) { return w }
                return nil
            }
            let relevantWikiSnippets = wikiSnippets.filter { aboutQuery(title: $0.title, text: $0.snippet) }
            let relevantWiktSnippets = wiktSnippets.filter { wordCount <= 2 || $0.snippet.lowercased().contains(core) }
            let examples = quoteSnippets.compactMap { s -> (String, WebSnippet)? in
                guard let f = focusedSentence(s.snippet, on: core), isUsageExample(f, core: core) else { return nil }
                return (f, s)
            }
            let bestEncyclopedia = validWiktionary ?? validWiki ?? ddgInstant.map { ("", $0.text, $0.url) }

            // Clickable sources.
            var sources: [SourceItem] = []
            var seen = Set<String>()
            func addSource(_ item: SourceItem) {
                let key = item.url.absoluteString.lowercased()
                guard !seen.contains(key), sources.count < 5 else { return }
                seen.insert(key)
                sources.append(item)
            }
            if let w = validWiktionary { addSource(SourceItem(title: "Wiktionary", source: "Wiktionary", url: w.url)) }
            for s in relevantWiktSnippets.prefix(1) { addSource(SourceItem(title: "Wiktionary · \(s.title)", source: "Wiktionary", url: s.url)) }
            for (_, s) in examples.prefix(1) { addSource(SourceItem(title: "Wikiquote · \(s.title)", source: "Wikiquote", url: s.url)) }
            if let v = validWiki { addSource(SourceItem(title: "Wikipedia", source: "Wikipedia", url: v.url)) }
            if !isIdiom {
                for s in relevantWikiSnippets.prefix(2) { addSource(SourceItem(title: "Wikipedia · \(s.title)", source: "Wikipedia", url: s.url)) }
            }
            if let d = ddgInstant { addSource(SourceItem(title: "DuckDuckGo", source: "DuckDuckGo", url: d.url)) }
            for n in news.prefix(3) { addSource(n) }

            // Key points: news for questions, usage examples for idioms, else encyclopedia sentences or snippets.
            var bullets: [String] = []
            var bulletTitle = L("Key points", "Punti chiave")
            if isQA && !news.isEmpty {
                bullets = Array(news.prefix(4).map(\.title))
                bulletTitle = L("Latest news & highlights", "Ultime notizie e punti chiave")
            } else if isIdiom {
                var seenLines = Set<String>()
                bullets = examples.map(\.0).filter { seenLines.insert($0.lowercased()).inserted }.prefix(3).map { "«\($0)»" }
                bulletTitle = L("Usage examples", "Esempi d'uso")
            } else if let enc = bestEncyclopedia {
                let sentences = cleanEncyclopedia(enc.text)
                    .components(separatedBy: ". ")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 14 }
                bullets = Array(sentences.dropFirst(2).prefix(3)).map { $0.hasSuffix(".") ? $0 : $0 + "." }
            }
            if bullets.isEmpty, !isIdiom {
                bullets = relevantWikiSnippets.prefix(3).map { "\($0.title) — \(cleanEncyclopedia($0.snippet))" }
            }

            // Best answer without the model, strongest first.
            let fallbackSummary: String? = {
                if let d = dictionaryMeaning { return d }
                if let w = validWiktionary { return firstTwoSentences(of: cleanEncyclopedia(w.text)) }
                if isIdiom {
                    // "Col coltello fra i denti - Con grande tenacia." inside a list of idioms.
                    for s in relevantWikiSnippets + relevantWiktSnippets {
                        if let f = focusedSentence(s.snippet, on: core), f.contains(" - ") || f.contains(": ") {
                            addSource(SourceItem(title: s.source, source: s.source.contains("wikipedia") ? "Wikipedia" : "Wiktionary", url: s.url))
                            return f
                        }
                    }
                    return nil
                }
                if let v = validWiki { return firstTwoSentences(of: cleanEncyclopedia(v.text)) }
                if let d = ddgInstant { return firstTwoSentences(of: d.text) }
                if let s = relevantWikiSnippets.first(where: { $0.snippet.count >= 30 }) { return cleanEncyclopedia(s.snippet) }
                return news.first?.title
            }()

            // Rich multi-source context so the model can write a fast, accurate summary ("sunto veloce").
            var contextPieces: [String] = []
            if let w = validWiktionary { contextPieces.append("[Wiktionary] \(cleanEncyclopedia(w.text).prefix(450))") }
            for s in relevantWiktSnippets.prefix(2) { contextPieces.append("[Wiktionary · \(s.title)] \(s.snippet)") }
            for (e, s) in examples.prefix(3) { contextPieces.append("[Wikiquote · \(s.title)] \(e)") }
            if let v = validWiki { contextPieces.append("[Wikipedia] \(cleanEncyclopedia(v.text).prefix(450))") }
            for s in relevantWikiSnippets.prefix(3) { contextPieces.append("[Wikipedia · \(s.title)] \(cleanEncyclopedia(s.snippet))") }
            if let d = ddgInstant { contextPieces.append("[DuckDuckGo] \(d.text.prefix(400))") }
            for n in news.prefix(4) { contextPieces.append("[News - \(n.source)] \(n.title)") }
            let combinedContext = contextPieces.joined(separator: "\n")

            func card(_ summary: String, aiOnly: Bool = false) -> ResultCard {
                // An answer no online source backs is labelled as such, without sounding like an error.
                ResultCard(query: terms, isDefinition: !isQA, summary: summary,
                           bullets: aiOnly ? [L("Explained by the AI model: no online source covers it directly.",
                                                "Spiegazione del modello IA: nessuna fonte online la tratta direttamente.")] : bullets,
                           bulletTitle: aiOnly ? L("Note", "Nota") : bulletTitle, sources: sources)
            }

            // A known idiom: the exact meaning, instantly — no model needed.
            if let d = dictionaryMeaning {
                completion(.success(card(d)))
                return
            }

            let prompt: String
            if italian {
                prompt = combinedContext.isEmpty
                    ? """
                      Rispondi in modo chiaro e diretto in ITALIANO (massimo 2 frasi) a: «\(terms)». Se è un modo di dire, spiegane il significato figurato (non la traduzione letterale); se è una domanda, rispondi direttamente. Scrivi SOLO in italiano.

                      Risposta in italiano su «\(terms)»:
                      """
                    : """
                      Usa i seguenti risultati di ricerca per dare un sunto veloce, chiaro e diretto in ITALIANO (massimo 2 frasi) su «\(terms)». Se è un modo di dire, spiegane il significato figurato (non la traduzione letterale); se è una domanda o notizia, rispondi in modo diretto. Scrivi SOLO in italiano:
                      \(combinedContext.prefix(1100))

                      Sunto veloce in italiano su «\(terms)»:
                      """
            } else {
                prompt = combinedContext.isEmpty
                    ? """
                      Answer clearly and directly in ENGLISH (maximum 2 sentences): “\(terms)”. If it is an idiom, explain its figurative meaning (not a literal translation); if it is a question, answer it directly. Write ONLY in English.

                      Answer in English about “\(terms)”:
                      """
                    : """
                      Use the following search results to provide a fast, clear and direct summary in ENGLISH (maximum 2 sentences) about “\(terms)”. If it is an idiom, explain its figurative meaning; if it is a question or news topic, answer it directly. Write ONLY in English:
                      \(combinedContext.prefix(1100))

                      Quick summary in English about “\(terms)”:
                      """
            }

            guard let answerWith else {
                if let s = fallbackSummary { completion(.success(card(s))) } else { completion(.failure(URLError(.cannotFindHost))) }
                return
            }
            // Even with sparse or no web data, the model answers (explains the idiom, answers the question):
            // never a dead-end "Nothing found".
            answerWith(prompt) { aiText in DispatchQueue.main.async {
                let cleanAI = (aiText ?? "")
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”«»")))
                let rightLanguage = cleanAI.split(separator: " ").count < 5 || Spelling.dominantLanguageCode(of: cleanAI) == lang
                if cleanAI.count >= 20, rightLanguage {
                    completion(.success(card(cleanAI, aiOnly: sources.isEmpty && bullets.isEmpty)))
                } else if let s = fallbackSummary {
                    completion(.success(card(s)))
                } else {
                    completion(.failure(URLError(.cannotFindHost)))
                }
            } }
        }
    }

    /// Full-text search hits (`list=search&srprop=snippet`): the exact passage where the words appear, even deep
    /// inside an entry (idioms listed under "manico", events inside a long article).
    static func parseMediaWikiSearch(data: Data?, host: String) -> [WebSnippet] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let hits = query["search"] as? [[String: Any]] else { return [] }
        return hits.compactMap { hit in
            guard let title = hit["title"] as? String,
                  let enc = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://\(host)/wiki/\(enc)") else { return nil }
            let snippet = stripHTML((hit["snippet"] as? String) ?? "")
            return WebSnippet(title: title, snippet: snippet, source: host, url: url)
        }
    }

    private static func firstTwoSentences(of text: String) -> String {
        let sentences = text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 10 }
        guard !sentences.isEmpty else { return text }
        let joined = sentences.prefix(2).joined(separator: ". ")
        return joined.hasSuffix(".") ? joined : joined + "."
    }

    static func isRelevantWikiExtract(title: String, text: String, forQuery query: String) -> Bool {
        let qLower = query.lowercased()
        let titleLower = title.lowercased()
        let textLower = text.lowercased()
        // Reject obvious false-positive album/song/film pages when searching a common word or idiom.
        let words = qLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count == 1 {
            let musicFilmCues = ["album discografico", "singolo del", "brano musicale", "studio album by", "is a song by", "è un film del"]
            if musicFilmCues.contains(where: { textLower.contains($0) }) { return false }
        }
        if titleLower == qLower || textLower.contains(qLower) { return true }
        let keys = contentWords(in: query)
        guard !keys.isEmpty else { return true }
        let matched = keys.filter { mentions(titleLower, $0) || mentions(textLower, $0) }.count
        // Questions: the key subject is enough ("palestina"). Phrases/idioms: nearly all key words.
        if isQuestionOrNews(query) { return matched >= 1 }
        return matched >= (keys.count >= 3 ? keys.count - 1 : keys.count)
    }

    /// Parses organic web search results (`title`, `snippet`, and real destination `url`) from DuckDuckGo HTML search.
    static func parseDuckDuckGoHTML(_ html: String) -> [WebSnippet] {
        var results: [WebSnippet] = []
        let rawBlocks = html.contains("class=\"result__body\"")
            ? html.components(separatedBy: "class=\"result__body\"")
            : html.components(separatedBy: "class=\"result\"")
        for block in rawBlocks.dropFirst().prefix(8) {
            guard let aRange = block.range(of: "class=\"result__a\"") else { continue }
            let afterA = block[aRange.upperBound...]
            // Extract href before or after class="result__a"
            let headerSlice = block[..<min(block.endIndex, block.index(aRange.upperBound, offsetBy: 600, limitedBy: block.endIndex) ?? block.endIndex)]
            guard let hrefRange = headerSlice.range(of: "href=\"") else { continue }
            let afterHref = headerSlice[hrefRange.upperBound...]
            guard let hrefEnd = afterHref.firstIndex(of: "\"") else { continue }
            let rawHref = String(afterHref[..<hrefEnd])
            guard let targetURL = extractRealURL(from: rawHref) else { continue }

            guard let tagClose = afterA.firstIndex(of: ">"),
                  let endA = afterA.range(of: "</a>", range: tagClose..<afterA.endIndex) else { continue }
            let rawTitle = String(afterA[afterA.index(after: tagClose)..<endA.lowerBound])
            let title = stripHTML(rawTitle)
            guard !title.isEmpty else { continue }

            var snippet = ""
            if let snipRange = block.range(of: "class=\"result__snippet\"") {
                let afterSnip = block[snipRange.upperBound...]
                if let sOpen = afterSnip.firstIndex(of: ">"),
                   let sClose = afterSnip.range(of: "</", range: sOpen..<afterSnip.endIndex) {
                    snippet = stripHTML(String(afterSnip[afterSnip.index(after: sOpen)..<sClose.lowerBound]))
                }
            }
            let host = (targetURL.host ?? "web").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            results.append(WebSnippet(title: title, snippet: snippet, source: host, url: targetURL))
            if results.count >= 5 { break }
        }
        return results
    }

    /// Only plain web pages may be opened from a result card (no file:, custom app schemes, javascript:…).
    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// Longest text sent to search engines: a selection or OCR'd area can be a whole page of private text.
    static let maxQueryLength = 300

    private static func extractRealURL(from href: String) -> URL? {
        let decodedHref = decode(href)
        if let uddgRange = decodedHref.range(of: "uddg=") {
            let after = decodedHref[uddgRange.upperBound...]
            let encoded = after.prefix { $0 != "&" }
            if let unescaped = String(encoded).removingPercentEncoding, let u = URL(string: unescaped), u.scheme?.hasPrefix("http") == true {
                return u
            }
        }
        if decodedHref.hasPrefix("//"), let u = URL(string: "https:" + decodedHref) { return u }
        if let u = URL(string: decodedHref), u.scheme?.hasPrefix("http") == true { return u }
        return nil
    }

    private static func stripHTML(_ s: String) -> String {
        let noTags = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decode(noTags).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func urllibLower(_ s: String) -> String {
        s.lowercased().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private static func parseMediaWiki(data: Data?) -> (title: String, text: String, url: URL)? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any],
              let page = pages.values.first(where: { ($0 as? [String: Any])?["missing"] == nil }) as? [String: Any],
              let raw = page["extract"] as? String else { return nil }
        let title = (page["title"] as? String) ?? ""
        let cleaned = raw
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==") && $0.count > 4 }
            .joined(separator: " ")
        guard !cleaned.isEmpty,
              let link = (page["fullurl"] as? String).flatMap(URL.init(string:)), isWebLink(link) else { return nil }
        return (title, cleaned, link)
    }

    /// Items of a Google News RSS feed ("Headline - Source").
    static func parseRSS(_ xml: String) -> [SourceItem] {
        func tag(_ name: String, in s: String) -> String? {
            guard let open = s.range(of: "<\(name)"), let start = s[open.upperBound...].firstIndex(of: ">"),
                  let close = s.range(of: "</\(name)>", range: start..<s.endIndex) else { return nil }
            return decode(String(s[s.index(after: start)..<close.lowerBound]))
        }
        return xml.components(separatedBy: "<item>").dropFirst().prefix(8).compactMap { item in
            guard let title = tag("title", in: item), let url = tag("link", in: item).flatMap(URL.init(string:)),
                  isWebLink(url) else { return nil }
            let source = tag("source", in: item) ?? url.host ?? ""
            let clean = title.hasSuffix(" - \(source)") ? String(title.dropLast(source.count + 3)) : title
            return SourceItem(title: clean, source: source, url: url)
        }
    }

    private static func decode(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        for (k, v) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
