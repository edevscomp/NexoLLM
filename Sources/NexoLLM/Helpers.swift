import AppKit
import NaturalLanguage
import Vision
import ScreenCaptureKit

// MARK: - Spelling / autocorrect

/// Spell checking that respects the language of the sentence and fixes only obvious slips.
/// A wrong correction is worse than none, so every rule below leans towards leaving the word alone.
enum Spelling {
    private static let checker: NSSpellChecker = {
        let c = NSSpellChecker.shared
        c.automaticallyIdentifiesLanguages = false
        return c
    }()
    private static let tag = NSSpellChecker.uniqueSpellDocumentTag()

    /// Common Italian words often typed without an accent or with a trailing apostrophe ("probabilita'" -> "probabilità").
    /// Ambiguous real words ("meta", "eta") are excluded unless typed with an apostrophe, preventing cross-language corruption.
    private static let accentMap: [String: String] = [
        "probabilita": "probabilità", "probablita": "probabilità", "possibilita": "possibilità", "possiblita": "possibilità",
        "universita": "università", "difficolta": "difficoltà", "attivita": "attività", "verita": "verità",
        "citta": "città", "perche": "perché", "poiche": "poiché", "benche": "benché", "affinche": "affinché",
        "piu": "più", "gia": "già", "puo": "può", "cio": "ciò", "cosi": "così", "pero": "però", "percio": "perciò",
        "qualita": "qualità", "quantita": "quantità", "realta": "realtà", "societa": "società", "liberta": "libertà",
        "capacita": "capacità", "velocita": "velocità", "felicita": "felicità", "curiosita": "curiosità",
        "opportunita": "opportunità", "necessita": "necessità", "novita": "novità",
        "caffe": "caffè", "cioe": "cioè", "anziche": "anziché", "pressoché": "pressoché", "pressoche": "pressoché",
    ]

    private static let italianTypos: [String: String] = [
        "xciao": "ciao", "cciao": "ciao", "vciao": "ciao", "ciaoo": "ciao", "ciaooo": "ciao", "cao": "ciao", "ciai": "ciao",
        "buongirono": "buongiorno", "bungiorno": "buongiorno", "buongiono": "buongiorno", "buonaser": "buonasera",
        "coaa": "cosa", "csoa": "cosa", "cosaa": "cosa", "succednedo": "succedendo", "succedndo": "succedendo",
        "sucesso": "successo", "perhcè": "perché", "perhce": "perché", "perchè": "perché",
        "scsua": "scusa", "grzie": "grazie", "garzie": "grazie", "graize": "grazie", "nonn": "non",
        "qeusto": "questo", "qusto": "questo", "sempe": "sempre", "ancge": "anche",
    ]

    private static let englishTypos: [String: String] = [
        "hllo": "hello", "helo": "hello", "thnaks": "thanks", "thansk": "thanks", "becuase": "because",
        "teh": "the", "hte": "the", "adn": "and", "nad": "and", "taht": "that", "yuo": "you", "thier": "their", "wiht": "with",
    ]

    private static let otherGreetingTypos: [String: (word: String, lang: String)] = [
        "hla": ("hola", "es"), "salu": ("salut", "fr"), "halo": ("hallo", "de"), "ola": ("olá", "pt"),
    ]

    /// Combined slip table used by language-normalization and tests.
    static let typoMap: [String: String] = italianTypos.merging(englishTypos) { a, _ in a }

    /// Chat shorthand expanded only by the writing tools (Fix Grammar, Improve…), never while typing: there the
    /// user may well mean to write "cmq".
    static let shorthand: [String: (word: String, language: String)] = [
        "nn": ("non", "it"), "cmq": ("comunque", "it"), "qst": ("questo", "it"), "xke": ("perché", "it"),
        "xké": ("perché", "it"), "xchè": ("perché", "it"), "xché": ("perché", "it"), "ke": ("che", "it"),
        "pls": ("please", "en"), "plz": ("please", "en"), "thx": ("thanks", "en"),
    ]

