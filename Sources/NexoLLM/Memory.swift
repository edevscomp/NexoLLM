import Foundation
import CryptoKit

/// Short-term episodic memory: what you wrote about recently (and the on-screen line it was a reply to),
/// so a topic you come back to hours or days later still has context.
///
/// Built to cost nothing while you type:
/// - **No model, no NLP framework**: sentence picking and word stems are plain string heuristics (µs).
/// - **Ingested only when the app goes idle**, from the text you actually wrote in the last burst.
/// - **Decay**: every memory fades with a half-life; mentioning the topic again reinforces it;
///   memories that fade below a threshold are deleted. Bounded to `maxEpisodes`.
/// - **Recall** is an inverted-index lookup on word stems (no scanning), requiring at least two
///   shared topics (stricter across apps, so personal things don't leak into work emails).
/// - **Encrypted on disk** (AES-GCM, key in the Keychain), written only at idle and on quit.
final class Memory: ObservableObject {
    static let shared = Memory(url: AppPaths.support.appendingPathComponent("memory.bin"))

    struct Episode: Codable, Identifiable, Equatable {
        let id: UUID
        /// A sentence the user wrote.
        var text: String
        /// The on-screen line it was replying to, if any.
        var context: String?
        var app: String
        var appName: String
        let created: Date
        var touched: Date
        /// 1 = mentioned once; grows when the topic comes back (capped).
        var strength: Double
        var stems: [String]
        var names: [String]
    }

    /// Raw material collected during a writing burst (one per field).
    struct Source {
        let app: String
        let appName: String
        let text: String
        let screen: String?
    }

    struct Recall: Equatable {
        let ids: [UUID]
        let block: String
    }

    @Published private(set) var episodes: [Episode] = []
    /// stem -> indices into `episodes`. Rebuilt after every mutation (≤ 300 episodes: microseconds).
    private var index: [String: [Int]] = [:]

    /// Memories below this relevance are deleted.
    static let floor = 0.1
    let maxEpisodes = 300
    /// Unused memories are forgotten after about this long (set from preferences).
    var forgetAfter: TimeInterval = 3 * 86_400
    private var halfLife: TimeInterval { forgetAfter / log2(1 / Memory.floor) }

    private let url: URL?
    private let io = DispatchQueue(label: "nexollm.memory", qos: .utility)
    private var dirty = false

    init(url: URL?) {
        self.url = url
        load()
    }

    var count: Int { episodes.count }

    func relevance(_ e: Episode, now: Date = Date()) -> Double {
        e.strength * pow(0.5, max(0, now.timeIntervalSince(e.touched)) / halfLife)
    }

    // MARK: Ingest (idle time only)

    /// Extracts the memorable sentences of a burst off the main thread, then merges them.
    func ingest(_ sources: [Source], now: Date = Date(), sync: Bool = false) {
        guard !sources.isEmpty else { prune(now: now); save(); return }
        let work = { () -> [(Memory.Candidate, Source)] in
            var all: [(Candidate, Source)] = []
            for s in sources { all += Memory.extract(s.text, screen: s.screen).map { ($0, s) } }
            return Array(all.sorted { $0.0.score > $1.0.score }.prefix(4))   // at most 4 new memories per burst
        }
        if sync {
            merge(work(), now: now)
        } else {
            io.async { [weak self] in
                let picked = work()
                DispatchQueue.main.async { self?.merge(picked, now: now) }
            }
        }
    }

