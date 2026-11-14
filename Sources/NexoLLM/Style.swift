import Foundation
import NaturalLanguage

/// Learns *how* and *what* the user writes from the encrypted, local typing history: language, sentence
/// length, capitalization and punctuation habits, emoji, laughs and abbreviations, register (formal or
/// casual), typical openings and closings, and recurring expressions — globally and per app (a work email
/// isn't a WhatsApp message). The result is a compact block in the prompt, so suggestions sound like you.
///
/// Built to cost nothing while typing:
/// - analysis runs **only when the app goes idle**, at most every 20 minutes and only if the history
///   grew, on a background utility queue (plain string counting, no model);
/// - the per-app prompt block is cached, so building a prompt is a dictionary lookup;
/// - nothing new is stored on disk: the profile is derived from the history and rebuilt at launch.
final class StyleProfile: ObservableObject {
    static let shared = StyleProfile()

    struct Profile: Equatable {
        var samples = 0
        var traits: [String] = []
        var openings: [String] = []
        var closings: [String] = []
        var phrases: [String] = []

        var isEmpty: Bool { traits.isEmpty && openings.isEmpty && closings.isEmpty && phrases.isEmpty }

        /// Prompt block (English labels, the user's own words quoted).
        var block: String {
            var lines: [String] = []
            if !traits.isEmpty { lines.append(traits.joined(separator: "; ")) }
            if !openings.isEmpty { lines.append("Usually opens with: " + openings.map { "\"\($0)\"" }.joined(separator: ", ")) }
            if !closings.isEmpty { lines.append("Usually closes with: " + closings.map { "\"\($0)\"" }.joined(separator: ", ")) }
            if !phrases.isEmpty { lines.append("Expressions they use a lot: " + phrases.map { "\"\($0)\"" }.joined(separator: ", ")) }
            guard !lines.isEmpty else { return "" }
            return "[How the author writes]\n" + lines.joined(separator: "\n")
        }
    }

    @Published private(set) var global = Profile()
    @Published private(set) var lastAnalyzed: Date?
    @Published private(set) var analyzing = false
    private var perApp: [String: Profile] = [:]
    private var blocks: [String: String] = [:]
    private var analyzedSignature = ""
    private let queue = DispatchQueue(label: "nexollm.style", qos: .utility)

    /// Profile used for an app: its own once it has enough samples, otherwise the global one.
    func profile(for app: String) -> Profile { perApp[app] ?? global }

    /// Cached prompt block for an app (nil if nothing learned yet).
    func block(for app: String) -> String? {
        if let b = blocks[app] { return b.isEmpty ? nil : b }
        let b = profile(for: app).block
        blocks[app] = b
        return b.isEmpty ? nil : b
    }

    /// Re-analyzes the history if it changed enough and the last run is old enough. Idle time only.
    func refreshIfNeeded(force: Bool = false) {
        let entries = History.shared.entries
        let signature = "\(entries.count)-\(entries.last?.date.timeIntervalSince1970 ?? 0)"
        guard !analyzing, signature != analyzedSignature else { return }
        if !force, let last = lastAnalyzed, Date().timeIntervalSince(last) < 20 * 60 { return }
        analyzing = true
        let recent = Array(entries.suffix(2000))
        queue.async { [weak self] in
            let started = Date()
            var byApp: [String: [String]] = [:]
            for e in recent { byApp[e.app, default: []].append(e.text) }
            let global = StyleProfile.analyze(recent.map(\.text)) ?? Profile()
            var apps: [String: Profile] = [:]
            for (app, texts) in byApp where texts.count >= 15 {
                if let p = StyleProfile.analyze(texts) { apps[app] = p }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.global = global
                self.perApp = apps
                self.blocks = [:]
                self.lastAnalyzed = Date()
                self.analyzedSignature = signature
                self.analyzing = false
                Log.write(String(format: "style: analyzed %d texts (%d app profiles) in %.0fms",
                                 recent.count, apps.count, Date().timeIntervalSince(started) * 1000))
            }
        }
    }

    func reset() {
        global = Profile(); perApp = [:]; blocks = [:]; analyzedSignature = ""; lastAnalyzed = nil
    }

    // MARK: Analysis (pure, unit-tested)

    static func analyze(_ texts: [String]) -> Profile? {
        let messages = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 12 }
        guard messages.count >= 8 else { return nil }
        var p = Profile()
        p.samples = messages.count
        let n = Double(messages.count)