    /// Colloquialisms, slang and common short tokens that must never be "corrected" into a similar word ("suca" -> "sua").
    private static let neverCorrect: Set<String> = [
        "suca", "cazzo", "minchia", "figa", "vabbè", "vabbe", "boh", "mah", "ehm", "bro", "fra", "raga",
        "chill", "cringe", "spoiler", "chat", "link", "app", "web", "wifi", "mail", "zoom", "meet", "obsidian",
    ]

    /// True when the last word of `s` is a link, path, domain or address (never a word to check or complete).
    static func isURLToken(_ s: Substring) -> Bool {
        guard let token = s.split(whereSeparator: { $0.isWhitespace }).last else { return false }
        return token.contains("://") || token.lowercased().hasPrefix("www.") || token.contains("/") || token.contains("@")
            || token.contains("=") || token.contains("?") || (token.contains(".") && !token.hasSuffix("."))
    }

    /// The word currently being typed (letters right before the caret), if any.
    static func currentWord(_ prefix: String) -> String? {
        guard !isURLToken(Substring(prefix)) else { return nil }
        let word = String(prefix.reversed().prefix(while: { $0.isLetter || $0 == "'" || $0 == "’" }).reversed())
        return word.count >= 2 ? word : nil
    }

    /// The last *finished* word (followed by a space/punctuation), for suggested fixes.
    /// Includes a trailing apostrophe used as an accent ("probablita' ", "perche' ").
    static func lastFinishedWord(_ prefix: String) -> (word: String, trailing: String)? {
        let trailing = String(prefix.reversed().prefix(while: { SuggestionText.isSpace($0) || ",.;:!?".contains($0) }).reversed())
        guard !trailing.isEmpty, trailing.count <= 2 else { return nil }
        var body = prefix.dropLast(trailing.count)
        guard !isURLToken(body) else { return nil }
        var apo = ""
        if let last = body.last, last == "'" || last == "’" {
            apo = String(last)
            body = body.dropLast()
        }
        let letters = String(body.reversed().prefix(while: { $0.isLetter }).reversed())
        // Glued to digits, slashes or symbols ("3rd", "x2y", "site/page"): not a word to correct.
        if let before = body.dropLast(letters.count).last, !(before.isWhitespace || "\"'(«“-—".contains(before)) { return nil }
        let word = letters + apo
        return letters.count >= 3 ? (word, trailing) : nil
    }

    // MARK: Language

