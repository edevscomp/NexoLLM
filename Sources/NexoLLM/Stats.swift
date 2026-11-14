import Foundation
import IOKit.ps

/// Shared on-disk location: ~/Library/Application Support/NexoLLM (owner-only, 0700).
enum AppPaths {
    static let support: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Brand.name, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        SecureFile.restrict(dir, mode: 0o700)
        // Files written by older versions kept the default 0644: tighten them once per launch.
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            var isDir: ObjCBool = false
            let url = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            SecureFile.restrict(url, mode: isDir.boolValue ? 0o700 : 0o600)
        }
        return dir
    }()
}

/// Completion statistics (no limits — just numbers).
final class Stats: ObservableObject {
    static let shared = Stats()

    struct Day: Codable, Equatable {
        var words = 0
        var completions = 0
        /// Accepted words per app bundle ID on that day. Empty for days recorded before 0.9.0.
        var byApp: [String: Int] = [:]

        init(words: Int = 0, completions: Int = 0, byApp: [String: Int] = [:]) {
            self.words = words; self.completions = completions; self.byApp = byApp
        }

        private enum CodingKeys: String, CodingKey { case words, completions, byApp }

        /// Older stats.json files have no `byApp`: they load unchanged.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            words = try c.decodeIfPresent(Int.self, forKey: .words) ?? 0
            completions = try c.decodeIfPresent(Int.self, forKey: .completions) ?? 0
            byApp = try c.decodeIfPresent([String: Int].self, forKey: .byApp) ?? [:]
        }

        /// Words per app, with whatever isn't attributed to an app (older days) under `Stats.otherApp`.
        var appBreakdown: [String: Int] {
            var out = byApp
            let rest = words - byApp.values.reduce(0, +)
            if rest > 0 { out[Stats.otherApp, default: 0] += rest }
            return out
        }
    }

    /// Key for words not attributed to a known app.
    static let otherApp = "_other"

    /// Keyed by "yyyy-MM-dd".
    @Published private(set) var days: [String: Day] = [:]
    /// Accepted words per app bundle ID.
    @Published private(set) var perApp: [String: Int] = [:]

    private struct Stored: Codable { var days: [String: Day]; var perApp: [String: Int] }
    private let url = AppPaths.support.appendingPathComponent("stats.json")
    private let persist: Bool

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private init() {
        persist = true
        if let data = SecureFile.read(url), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            days = s.days; perApp = s.perApp
        }
    }

    /// In-memory instance for isolated unit tests (never writes to disk).
    init(days: [String: Day], perApp: [String: Int] = [:]) {
        self.persist = false
        self.days = days
        self.perApp = perApp
    }

    #if DEBUG || NEXO_DEV
    /// Populates preview data in memory without touching disk (used by `--render-ui`).
    func loadPreview(_ days: [String: Day], perApp: [String: Int]) {
        self.days = days
        self.perApp = perApp
    }
    #endif

    func record(words: Int, app: String, on date: Date = Date()) {
        let key = Stats.dayFormatter.string(from: date)
        var d = days[key] ?? Day()
        d.words += words
        d.completions += 1
        if !app.isEmpty {
            d.byApp[app, default: 0] += words
            perApp[app, default: 0] += words
        }
        days[key] = d
        scheduleSave()
    }

    func day(_ date: Date) -> Day { days[Stats.dayFormatter.string(from: date)] ?? Day() }
    var today: Day { day(Date()) }
    var totalWords: Int { days.values.reduce(0) { $0 + $1.words } }

    // MARK: Analytics

    /// Consecutive days with at least one accepted word, ending today (or yesterday, if nothing yet today).
    static func streak(_ days: [String: Day], today: Date = Date()) -> Int {
        let cal = Calendar.current
        var date = cal.startOfDay(for: today)
        if (days[dayFormatter.string(from: date)]?.words ?? 0) == 0 {
            guard let y = cal.date(byAdding: .day, value: -1, to: date) else { return 0 }
            date = y
        }
        var n = 0
        while (days[dayFormatter.string(from: date)]?.words ?? 0) > 0 {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { break }
            date = prev
        }
        return n
    }

    var streak: Int { Stats.streak(days) }

    /// Words per app over a list of days, largest first (older unattributed words under `otherApp`).
    static func appTotals(_ days: [Day]) -> [(app: String, words: Int)] {
        var sum: [String: Int] = [:]
        for d in days { for (k, v) in d.appBreakdown { sum[k, default: 0] += v } }
        return sum.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    /// ~40 wpm typing speed, ~5 chars per word saved per accepted word.
    static func timeSaved(words: Int) -> String {
        let minutes = Double(words) / 40.0
        if minutes < 1 { return L("< 1 minute", "< 1 minuto") }
        if minutes < 60 { return "≈\(Int(minutes.rounded())) " + L("minutes", "minuti") }
        return String(format: "≈%.1f ", locale: Fmt.locale, minutes / 60) + L("hours", "ore")
    }

    /// Accepting words with Tab is rapid-fire: batch the disk writes instead of one per keypress.
    private var saveScheduled = false
    private func scheduleSave() {
        guard persist, !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.flush() }
    }

    /// Writes pending stats now (also called on quit).
    func flush() {
        saveScheduled = false
        guard persist else { return }
        let s = Stored(days: days, perApp: perApp)
        if let data = try? JSONEncoder().encode(s) { SecureFile.write(data, to: url) }
    }
}

/// Power source state, updated by an IOKit notification (no polling).
enum Power {
    private static let initial = readState()
    private(set) static var onBattery: Bool = initial.onBattery
    /// Battery charge in percent (100 on desktops). Refreshed by the same IOKit notification.
    private(set) static var batteryLevel: Int = initial.level
    private static var source: CFRunLoopSource?
    static let changed = Notification.Name("NexoLLMPowerSourceChanged")

    private static func readState() -> (onBattery: Bool, level: Int) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (false, 100) }
        let onBat = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSBatteryPowerValue
        var level = 100
        if let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                   let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    level = cur * 100 / max
                    break
                }
            }
        }
        return (onBat, level)
    }

    /// Starts listening for plug/unplug and low-battery threshold crossings; posts `Power.changed` on the main thread.
    static func startMonitoring() {
        guard source == nil else { return }
        let callback: IOPowerSourceCallbackType = { _ in
            let wasLow = Power.batteryLevel <= 20
            let next = Power.readState()
            Power.batteryLevel = next.level
            let crossedLow = Power.onBattery && ((next.level <= 20) != wasLow)
            if next.onBattery != Power.onBattery || crossedLow {
                Power.onBattery = next.onBattery
                NotificationCenter.default.post(name: Power.changed, object: nil)
            }
        }
        if let s = IOPSNotificationCreateRunLoopSource(callback, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
            source = s
        }
    }
}
