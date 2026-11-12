import Foundation
import CryptoKit
import Security

/// Encrypted, local-only typing history used for personalization.
/// AES-GCM file in Application Support; the key lives in the user's Keychain.
final class History: ObservableObject {
    static let shared = History()

    struct Entry: Codable {
        let app: String
        var text: String
        var date: Date
    }

    /// Lowercased word sets per entry, computed lazily for retrieval (not persisted).
    private var wordCache: [Int: Set<String>] = [:]

    @Published private(set) var entries: [Entry] = []
    var count: Int { entries.count }
    func count(app: String) -> Int { entries.reduce(0) { $0 + ($1.app == app ? 1 : 0) } }

    private let url = AppPaths.support.appendingPathComponent("history.bin")
    private let queue = DispatchQueue(label: "nexollm.history")
    private let maxEntries = 6000
    private var saveScheduled = false
    /// Identifies the field currently being recorded so we update one entry instead of piling up drafts.
    private var currentFieldKey: String?
    private var currentIndex: Int?

    private init() { load() }

    // MARK: Recording

    /// Records the latest text of a field. Repeated calls for the same field update the same entry —
    /// unless it's clearly a *new* text in the same field (next message in a chat box): then it gets its
    /// own entry, so every message you send is learned from instead of overwriting the previous one.
    func record(app: String, fieldKey: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, !History.hasRepetitionLoop(trimmed), !SecretScrubber.containsSecret(trimmed) else { return }
        let clipped = String(trimmed.suffix(1500))
        if fieldKey == currentFieldKey, let i = currentIndex, i < entries.count, entries[i].app == app {
            let old = entries[i].text
            guard old != clipped else { return }
            // Caret moved back / text above the caret only: keep the longer version.
            if old.hasPrefix(clipped), clipped.count + 30 < old.count { return }
            let sameText = old.count >= 1400 || clipped.count >= 1400 || clipped.prefix(12) == old.prefix(12)
            if sameText {
                entries[i].text = clipped
                entries[i].date = Date()
                wordCache[i] = nil
                scheduleSave()
                return
            }
        }
        entries.append(Entry(app: app, text: clipped, date: Date()))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries); wordCache.removeAll() }
        currentFieldKey = fieldKey
        currentIndex = entries.count - 1
        scheduleSave()
    }

    func deleteAll() {
        entries.removeAll(); wordCache.removeAll(); currentFieldKey = nil; currentIndex = nil; scheduleSave()
    }

    /// Size of the encrypted history file on disk.
    var diskBytes: Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    func delete(at indices: IndexSet) {
        for i in indices.sorted(by: >) where i < entries.count { entries.remove(at: i) }
        wordCache.removeAll(); currentFieldKey = nil; currentIndex = nil; scheduleSave()
    }

    /// Keeps the `limit` most recent texts.
    func keepRecent(_ limit: Int) {
        guard entries.count > limit else { return }
        entries.removeFirst(entries.count - limit)
        wordCache.removeAll(); currentFieldKey = nil; currentIndex = nil; scheduleSave()
    }

    func delete(app: String) {
        entries.removeAll { $0.app == app }; wordCache.removeAll(); currentFieldKey = nil; currentIndex = nil; scheduleSave()
    }

    // MARK: Vocabulary

    private var vocabulary: Set<String> = []
    private var vocabularyStamp = -1

    /// The word appears at least twice in your own writing (so it's yours, not a typo).
    func knows(_ word: String) -> Bool {
        let w = word.lowercased()
        guard w.count >= 3 else { return false }
        let stamp = entries.count &+ entries.reduce(0) { $0 &+ $1.text.utf8.count }
        if stamp != vocabularyStamp {
            var counts: [Substring: Int] = [:]
            for e in entries {
                for token in e.text.lowercased().split(whereSeparator: { !$0.isLetter }) where token.count >= 3 {
                    counts[token, default: 0] += 1
                }
            }
            vocabulary = Set(counts.filter { $0.value >= 2 }.map { String($0.key) })
            vocabularyStamp = stamp
        }
        return vocabulary.contains(w)
    }

    // MARK: Retrieval

    /// Past writing that shares the most words with `context` (simple TF-IDF-ish overlap),
    /// while excluding the paragraph currently being written so the model never echoes it back.
    func snippets(similarTo context: String, app: String, limit: Int, excludingField fieldKey: String?) -> [String] {
        guard limit > 0, !entries.isEmpty else { return [] }
        let tail = String(context.suffix(400))
        let query = Set(History.words(Substring(tail)))
        guard !query.isEmpty else { return [] }
        let tailProbe = String(tail.trimmingCharacters(in: .whitespacesAndNewlines).suffix(60))
        var scored: [(Double, String)] = []
        for (i, e) in entries.enumerated().reversed().prefix(3000) {
            if fieldKey != nil, fieldKey == currentFieldKey, i == currentIndex { continue }
            if !tailProbe.isEmpty, (e.text.contains(tailProbe) || context.contains(e.text)) { continue }
            let w: Set<String>
            if let cachedWords = wordCache[i] { w = cachedWords } else { w = Set(History.words(Substring(e.text))); wordCache[i] = w }
            let overlap = Double(query.intersection(w).count)
            guard overlap >= 2 else { continue }
            // Skip if > 65% of the current text's words are in this entry (same draft after refocus).
            if query.count >= 4, overlap / Double(query.count) > 0.65 { continue }
            let sameApp = e.app == app ? 1.5 : 1.0
            scored.append((overlap / Double(10 + w.count).squareRoot() * sameApp, e.text))
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map { String($0.1.suffix(240)) }
    }

    private static func words(_ s: Substring) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 }.map(String.init)
    }

    /// Detects if a text contains a 3-word phrase repeated 3+ times (e.g. from an earlier loop).
    private static func hasRepetitionLoop(_ s: String) -> Bool {
        let ws = s.lowercased().split(whereSeparator: { !$0.isLetter })
        guard ws.count >= 9 else { return false }
        var counts: [String: Int] = [:]
        for i in 0...(ws.count - 3) {
            let tri = "\(ws[i]) \(ws[i + 1]) \(ws[i + 2])"
            guard tri.count >= 10 else { continue }
            counts[tri, default: 0] += 1
            if counts[tri]! >= 3 { return true }
        }
        return false
    }

    // MARK: Persistence

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        let snapshot = { self.entries }
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            let data = DispatchQueue.main.sync { () -> [Entry] in self.saveScheduled = false; return snapshot() }
            guard let plain = try? JSONEncoder().encode(data),
                  let sealed = try? AES.GCM.seal(plain, using: History.key()).combined else { return }
            SecureFile.write(sealed, to: self.url)
        }
    }

    /// Writes pending changes immediately (call on quit).
    func flush() {
        guard let plain = try? JSONEncoder().encode(entries),
              let sealed = try? AES.GCM.seal(plain, using: History.key()).combined else { return }
        SecureFile.write(sealed, to: url)
    }

    private func load() {
        guard let data = SecureFile.read(url),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: History.key()),
              let list = try? JSONDecoder().decode([Entry].self, from: plain) else { return }
        entries = list.filter { !History.hasRepetitionLoop($0.text) }
    }

    /// AES key shared by the encrypted local stores (history, memory). Lives in the Keychain, read once.
    static func key() -> SymmetricKey {
        keyLock.lock(); defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }
        let key = loadOrCreateKey()
        cachedKey = key
        return key
    }

    private static let keyLock = NSLock()
    private static var cachedKey: SymmetricKey?
    private static let keyAccount = "history-key"

    private static func loadOrCreateKey() -> SymmetricKey {
        if let data = readKey(service: Brand.bundleID).data { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        storeKey(key.withUnsafeBytes { Data($0) }, service: Brand.bundleID)
        return key
    }

    private static func readKey(service: String) -> (data: Data?, status: OSStatus) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: keyAccount,
                                    kSecReturnData as String: true]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let d = out as? Data, d.count == 32 else { return (nil, status) }
        return (d, status)
    }

    private static func storeKey(_ data: Data, service: String) {
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: keyAccount,
                                  kSecAttrLabel as String: "\(Brand.name) local encryption key",
                                  kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Drops the decrypted key from memory (screen locked, Mac asleep). Read again from the Keychain on next use.
    static func lockKeyInMemory() {
        keyLock.lock(); cachedKey = nil; keyLock.unlock()
    }
}