    private static let englishMarkers: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "have", "will", "would", "could", "should",
        "about", "into", "your", "their", "what", "when", "where", "which", "privacy", "inspector", "settings",
        "window", "screen", "model", "update", "project", "meeting", "workflow", "feature", "issue", "system",
        "please", "thanks", "hello", "hey", "world", "today", "tomorrow", "because", "always", "never", "working"
    ]

    private static let italianMarkers: Set<String> = [
        "è", "é", "à", "ò", "ù", "un", "una", "uno", "il", "lo", "la", "gli", "le", "mi", "ti", "ci", "vi", "si",
        "ho", "ha", "hai", "io", "tu", "lui", "lei", "noi", "voi", "del", "al", "dal", "nel", "sul", "col",
        "ciao", "sono", "della", "delle", "dello", "degli", "nella", "nelle", "sulla", "questo", "questa",
        "questi", "queste", "quello", "quella", "anche", "tutto", "tutti", "molto", "senza", "perché", "perche",
        "però", "pero", "quindi", "allora", "grazie", "salve", "buongiorno", "buonasera", "quando", "dove",
        "come", "cosa", "siamo", "hanno", "fatto", "lavoro", "progetto", "riunione", "lezione", "schermo", "oggi"
    ]

    private static let spanishMarkers: Set<String> = [
        "hola", "gracias", "mañana", "hoy", "ayer", "también", "tambien", "pero", "porque", "porqué", "cuando",
        "donde", "dónde", "cómo", "qué", "quién", "está", "están", "estoy", "tenemos", "tengo", "puede", "puedo",
        "quiero", "hacer", "trabajo", "proyecto", "reunión", "reunion", "pantalla", "siempre", "nunca", "buenos",
        "buenas", "muchas", "mucho", "todos", "todas", "nosotros", "ustedes", "vosotros", "después", "despues"
    ]

    private static let frenchMarkers: Set<String> = [
        "bonjour", "bonsoir", "merci", "beaucoup", "demain", "aujourd", "toujours", "jamais", "mais", "parce",
        "quand", "comment", "pourquoi", "avec", "sans", "dans", "cette", "ces", "nous", "vous", "sont", "suis",
        "avons", "avez", "faire", "travail", "projet", "réunion", "reunion", "écran", "ecran", "fichier", "très",
        "tres", "aussi", "alors", "après", "apres", "peut", "bien", "salut"
    ]

    private static let germanMarkers: Set<String> = [
        "hallo", "guten", "morgen", "danke", "bitte", "heute", "gestern", "immer", "niemals", "nicht", "aber",
        "weil", "wenn", "warum", "wieso", "oder", "und", "mit", "ohne", "für", "über", "unter", "dieser", "diese",
        "dieses", "wir", "ihr", "sind", "habe", "haben", "wird", "werden", "arbeit", "projekt", "treffen", "datei",
        "bildschirm", "auch", "noch", "schon", "jetzt", "später", "können", "kann"
    ]

    private static let portugueseMarkers: Set<String> = [
        "olá", "ola", "obrigado", "obrigada", "amanhã", "amanha", "hoje", "ontem", "também", "tambem", "não",
        "nao", "então", "entao", "porque", "porquê", "quando", "onde", "está", "estão", "estou", "temos", "tenho",
        "pode", "posso", "fazer", "trabalho", "projeto", "reunião", "reuniao", "ecrã", "ficheiro", "arquivo",
        "sempre", "nunca", "muito", "muitos", "todos", "todas", "você", "vocês", "depois", "bom", "boa"
    ]

    private static let markerSets: [(code: String, words: Set<String>)] = [
        ("en", englishMarkers), ("it", italianMarkers), ("es", spanishMarkers),
        ("fr", frenchMarkers), ("de", germanMarkers), ("pt", portugueseMarkers),
    ]

    private static let recognizerLock = NSLock()
    private static let sharedRecognizer: NLLanguageRecognizer = {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.italian, .english, .spanish, .french, .german, .portuguese]
        return r
    }()

    private static func recognizeLanguage(_ text: String, minConfidence: Double) -> String? {
        recognizerLock.lock(); defer { recognizerLock.unlock() }
        sharedRecognizer.reset()
        sharedRecognizer.languageConstraints = [.italian, .english, .spanish, .french, .german, .portuguese]
        sharedRecognizer.processString(text)
        guard let dom = sharedRecognizer.dominantLanguage,
              (sharedRecognizer.languageHypotheses(withMaximum: 1)[dom] ?? 0) >= minConfidence else { return nil }
        return dom.rawValue
    }

    /// Detects the ISO language code (`"it"`, `"en"`, `"es"`, `"fr"`, `"de"`, `"pt"`) of the current clause or words being typed.
    /// Switches immediately even on 1–2 words (e.g. typing `"privacy inspector"` while the app UI is in Italian).
    static func detectedLanguageCode(for context: String) -> String {
        let fallbackCode = Settings.shared.prefs.exampleLanguage.iso
        let tail = String(context.suffix(300))
        let activeClause = tail
            .components(separatedBy: CharacterSet(charactersIn: "\n.!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty } ?? tail
        let words = activeClause
            .lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 2 || ["è", "é", "à", "ò", "ù", "ñ", "ç", "ã", "õ"].contains($0) }
        guard !words.isEmpty else { return fallbackCode }

        let recent = Array(words.suffix(5))
        var scores: [String: Int] = [:]
        for raw in recent {
            var matched = false
            for (code, set) in markerSets where set.contains(raw) { scores[code, default: 0] += 3; matched = true }
            if !matched {
                let norm = normalizedForLanguage(raw, knownInvalid: false)
                if norm != raw {
                    for (code, set) in markerSets where set.contains(norm) { scores[code, default: 0] += 3 }
                }
            }
        }

        if words.count >= 2, let dom = recognizeLanguage(activeClause, minConfidence: 0.55) {
            let bestMarker = scores.max { $0.value < $1.value }
            if bestMarker == nil || bestMarker!.key == dom || bestMarker!.value < 4 {
                return dom
            }
        }

        // Dictionary & suffix tie-breaker only for short 1–2 word fragments without clear NL recognition.
        for raw in recent {
            let validEN = isValid(raw, language: "en")
            let validIT = isValid(raw, language: "it")
            if validEN && !validIT { scores["en", default: 0] += 2 }
            else if validIT && !validEN { scores["it", default: 0] += 2 }
            else if !validEN && !validIT {
                let (i, e) = suffixVote(raw)
                if i > 0 { scores["it", default: 0] += i }
                if e > 0 { scores["en", default: 0] += e }
            }
        }

        let sorted = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key == fallbackCode }
        if let top = sorted.first, top.value > 0 {
            let second = sorted.dropFirst().first?.value ?? 0
            if top.value > second { return top.key }
        }
        return fallbackCode
    }

    private static let longMarkers: [String] = Array(
        markerSets.reduce(into: Set<String>()) { $0.formUnion($1.words) }.filter { $0.count >= 4 }
    )

    /// ISO code (`"en"`, `"it"`, `"es"`, `"fr"`, `"de"`, `"pt"`) when marker words clearly point to one language, else nil.
    static func markerLanguage(of text: String) -> String? {
        var counts: [String: Int] = [:]
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init) {
            let w = normalizedForLanguage(raw)
            for (code, set) in markerSets where set.contains(w) { counts[code, default: 0] += 1 }
        }
        let sorted = counts.sorted { $0.value > $1.value }
        guard let top = sorted.first, top.value > 0 else { return nil }
        let second = sorted.dropFirst().first?.value ?? 0
        return top.value > second ? top.key : nil
    }

    /// A misspelled word mapped to the word it almost certainly is (`"xciao"` → `"ciao"`), for language voting.
    static func normalizedForLanguage(_ w: String, knownInvalid: Bool = false) -> String {
        if let t = typoMap[w] { return t }
        if let a = accentMap[w] { return a }
        guard w.count >= 4, w.count <= 14, !markerSets.contains(where: { $0.words.contains(w) }) else { return w }
        if !knownInvalid, isValid(w, language: "en") || isValid(w, language: "it") { return w }
        // One slip away from a high-frequency marker word ("xciao", "graize", "thnaks").
        let fw = Array(w)
        for m in longMarkers where abs(m.count - w.count) <= 1 {
            if editDistance(fw, Array(m)) == 1 { return m }
        }
        return w
    }

    /// Weak vote from the word's ending (used only for unknown words).
    static func suffixVote(_ w: String) -> (it: Int, en: Int) {
        let itEnds = ["ando", "endo", "zione", "zioni", "mente", "ebbe", "iamo", "ete", "ono", "ato", "ito", "uto", "ggio", "ssimo", "are", "ere", "ire"]
        let enEnds = ["ing", "tion", "ness", "ment", "ould", "ght", "ly", "ed", "ful", "less", "ship"]
        if itEnds.contains(where: { w.hasSuffix($0) }) { return (1, 0) }
        if enEnds.contains(where: { w.hasSuffix($0) }) { return (0, 1) }
        return (0, 0)
    }

    /// Language of a whole text (rewrites, translations): `NLLanguageRecognizer` over all of it, with the
    /// marker/dictionary vote of `detectedLanguageCode` as tie-breaker for short texts.
    static func dominantLanguageCode(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: { !$0.isLetter }).count
        if wordCount >= 4, let dom = recognizeLanguage(trimmed, minConfidence: 0.5) {
            return dom
        }
        var votes: [String: Int] = [:]
        for clause in trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n")) where clause.contains(where: { $0.isLetter }) {
            votes[detectedLanguageCode(for: clause), default: 0] += 1
        }
        return votes.max { $0.value < $1.value }?.key ?? detectedLanguageCode(for: trimmed)
    }

    /// Spell-checker language for the text being written (detected live from the current words/clause, falling back to the app language).
    static func language(for context: String) -> String? {
        let available = checker.availableLanguages
        func match(_ code: String) -> String? {
            available.first { $0 == code } ?? available.first { $0.hasPrefix(code + "_") || $0.hasPrefix(code + "-") }
        }
        let code = detectedLanguageCode(for: context)
        let fallbackCode = Settings.shared.prefs.exampleLanguage.iso
        return match(code) ?? match(fallbackCode) ?? checker.language()
    }

    static func isValid(_ word: String, language: String?) -> Bool {
        let miss = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                         inSpellDocumentWithTag: tag, wordCount: nil)
        return miss.location == NSNotFound
    }

    /// Known in the sentence's language, Italian, English (including capitalized proper nouns typed in lowercase), or in your own writing history.
    private static func isKnown(_ word: String, language: String?) -> Bool {
        if isValid(word, language: language) { return true }
        if language?.hasPrefix("en") == false, isValid(word, language: "en") { return true }
        if language?.hasPrefix("it") == false, isValid(word, language: "it") { return true }
        if word.first?.isLowercase == true {
            let cap = word.prefix(1).uppercased() + word.dropFirst()
            if isValid(cap, language: language) { return true }
            if language?.hasPrefix("en") == false, isValid(cap, language: "en") { return true }
            if language?.hasPrefix("it") == false, isValid(cap, language: "it") { return true }
        }
        return History.shared.knows(word)
    }

    /// A real word in the sentence's language, in English, or one you use yourself.
    static func isWord(_ word: String, context: String) -> Bool {
        isKnown(word, language: language(for: context))
    }

    /// Dictionary words starting with `partial`, most likely first.
    static func completions(for partial: String, context: String, limit: Int = 6) -> [String] {
        guard partial.count >= 2 else { return [] }
        let lang = language(for: context)
        let ns = partial as NSString
        let list = checker.completions(forPartialWordRange: NSRange(location: 0, length: ns.length), in: partial,
                                       language: lang, inSpellDocumentWithTag: tag) ?? []
        return Array(list.filter { $0.count > partial.count }.prefix(limit))
    }

    // MARK: Typos

    /// True when `partial` can't be the beginning of any known word (typo while typing). Short fragments
    /// are never flagged: half a word is not a typo.
    static func isTypoInProgress(_ partial: String, context: String) -> Bool {
        guard partial.count >= 5, partial.allSatisfy({ $0.isLetter }) else { return false }
        let lang = language(for: context)
        if isKnown(partial, language: lang) { return false }
        let ns = partial as NSString
        let completions = checker.completions(forPartialWordRange: NSRange(location: 0, length: ns.length),
                                              in: partial, language: lang, inSpellDocumentWithTag: tag) ?? []
        return completions.isEmpty
    }

    /// Correction for a finished misspelled word, or nil. Handles trailing apostrophes ("probablita'" -> "probabilità"),
    /// missing accents, and unmistakable typos without ever altering short slang/colloquialisms ("suca").
    static func correction(for word: String, context: String) -> String? {
        let hasApostrophe = word.last == "'" || word.last == "’"
        let core = word.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
        guard core.count >= 3, core.allSatisfy({ $0.isLetter }) else { return nil }
        let lower = core.lowercased()
        guard !neverCorrect.contains(lower) else { return nil }
        let isAllCaps = core == core.uppercased()
        if isAllCaps { return nil }
        let head = context.range(of: word, options: .backwards).map { context[..<$0.lowerBound] } ?? ""
        let before = head.trimmingCharacters(in: .whitespaces)
        let sentenceStart = before.isEmpty || ".!?\n".contains(before.last!)
        if core.first?.isUppercase == true, !sentenceStart { return nil }   // probably a name

        func applyCase(_ target: String) -> String {
            core.first?.isUppercase == true ? target.prefix(1).uppercased() + target.dropFirst() : target
        }

        let detected = detectedLanguageCode(for: context)
        let lang = language(for: context)
        let isolated = context.split(whereSeparator: { !$0.isLetter }).count <= 1

        // Never corrupt words that are already valid or recognized markers in a non-Italian sentence (e.g. ES "pero", PT "sucesso").
        if !hasApostrophe, detected != "it" {
            if markerSets.first(where: { $0.code == detected })?.words.contains(lower) == true { return nil }
            if !isolated, isValid(core, language: lang) { return nil }
        }

        if let g = otherGreetingTypos[lower], (detected == g.lang || (isolated && Settings.shared.prefs.exampleLanguage.iso == g.lang)) {
            return applyCase(g.word)
        }
        if detected == "en" || isolated, let en = englishTypos[lower] {
            return applyCase(en)
        }
        if detected == "it" || hasApostrophe || (isolated && Settings.shared.prefs.exampleLanguage != .portuguese) {
            if hasApostrophe, lower == "eta" { return applyCase("età") }
            if hasApostrophe, lower == "meta" { return applyCase("metà") }
            if let mapped = accentMap[lower] ?? italianTypos[lower] {
                return applyCase(mapped)
            }
        }

        if !hasApostrophe, isKnown(core, language: lang) { return nil }
        // Short words (3–4 letters) without a trailing apostrophe: only fix missing accents, never swap/delete letters ("suca" != "sua").
        let onlyAccent = core.count <= 4 && !hasApostrophe

        let sentence = String(context.suffix(200))
        let ns = sentence as NSString
        let r = ns.range(of: core, options: .backwards)
        guard r.location != NSNotFound else { return nil }
        var candidates: [String] = []
        for l in [lang, "it", "en"].compactMap({ $0 }) {
            if let c = checker.correction(forWordRange: r, in: sentence, language: l, inSpellDocumentWithTag: tag) {
                candidates.append(c)
            }
            candidates += checker.guesses(forWordRange: r, in: sentence, language: l, inSpellDocumentWithTag: tag) ?? []
        }
        var scored: [(score: Int, index: Int, word: String)] = []
        var seen = Set<String>()
        for (idx, c) in candidates.enumerated() where c.lowercased() != word.lowercased() && !c.contains(" ") && !c.contains("'") {
            let cl = c.lowercased()
            guard !seen.contains(cl) else { continue }
            seen.insert(cl)
            let fa = core.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            let fb = c.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            if onlyAccent && fa != fb { continue }
            guard isNearMiss(core, c),
                  (isValid(c, language: lang) || isValid(c, language: "it") || isValid(c, language: "en")) else { continue }
            let d = editDistance(Array(fa), Array(fb))
            let isTransposition = (fa.count == fb.count && fa.sorted() == fb.sorted() && d == 1)
            let langBonus = isValid(c, language: lang) ? 0 : 2
            let score = (fa == fb ? 0 : isTransposition ? 1 : d * 2) + langBonus
            scored.append((score, idx, c))
        }
        if let best = scored.min(by: { $0.score != $1.score ? $0.score < $1.score : $0.index < $1.index }) {
            return applyCase(best.word)
        }
        return nil
    }

    /// Unmistakable near misses only: missing accents, same-length 1-edit slips on 5-letter words,
    /// or ≤ 2 edits on ≥ 6-letter words that share first and last letter (or stem).
    static func isNearMiss(_ a: String, _ b: String) -> Bool {
        let fa = a.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let fb = b.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        if fa == fb { return true }   // perche → perché
        // A stray adjacent key before the first letter ("xciao" → "ciao") or a doubled letter ("ciaoo" → "ciao"):
        // the rest of the word is intact, so the slip is unmistakable.
        if fb.count >= 4, fa.count == fb.count + 1 {
            if String(fa.dropFirst()) == fb { return true }
            let a = Array(fa)
            for i in 1..<a.count where a[i] == a[i - 1] {
                var r = a; r.remove(at: i)
                if String(r) == fb { return true }
            }
        }
        // Wrong first key on a long word ("xomputer" → "computer").
        if fa.count >= 6, fa.count == fb.count, fa.first != fb.first, fa.dropFirst() == fb.dropFirst() { return true }
        guard fa.first == fb.first, abs(fa.count - fb.count) <= 1 else { return false }
        if fa.count <= 4 {
            return fa.count == fb.count && fa.sorted() == fb.sorted() && editDistance(Array(fa), Array(fb)) == 1
        }
        let d = editDistance(Array(fa), Array(fb))
        if fa.count == 5 { return d <= 1 && fa.count == fb.count }
        return d <= 2 && (fa.last == fb.last || d == 1)
    }

    /// Damerau–Levenshtein (optimal string alignment).
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }
}