        // Language.
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(messages.suffix(80).joined(separator: "\n").prefix(6000)))
        let lang = recognizer.dominantLanguage
        if let lang, let name = Locale(identifier: "en").localizedString(forLanguageCode: lang.rawValue) {
            p.traits.append("writes in \(name)")
        }

        // Sentence length.
        var sentenceWords: [Int] = []
        for m in messages {
            for s in m.split(whereSeparator: { ".!?\n".contains($0) }) {
                let w = s.split(whereSeparator: { $0.isWhitespace }).count
                if w >= 2 { sentenceWords.append(w) }
            }
        }
        if !sentenceWords.isEmpty {
            let avg = Double(sentenceWords.reduce(0, +)) / Double(sentenceWords.count)
            let a = Int(avg.rounded())
            if avg < 9 { p.traits.append("short, direct sentences (~\(a) words)") }
            else if avg > 20 { p.traits.append("long, articulated sentences (~\(a) words)") }
            else { p.traits.append("medium-length sentences (~\(a) words)") }
        }

        // Capitalization and final punctuation (short, chat-like messages).
        let firstLetters = messages.compactMap { $0.first(where: { $0.isLetter }) }
        let lower = Double(firstLetters.filter { $0.isLowercase }.count) / Double(max(1, firstLetters.count))
        if lower > 0.55 { p.traits.append("often starts in lowercase") }
        let short = messages.filter { $0.count < 220 }
        if short.count >= 6 {
            let noPeriod = Double(short.filter { m in
                guard let last = m.last else { return false }
                return last.isLetter || last.isNumber
            }.count) / Double(short.count)
            if noPeriod > 0.6 { p.traits.append("usually no final period in short messages") }
        }

        // Punctuation habits.
        let exclam = Double(messages.reduce(0) { $0 + $1.filter { $0 == "!" }.count }) / n
        if exclam > 0.35 { p.traits.append("uses exclamation marks often") }
        let ellipses = Double(messages.filter { $0.contains("...") || $0.contains("…") }.count) / n
        if ellipses > 0.15 { p.traits.append("often uses ellipses (...)") }

        // Emoji.
        var emojiCount: [String: Int] = [:]
        var withEmoji = 0
        for m in messages {
            var found = false
            for ch in m where ch.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
                emojiCount[String(ch), default: 0] += 1
                found = true
            }
            if found { withEmoji += 1 }
        }
        if Double(withEmoji) / n > 0.15 {
            let top = emojiCount.sorted { $0.value > $1.value }.prefix(3).map(\.key).joined(separator: " ")
            p.traits.append("uses emoji (\(top))")
        } else if withEmoji == 0, n >= 20 {
            p.traits.append("never uses emoji")
        }

        // Laughs and abbreviations (word level).
        var laughs: [String: Int] = [:]
        var abbreviations: [String: Int] = [:]
        let knownAbbreviations: Set<String> = ["cmq", "nn", "xke", "xké", "xché", "xk", "tvb", "qlc", "qlcs", "msg", "grz",
                                               "pls", "plz", "tt", "dv", "sn", "ke", "cm", "nnt", "tranqui", "bro", "raga",
                                               "btw", "imo", "idk", "thx", "asap", "okk", "vabbè", "boh", "mah"]
        for m in messages {
            for raw in m.lowercased().split(whereSeparator: { $0.isWhitespace || ",.;:!?()\"".contains($0) }) {
                let w = String(raw)
                if isLaugh(w) { laughs[w, default: 0] += 1 }
                if knownAbbreviations.contains(w) { abbreviations[w, default: 0] += 1 }
            }
        }
        if let laugh = laughs.max(by: { $0.value < $1.value }), laugh.value >= 3 {
            p.traits.append("laughs with \"\(laugh.key)\"")
        }
        let usedAbbr = abbreviations.filter { $0.value >= 3 }.sorted { $0.value > $1.value }.prefix(4).map(\.key)
        if !usedAbbr.isEmpty { p.traits.append("uses abbreviations like \(usedAbbr.joined(separator: ", "))") }

        // Register (Italian and English markers).
        let lowerAll = messages.map { $0.lowercased() }
        let formalMarkers = ["cordiali saluti", "distinti saluti", "la ringrazio", "gentile ", "egregio", "resto a disposizione",
                             "le scrivo", "in attesa di un suo", "rimango a disposizione", "kind regards", "best regards",
                             "dear ", "sincerely"]
        let casualMarkers = ["ciao", "ehi", "hey", "un abbraccio", "a dopo", "ci sentiamo", "bella", "tvb", "ahah", "raga",
                             "dai ", "figurati", "tranquillo", "cmq"]
        let formal = lowerAll.filter { m in formalMarkers.contains { m.contains($0) } }.count
        let casual = lowerAll.filter { m in casualMarkers.contains { m.contains($0) } }.count
        if formal >= 3, Double(formal) > Double(casual) * 1.5 { p.traits.append("formal, polite register") }
        else if casual >= 3, Double(casual) > Double(formal) * 2 { p.traits.append("casual, friendly register") }

        // Openings: the first words, up to the first comma/line (≤ 4 words).
        var openings: [String: Int] = [:]
        var closings: [String: Int] = [:]
        for m in messages {
            if let first = m.split(whereSeparator: { ",\n!?.".contains($0) }).first {
                let w = first.split(separator: " ")
                if (1...4).contains(w.count), first.count <= 30, first.contains(where: { $0.isLetter }) {
                    openings[first.trimmingCharacters(in: .whitespaces), default: 0] += 1
                }
            }
            // Closings: the last line of longer, multi-line texts (emails), if short.
            let lines = m.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if lines.count >= 3 {
                for line in lines.suffix(2) {
                    let w = line.split(separator: " ")
                    if (1...5).contains(w.count), line.count <= 40, line.contains(where: { $0.isLetter }) {
                        closings[line.trimmingCharacters(in: CharacterSet(charactersIn: " ,.")), default: 0] += 1
                    }
                }
            }
        }
        let minOpen = max(3, Int(n * 0.04))
        p.openings = openings.filter { $0.value >= minOpen }.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        p.closings = closings.filter { $0.value >= 3 }.sorted { $0.value > $1.value }.prefix(2).map(\.key)

        p.phrases = frequentPhrases(messages, language: lang)
        return p.isEmpty ? nil : p
    }

    static func isLaugh(_ w: String) -> Bool {
        guard w.count >= 4 else { return w == "lol" || w == "xd" }
        let letters = Set(w)
        return letters.isSubset(of: ["a", "h"]) && letters.count == 2 && (w.hasPrefix("ah") || w.hasPrefix("ha"))
    }

    private static let stopwords: Set<String> = [
        // Italian
        "il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "di", "a", "da", "in", "con", "su", "per", "tra", "fra",
        "e", "ed", "o", "ma", "che", "chi", "non", "si", "mi", "ti", "ci", "vi", "ne", "del", "della", "dei", "delle",
        "al", "alla", "ai", "alle", "dal", "dalla", "nel", "nella", "sul", "sulla", "è", "sono", "ho", "hai", "ha",
        "io", "tu", "lui", "lei", "noi", "voi", "loro", "questo", "questa", "quello", "quella", "come", "anche", "più",
        "se", "poi", "già", "l", "d", "c", "un'", "l'", "c'è", "mio", "tuo", "suo",
        // English
        "the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "but", "is", "are", "was", "it", "this", "that",
        "i", "you", "he", "she", "we", "they", "my", "your", "with", "at", "be", "have", "has", "not", "so", "as",
        // ES / FR / DE / PT
        "el", "los", "las", "del", "que", "por", "para", "como", "pero", "más", "mas", "está", "son", "muy",
        "les", "des", "est", "pas", "que", "qui", "dans", "pour", "sur", "plus", "avec", "tout", "mais", "nous", "vous",
        "der", "die", "das", "den", "dem", "und", "ist", "nicht", "mit", "auf", "für", "von", "sie", "ich", "wir", "auch",
        "os", "as", "um", "uma", "dos", "das", "não", "nao", "mais", "muito", "está", "como", "pelo", "pela",
    ]

    /// Recurring 2–4-word expressions (counted once per text), dropping ones made only of filler words
    /// and shorter ones fully covered by a longer frequent phrase.
    /// Apriori-style: an n-gram is only counted if both its (n-1)-grams are frequent, so memory stays
    /// small (a few thousand keys) even over thousands of texts.
    static func frequentPhrases(_ messages: [String], language: NLLanguage?, limit: Int = 8) -> [String] {
        let docs: [[String]] = messages.suffix(900).map { m in
            String(m.suffix(700)).lowercased()
                .split(whereSeparator: { $0.isWhitespace || ",.;:!?()\"«»“”\n".contains($0) })
                .map(String.init)
        }
        let minCount = max(4, docs.count / 40)
        var frequent: [String: Int] = [:]
        var previous: Set<String> = []
        for size in 2...4 {
            var counts: [String: Int] = [:]
            for words in docs where words.count >= size {
                var local = Set<String>()
                for i in 0...(words.count - size) {
                    let gram = words[i..<(i + size)]
                    guard !gram.contains(where: { $0.count > 18 || $0.contains(where: { $0.isNumber }) }) else { continue }
                    if size > 2 {
                        let head = gram.dropLast().joined(separator: " "), tail = gram.dropFirst().joined(separator: " ")
                        guard previous.contains(head), previous.contains(tail) else { continue }
                    }
                    local.insert(gram.joined(separator: " "))
                }
                for g in local { counts[g, default: 0] += 1 }
            }
            let kept = counts.filter { $0.value >= minCount }
            guard !kept.isEmpty else { break }
            previous = Set(kept.keys)
            for (g, c) in kept where g.split(separator: " ").contains(where: { !stopwords.contains(String($0)) && $0.count >= 3 }) {
                frequent[g] = c
            }
        }
        // Prefer longer phrases: drop a shorter one when a longer one containing it is nearly as frequent.
        let kept = frequent.filter { gram, c in
            !frequent.contains { other, oc in other.count > gram.count && other.contains(gram) && Double(oc) >= Double(c) * 0.7 }
        }
        return kept.sorted { ($0.value * $0.key.split(separator: " ").count) > ($1.value * $1.key.split(separator: " ").count) }
            .prefix(limit).map(\.key)
    }
}