    private func merge(_ picked: [(Candidate, Source)], now: Date) {
        for (c, s) in picked {
            let set = Set(c.stems)
            // Same topic already remembered? Reinforce it (newest wording wins) instead of duplicating.
            if let i = episodes.indices.max(by: { overlap(set, episodes[$0]) < overlap(set, episodes[$1]) }),
               overlap(set, episodes[i]) >= max(2, min(set.count, episodes[i].stems.count) / 2) {
                var e = episodes[i]
                e.strength = min(4, relevance(e, now: now) + 1)
                e.touched = now
                e.text = c.text
                e.context = c.context ?? e.context
                e.stems = Array((c.stems + e.stems.filter { !set.contains($0) }).prefix(16))
                e.names = Array(Set(e.names + c.names))
                e.app = s.app; e.appName = s.appName
                episodes[i] = e
            } else {
                episodes.append(Episode(id: UUID(), text: c.text, context: c.context, app: s.app, appName: s.appName,
                                        created: now, touched: now, strength: 1, stems: c.stems, names: c.names))
            }
            dirty = true
        }
        prune(now: now)
        if !picked.isEmpty { Log.write("memory: +\(picked.count) from burst, \(episodes.count) total") }
        save()
    }

    private func overlap(_ set: Set<String>, _ e: Episode) -> Int { e.stems.reduce(0) { $0 + (set.contains($1) ? 1 : 0) } }

    /// Deletes faded memories and enforces the size cap (weakest first).
    func prune(now: Date = Date()) {
        let before = episodes.count
        episodes.removeAll { relevance($0, now: now) < Memory.floor }
        if episodes.count > maxEpisodes {
            episodes = Array(episodes.sorted { relevance($0, now: now) > relevance($1, now: now) }.prefix(maxEpisodes))
        }
        if episodes.count != before { dirty = true }
        rebuildIndex()
    }

    /// The user accepted text that's about these memories: keep them alive.
    func reinforce(_ ids: [UUID], with text: String, now: Date = Date()) {
        guard !ids.isEmpty else { return }
        let s = Set(Memory.stems(text))
        guard !s.isEmpty else { return }
        for i in episodes.indices where ids.contains(episodes[i].id) && overlap(s, episodes[i]) > 0 {
            episodes[i].touched = now
            dirty = true
        }
    }

    func delete(_ id: UUID) { episodes.removeAll { $0.id == id }; dirty = true; rebuildIndex(); save() }
    func deleteAll() { episodes.removeAll(); dirty = true; rebuildIndex(); save() }

    private func rebuildIndex() {
        var idx: [String: [Int]] = [:]
        for (i, e) in episodes.enumerated() { for s in e.stems { idx[s, default: []].append(i) } }
        index = idx
    }

    // MARK: Recall (cheap, main thread)

    /// The memories that match what's being written (and what's on screen), formatted for the prompt.
    /// `draft` is the text being written: memories it already contains are skipped (no echo).
    func recall(query: String, draft: String, app: String, limit: Int = 2, now: Date = Date()) -> Recall? {
        guard !index.isEmpty else { return nil }
        let q = Set(Memory.stems(query))
        guard !q.isEmpty else { return nil }
        var hits: [Int: (score: Double, distinct: Int, longest: Int)] = [:]
        for s in q {
            guard let list = index[s] else { continue }
            let w = 1 / Double(list.count).squareRoot()   // common topics weigh less
            for i in list {
                let bonus = episodes[i].names.contains(s) ? 1.5 : 1
                var h = hits[i] ?? (0, 0, 0)
                h.score += w * bonus
                h.distinct += 1
                h.longest = max(h.longest, s.count)
                hits[i] = h
            }
        }
        let probe = draft.suffix(1500)
        let ranked = hits.compactMap { i, h -> (Double, Int)? in
            let e = episodes[i]
            guard !probe.contains(e.text.prefix(40)) else { return nil }
            let r = relevance(e, now: now)
            guard r >= Memory.floor else { return nil }
            let sameApp = e.app == app
            if h.distinct >= 2 {
                guard h.score >= (sameApp ? 1.6 : 2.4) else { return nil }   // stricter outside its own app
            } else {
                // A single shared topic ("il dito…") counts only for a fresh, specific, unambiguous memory.
                guard r >= 0.3, h.score >= 1, h.longest >= (sameApp ? 3 : 5) else { return nil }
            }
            return (h.score * (0.5 + r), i)
        }.sorted { $0.0 > $1.0 }.prefix(limit)
        guard !ranked.isEmpty else { return nil }
        let picked = ranked.map { episodes[$0.1] }
        let lines = picked.map { e -> String in
            var line = "- \(Memory.ago(e.touched, now: now)), \(e.appName): \"\(e.text)\""
            if let c = e.context { line += " (replying to: \"\(c)\")" }
            return line
        }
        return Recall(ids: picked.map(\.id), block: lines.joined(separator: "\n"))
    }

