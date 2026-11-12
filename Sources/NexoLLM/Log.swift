import Foundation

/// Tiny file logger: ~/Library/Logs/NexoLLM.log
enum Log {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(Brand.name).log")
    }()
    private static let queue = DispatchQueue(label: "nexollm.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func reset() {
        queue.sync { try? Data().write(to: url); SecureFile.restrict(url) }   // may hold text snippets: owner-only
    }

    /// Size of the log file.
    static var bytes: Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Verbose per-keystroke diagnostics (Settings → About → debug logging, or --probe/--debug).
    static var verbose = CommandLine.arguments.contains("--probe") || CommandLine.arguments.contains("--debug")

    /// Quoted text (what you typed, what's on screen) is written only when launched with --probe/--debug;
    /// otherwise it becomes its length, e.g. <24 chars>.
    private static let rawText = CommandLine.arguments.contains("--probe") || CommandLine.arguments.contains("--debug")
    private static let quoted = try! NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*""#)

    static func redact(_ message: String) -> String {
        let ns = message as NSString
        var out = message
        for m in quoted.matches(in: message, range: NSRange(location: 0, length: ns.length)).reversed() {
            out = (out as NSString).replacingCharacters(in: m.range, with: "<\(max(0, m.range.length - 2)) chars>")
        }
        return out
    }

    /// Detailed diagnostics; dropped unless `verbose` (avoids disk writes while typing).
    static func write(_ message: String) {
        guard verbose else { return }
        info(message)
    }

    /// Rare, important events (launch, model state, permissions, errors). Always written.
    static func info(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(rawText ? message : redact(message))\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
                SecureFile.restrict(url)
            }
        }
    }
}