// MARK: - Emoji

enum Emoji {
    struct Item { let glyph: String; let name: String }

    /// All single-scalar emoji with their Unicode names, built once.
    static let all: [Item] = {
        var out: [Item] = []
        let ranges: [ClosedRange<UInt32>] = [0x1F300...0x1FAFF, 0x2600...0x27BF, 0x1F000...0x1F2FF, 0x2300...0x23FF, 0x2B00...0x2BFF]
        for r in ranges {
            for v in r {
                guard let s = Unicode.Scalar(v), s.properties.isEmojiPresentation, let name = s.properties.name else { continue }
                out.append(Item(glyph: String(s), name: name.lowercased()))
            }
        }
        return out
    }()

    static let aliases: [String: String] = [
        "smile": "😄", "sorriso": "😊", "ridere": "😂", "lol": "😂", "cuore": "❤️", "heart": "❤️", "love": "😍",
        "ok": "👌", "like": "👍", "pollice": "👍", "thumbsup": "👍", "fire": "🔥", "fuoco": "🔥", "triste": "😢",
        "sad": "😢", "cry": "😭", "piangere": "😭", "wink": "😉", "occhiolino": "😉", "festa": "🎉", "party": "🎉",
        "clap": "👏", "pray": "🙏", "grazie": "🙏", "think": "🤔", "pensare": "🤔", "cool": "😎", "kiss": "😘",
        "bacio": "😘", "angry": "😠", "arrabbiato": "😠", "rocket": "🚀", "star": "⭐", "stella": "⭐", "check": "✅",
        "sweat_smile": "😅", "joy": "😂", "eyes": "👀", "100": "💯", "muscle": "💪", "wave": "👋", "ciao": "👋",
    ]