    static func ago(_ d: Date, now: Date) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 60 { return "earlier today" }
        if m < 24 * 60 { return "\(m / 60) hour\(m < 120 ? "" : "s") ago" }
        let days = m / (24 * 60)
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    // MARK: Extraction (pure, unit-tested)

    struct Candidate {
        let text: String
        let context: String?
        let stems: [String]
        let names: [String]
        let score: Double
    }

    private static let timeWords: Set<String> = [
        "oggi", "ieri", "domani", "stasera", "stamattina", "stanotte", "dopodomani", "settimana", "weekend",
        "lunedi", "martedi", "mercoledi", "giovedi", "venerdi", "sabato", "domenica", "prossimo", "prossima",
        "today", "tomorrow", "yesterday", "tonight", "week", "monday", "tuesday", "wednesday", "thursday",
        "friday", "saturday", "sunday", "next",
    ]
    private static let firstPerson: Set<String> = ["mi", "ho", "sono", "mio", "mia", "miei", "io", "i", "my", "me", "im", "ive"]

    /// The few sentences of `text` worth remembering: personal, concrete, about something specific.
    static func extract(_ text: String, screen: String?) -> [Candidate] {
        let screenLines = (screen ?? "").split(separator: "\n").map(String.init).filter { $0.count >= 8 }
        var out: [Candidate] = []
        for raw in sentences(text) {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (20...260).contains(s.count), !looksTechnical(s), !SecretScrubber.containsSecret(s) else { continue }
            let words = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .split(whereSeparator: { !$0.isLetter }).map(String.init)
            guard words.count >= 4 else { continue }
            let st = stems(s)
            guard st.count >= 2 else { continue }
            let nm = names(s)
            var score = Double(min(st.count, 6)) + Double(nm.count)
            if words.contains(where: timeWords.contains) { score += 1.5 }
            if words.contains(where: firstPerson.contains) { score += 1 }
            guard score >= 4 else { continue }
            // The line on screen it most likely answers (shares topics but isn't the sentence itself).
            let set = Set(st)
            let head = String(s.prefix(30))
            var context: String?
            var best = 1
            for line in screenLines where !s.contains(line) && !line.contains(head) {
                let shared = stems(line).filter { set.contains($0) }.count
                if shared > best { best = shared; context = String(line.prefix(140)) }
            }
            out.append(Candidate(text: s, context: context, stems: st, names: nm, score: score))
        }
        return out
    }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                if cur.count > 1 { out.append(cur) }
                cur = ""
            }
        }
        if cur.trimmingCharacters(in: .whitespaces).count > 1 { out.append(cur) }
        return out
    }

    private static func looksTechnical(_ s: String) -> Bool {
        if s.contains("://") || s.contains("{") || s.contains("}") || s.contains("=>") || s.contains("@") { return true }
        let digits = s.reduce(0) { $0 + ($1.isNumber ? 1 : 0) }
        return digits * 4 > s.count
    }

    /// Capitalized words that aren't at the start of a sentence (people, places, brands) as stems.
    static func names(_ s: String) -> [String] {
        let parts = s.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ":" })
        var out: [String] = []
        for (i, p) in parts.enumerated() where i > 0 {
            let w = p.trimmingCharacters(in: .punctuationCharacters)
            guard w.count >= 3, w.first?.isUppercase == true, w.dropFirst().allSatisfy({ $0.isLowercase }) else { continue }
            if let st = stem(w.lowercased().folding(options: .diacriticInsensitive, locale: nil)) { out.append(st) }
        }
        return Array(Set(out))
    }

    /// Topic stems (unique, in order): lowercased, accent-folded, stop words dropped, light suffix stripping
    /// so "tagliato/tagliata/taglio" or "meeting/meetings" collapse to one key.
    static func stems(_ text: some StringProtocol) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in text.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(whereSeparator: { !$0.isLetter }) {
            guard let s = stem(String(w)), seen.insert(s).inserted else { continue }
            out.append(s)
        }
        return out
    }

    static func stem(_ w: String) -> String? {
        guard w.count >= 4, !stopWords.contains(w), !timeWords.contains(w) else { return nil }
        if w.count >= 6 { return String(w.prefix(5)) }
        if let last = w.last, "aeiou".contains(last) { return String(w.dropLast()) }
        return w
    }

    private static let stopWords: Set<String> = [
        // Italian
        "anche", "ancora", "allora", "altra", "altre", "altri", "altro", "avere", "aveva", "avevo", "abbiamo", "hanno",
        "bene", "male", "meglio", "ciao", "grazie", "come", "cosa", "cose", "dove", "quando", "quanto", "quale", "quali",
        "perche", "pero", "poi", "molto", "molta", "molti", "tanto", "tanta", "tanti", "tutto", "tutta", "tutti", "tutte",
        "sempre", "solo", "fare", "fatto", "fatta", "faccio", "fanno", "quindi", "mentre", "dopo", "prima", "adesso",
        "questo", "questa", "questi", "queste", "quello", "quella", "quelli", "quelle", "sono", "siamo", "siete",
        "essere", "stato", "stata", "stati", "state", "della", "delle", "degli", "dello", "nella", "nelle", "negli",
        "sulla", "sulle", "dalla", "dalle", "alla", "alle", "agli", "allo", "dell", "nell", "sull", "loro", "nostro",
        "nostra", "vostro", "vostra", "ogni", "volta", "volte", "proprio", "davvero", "comunque", "forse", "magari",
        "infatti", "invece", "spero", "credo", "penso", "detto", "dire", "dico", "vado", "vuoi", "voglio", "posso",
        "puoi", "devo", "deve", "devi", "sarebbe", "sarei", "senza", "verso", "fino", "mai", "niente", "nulla",
        "qualcosa", "qualche", "ecco", "certo", "bello", "bella", "caro", "cara", "buon", "buona", "buongiorno",
        "salve", "scusa", "tipo", "cioe", "okay", "sisi", "nono", "eccomi", "fammi", "sapere",
        // English
        "this", "that", "these", "those", "with", "have", "from", "they", "them", "there", "their", "what", "when",
        "where", "which", "would", "could", "should", "about", "been", "were", "will", "your", "just", "like",
        "really", "very", "more", "some", "than", "then", "also", "only", "into", "over", "after", "before",
        "because", "think", "know", "going", "want", "thanks", "thank", "hello", "here", "much", "well", "good",
        "still", "even", "being", "does", "doing", "done", "make", "made", "sure", "maybe", "please", "dear",
    ]

    // MARK: Persistence (idle/quit only)

    func save() {
        guard dirty, let url else { return }
        dirty = false
        let snapshot = episodes
        io.async {
            guard let plain = try? JSONEncoder().encode(snapshot),
                  let sealed = try? AES.GCM.seal(plain, using: History.key()).combined else { return }
            SecureFile.write(sealed, to: url)
        }
    }

    /// Synchronous save (app quitting).
    func flush() {
        guard dirty, let url else { return }
        dirty = false
        guard let plain = try? JSONEncoder().encode(episodes),
              let sealed = try? AES.GCM.seal(plain, using: History.key()).combined else { return }
        SecureFile.write(sealed, to: url)
    }

    private func load() {
        guard let url, let data = SecureFile.read(url),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: History.key()),
              let list = try? JSONDecoder().decode([Episode].self, from: plain) else { return }
        episodes = list
        prune()
    }
}
