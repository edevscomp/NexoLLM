import CryptoKit
import Foundation

/// Product identity in one place: name, author handle, bundle identifier and links.
enum Brand {
    static let name = "NexoLLM"
    static let author = "EdevS"
    static let bundleID = "com.edevs.NexoLLM"
    /// Source code (GPL-3.0), releases and issues.
    static let website = URL(string: "https://github.com/edevscomp/NexoLLM")!
    static let websiteLabel = "github.com/edevscomp/NexoLLM"
    static let copyright = "© 2026 EdevS · Free software under the GNU GPL v3"
    static let coffee = URL(string: "https://buymeacoffee.com/edevs")!
    static let coffeeLabel = "buymeacoffee.com/edevs"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

/// Small file helpers for the private stores (history, memory, stats, log) and verified downloads.
enum SecureFile {
    /// Nothing NexoLLM stores is anywhere near this; a bigger file is corrupt or not ours.
    static let maxReadBytes = 32 * 1024 * 1024

    /// Reads a file only if it's a regular file of sane size.
    static func read(_ url: URL, limit: Int = maxReadBytes) -> Data? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attrs[.type] as? FileAttributeType) == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.intValue <= limit else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Atomic write, readable and writable by the current user only (0600).
    static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            restrict(url)
        } catch {
            Log.info("storage: could not write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    static func restrict(_ url: URL, mode: Int = 0o600) {
        try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }

    /// Streaming lowercase SHA-256 hex digest for large files (models, updates).
    static func sha256(of url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Tiny FIFO-bounded dictionary shared by completion, alternatives and screen caches.
struct BoundedCache<Key: Hashable, Value> {
    let limit: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = limit
    }

    var isEmpty: Bool { values.isEmpty }
    var entries: [Key: Value] { values }

    subscript(key: Key) -> Value? {
        get { values[key] }
        set {
            guard let v = newValue else { values.removeValue(forKey: key); order.removeAll { $0 == key }; return }
            if values[key] == nil {
                order.append(key)
                if order.count > limit { values.removeValue(forKey: order.removeFirst()) }
            }
            values[key] = v
        }
    }

    mutating func removeAll() {
        values.removeAll()
        order.removeAll()
    }
}

/// Numbers and dates follow the app language, whatever the system region.
enum Fmt {
    static var locale: Locale { Locale(identifier: Settings.shared.prefs.exampleLanguage.localeIdentifier) }

    /// Engine status (English internally, where its prefixes are matched) in the app language.
    static func status(_ s: String) -> String {
        guard Settings.shared.prefs.exampleLanguage != .english else { return s }
        return [("Ready", L("Ready", "Pronto")), ("Loading model…", L("Loading model…", "Caricamento modello…")),
                ("Starting…", L("Starting…", "Avvio…")), ("Sleeping", L("Sleeping", "In pausa")), ("Error:", L("Error:", "Errore:")),
                ("(freed to save memory)", L("(freed to save memory)", "(memoria liberata)")),
                ("No model installed · download one in Models", L("No model installed · download one in Models", "Nessun modello installato · scaricane uno in Modelli")),
                ("Downloading", L("Downloading", "Download di")), ("Verifying", L("Verifying", "Verifica di"))]
            .reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// "4.2" / "4,2": one decimal in the app language.
    static func decimal(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1)).locale(locale)) }

    /// "5.3 GB", "480 MB", "36 KB" (decimal units, like Finder).
    static func bytes(_ n: Int64) -> String {
        let v = Double(n)
        switch v {
        case 1e9...: return String(format: "%.1f GB", locale: locale, v / 1e9)
        case 1e6...: return String(format: "%.0f MB", locale: locale, v / 1e6)
        case 1e3...: return String(format: "%.0f KB", locale: locale, v / 1e3)
        default: return "\(n) bytes"
        }
    }

    static func number(_ n: Int) -> String { n.formatted(.number.locale(locale)) }

    /// "2 days ago", "yesterday".
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }
}