/// Text with a secret in it (API key, token, password, card number, IBAN, private key) is never stored,
/// not even encrypted.
enum SecretScrubber {
    private static let patterns: [NSRegularExpression] = [
        #"\b(sk|pk|rk)-[A-Za-z0-9_-]{16,}"#,
        #"\bgh[pousr]_[A-Za-z0-9]{20,}"#,
        #"\bAIza[0-9A-Za-z_-]{30,}"#,
        #"\bAKIA[0-9A-Z]{16}\b"#,
        #"\bxox[baprs]-[A-Za-z0-9-]{10,}"#,
        #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
        #"(?i)\b(password|passwd|pwd|passcode|secret|api[ _-]?key|seed phrase|mnemonic|pin)\s*[:=]\s*\S+"#,
        #"(?i)\bpassword\s+(is|è|e')\s+\S+"#,
        #"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#,   // IBAN
    ].map { try! NSRegularExpression(pattern: $0) }
    private static let cardCandidate = try! NSRegularExpression(pattern: #"\b\d(?:[ -]?\d){12,18}\b"#)

    static func containsSecret(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if patterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) { return true }
        return cardCandidate.matches(in: text, range: range).contains { m in
            luhn((text as NSString).substring(with: m.range).filter(\.isNumber))
        }
    }

    private static func luhn(_ digits: String) -> Bool {
        let d = digits.reversed().compactMap(\.wholeNumberValue)
        guard (13...19).contains(d.count) else { return false }
        let sum = d.enumerated().reduce(0) { s, e in s + (e.offset % 2 == 1 ? (e.element * 2 > 9 ? e.element * 2 - 9 : e.element * 2) : e.element) }
        return sum % 10 == 0
    }
}