    static func search(_ query: String, limit: Int = 6) -> [Item] {
        let q = query.lowercased()
        var result: [Item] = []
        if let a = aliases[q] { result.append(Item(glyph: a, name: q)) }
        if q.isEmpty {
            return ["😊", "😂", "❤️", "👍", "🙏", "🔥"].map { Item(glyph: $0, name: "") }
        }
        let words = all.filter { $0.name.split(separator: " ").contains { $0.hasPrefix(q) } }
        let contains = all.filter { $0.name.contains(q) }
        for item in words + contains where !result.contains(where: { $0.glyph == item.glyph }) {
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    static let emoticons: [String: String] = [
        ":-)": "🙂", ":)": "🙂", ";-)": "😉", ";)": "😉", ":-D": "😃", ":D": "😃", ":-(": "🙁", ":(": "🙁",
        ":'(": "😢", "<3": "❤️", ":-P": "😛", ":P": "😛", ":-O": "😮", ":O": "😮", "xD": "😆", "XD": "😆",
        ":-*": "😘", ":*": "😘", "B-)": "😎", ":-/": "😕", "^^": "😊", "</3": "💔",
    ]

    /// Emoticon right before the caret, e.g. "ciao :)" -> (":)", "🙂").
    static func trailingEmoticon(_ prefix: String) -> (String, String)? {
        for (k, v) in emoticons.sorted(by: { $0.key.count > $1.key.count }) where prefix.hasSuffix(k) {
            let before = prefix.dropLast(k.count)
            if before.isEmpty || (before.last.map(SuggestionText.isHorizontalSpace) ?? false) || before.last == "\n" { return (k, v) }
        }
        return nil
    }

    /// Query after " :" right before the caret, e.g. "ciao :sor" -> "sor".
    static func pickerQuery(_ prefix: String) -> String? {
        guard let colon = prefix.lastIndex(of: ":") else { return nil }
        let query = prefix[prefix.index(after: colon)...]
        guard query.count <= 20, query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return nil }
        let before = prefix[..<colon]
        guard before.isEmpty || (before.last.map(SuggestionText.isHorizontalSpace) ?? false) || before.last == "\n" else { return nil }
        if query.isEmpty, before.isEmpty { return nil }
        return String(query)
    }
}

// MARK: - Screen & clipboard context

enum ContextSources {
    /// Recent clipboard text (short, single-ish block), or nil. Passwords and one-time codes copied from password
    /// managers (marked concealed/transient, nspasteboard.org convention) are never read.
    static func clipboard() -> String? {
        let pb = NSPasteboard.general
        guard !Pasteboards.isSensitive(pb),
              let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              s.count >= 2, s.count <= 2000 else { return nil }
        return String(s.prefix(400))
    }
}

/// Pasteboard conventions shared by password managers and clipboard history apps (nspasteboard.org).
enum Pasteboards {
    typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let autoGenerated = NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")
    private static let sensitiveTypes: [NSPasteboard.PasteboardType] = [
        concealed, transient,
        NSPasteboard.PasteboardType("com.agilebits.onepassword"),
        NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType"),
    ]

    static func isSensitive(_ pb: NSPasteboard) -> Bool {
        isSensitive(types: pb.types ?? [])
    }

    static func isSensitive(types: [NSPasteboard.PasteboardType]) -> Bool {
        types.contains { sensitiveTypes.contains($0) }
    }

    /// Every item and representation currently on the pasteboard.
    static func snapshot(_ pb: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
        (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
    }

    /// Puts a snapshot back (images, files and rich text included).
    static func restore(_ pb: NSPasteboard, _ saved: [[(NSPasteboard.PasteboardType, Data)]]) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        pb.writeObjects(saved.map { pairs in
            let item = NSPasteboardItem()
            for (t, d) in pairs { item.setData(d, forType: t) }
            return item
        })
    }
}

// MARK: - Mechanical key click sound

/// A real mechanical keyboard click (`Resources/key-click.wav`), played at the user's volume.
enum KeyClickSound {
    static let wavData: Data = {
        let url = Bundle.main.url(forResource: "key-click", withExtension: "wav")
            ?? URL(fileURLWithPath: "Resources/key-click.wav")   // `swift test` runs from the package root
        return (try? Data(contentsOf: url)) ?? Data()
    }()

    private static let sound: NSSound? = NSSound(data: wavData)

    /// Plays when "Sound when accepting" is on, or always with `force` (preview, tour).
    static func play(force: Bool = false) {
        guard force || Settings.shared.prefs.acceptSound, let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.volume = Float(max(0.05, min(1, Settings.shared.prefs.acceptSoundVolume)))
        sound.play()
    }
}

// MARK: - Launch at login (SMAppService + LaunchAgent fallback)

import ServiceManagement

enum LaunchAtLogin {
    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Brand.bundleID).plist")
    }

    static var isEnabled: Bool {
        if SMAppService.mainApp.status == .enabled { return true }
        return FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ on: Bool) throws {
        let fm = FileManager.default
        if on {
            do {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .enabled {
                    try? fm.removeItem(at: agentURL)
                    return
                }
            } catch {
                Log.info("login: SMAppService register fell back to LaunchAgent (\(error.localizedDescription))")
            }
            let dir = agentURL.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let appBinary = "/Applications/\(Brand.name).app/Contents/MacOS/\(Brand.name)"
            let execPath = fm.fileExists(atPath: appBinary) ? appBinary : (Bundle.main.executablePath ?? appBinary)
            let plist: [String: Any] = [
                "Label": Brand.bundleID,
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agentURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: agentURL.path)
        } else {
            try? SMAppService.mainApp.unregister()
            if fm.fileExists(atPath: agentURL.path) {
                try fm.removeItem(at: agentURL)
            }
        }
    }
}
