import AppKit
import SwiftUI

struct StatisticsPane: View {
    @ObservedObject private var stats = Stats.shared
    @ObservedObject private var settings = Settings.shared
    @State private var range: TimeRange = .week
    @State private var grouping: Grouping = .day

    enum TimeRange: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: return L("Last 7 Days", "Ultimi 7 giorni")
            case .month: return L("Last 30 Days", "Ultimi 30 giorni")
            case .quarter: return L("Last 90 Days", "Ultimi 90 giorni")
            case .year: return L("Last Year", "Ultimo anno")
            }
        }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day: return L("By Day", "Per giorno")
            case .week: return L("By Week", "Per settimana")
            case .month: return L("By Month", "Per mese")
            }
        }
        var component: Calendar.Component {
            switch self { case .day: return .day; case .week: return .weekOfYear; case .month: return .month }
        }
    }

    /// Every day in the selected range (oldest first), including empty ones.
    private var rangeDays: [(Date, Stats.Day)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<range.rawValue).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (d, stats.day(d))
        }
    }

    var body: some View {
        let days = rangeDays
        let dayValues = days.map(\.1)
        let words = dayValues.reduce(0) { $0 + $1.words }
        let totals = Stats.appTotals(dayValues)
        let palette = AppPalette(ranked: totals.map(\.app))
        let buckets = StackedBucket.make(days: days, grouping: grouping, palette: palette)
        let nextKey = settings.prefs.nextWordShortcut.display
        let fullKey = settings.prefs.fullCompletionShortcut.display

        GlassPage {
            GlassSection(L("Activity", "Attività")) {
                HStack(spacing: 10) {
                    GlassMenuPicker($range) { $0.label }
                    GlassMenuPicker($grouping) { $0.label }
                    Spacer()
                    HStack(spacing: 5) {
                        Text(Fmt.number(words))
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text(L("words written", "parole scritte"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        InfoButton(text: L("Only words inserted by pressing \(nextKey) or \(fullKey) on a suggestion are counted.",
                                           "Vengono contate solo le parole inserite premendo \(nextKey) o \(fullKey) su un suggerimento."))
                    }
                }
                StackedPastelHistogram(buckets: buckets, grouping: grouping, palette: palette)
                    .frame(height: 240)
                    .id("\(range.rawValue)-\(grouping.rawValue)")
            }

            GlassSection(L("Words by App", "Parole per app")) {
                if totals.isEmpty {
                    SettingRow(L("Nothing yet", "Ancora niente"),
                               detail: L("Accept a few suggestions to see where NexoLLM helps you most.", "Accetta qualche suggerimento per vedere dove NexoLLM ti aiuta di più."))
                }
                ForEach(Array(palette.legend(totals).enumerated()), id: \.offset) { _, row in
                    AppWordsRow(app: row.app, words: row.words, share: words > 0 ? Double(row.words) / Double(words) : 0,
                                color: palette.color(row.app))
                }
            }
        }
    }
}

// MARK: - Pastel palette

/// Soft, muted pastels assigned by rank: the app you use most always gets the first color.
struct AppPalette {
    /// Group shown for the long tail and for words recorded before per-app days existed.
    static let others = "_others"
    static let maxApps = 6

    private static let tones: [(light: (Double, Double, Double), dark: (Double, Double, Double))] = [
        ((0.722, 0.710, 0.957), (0.557, 0.541, 0.839)),   // lavender
        ((0.659, 0.878, 0.808), (0.435, 0.722, 0.635)),   // mint
        ((0.655, 0.824, 0.957), (0.435, 0.651, 0.831)),   // powder sky
        ((0.965, 0.776, 0.710), (0.831, 0.584, 0.502)),   // peach
        ((0.949, 0.875, 0.659), (0.788, 0.698, 0.451)),   // buttercup
        ((0.937, 0.753, 0.831), (0.769, 0.545, 0.643)),   // rose quartz
    ]
    private static let neutral: (light: (Double, Double, Double), dark: (Double, Double, Double)) = ((0.796, 0.831, 0.882), (0.490, 0.533, 0.600))

    let ranked: [String]

    init(ranked: [String]) {
        self.ranked = Array(ranked.filter { $0 != Stats.otherApp }.prefix(Self.maxApps))
    }

    /// The app's group: itself when it has its own color, otherwise "others".
    func group(_ app: String) -> String { ranked.contains(app) ? app : Self.others }

    func color(_ app: String) -> Color {
        let tone = ranked.firstIndex(of: app).map { Self.tones[$0 % Self.tones.count] } ?? Self.neutral
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = dark ? tone.dark : tone.light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Bottom-to-top stacking order.
    var order: [String] { ranked + [Self.others] }

    /// Totals folded into colored groups, in stacking order.
    func legend(_ totals: [(app: String, words: Int)]) -> [(app: String, words: Int)] {
        var sum: [String: Int] = [:]
        for t in totals { sum[group(t.app), default: 0] += t.words }
        return order.compactMap { k in sum[k].flatMap { $0 > 0 ? (k, $0) : nil } }
    }

    static func displayName(_ app: String) -> String {
        app == others || app == Stats.otherApp ? L("Other apps", "Altre app") : AppInfo.name(app)
    }
}

// MARK: - Histogram

struct StackedBucket: Identifiable {
    struct Segment: Identifiable { let app: String; let words: Int; var id: String { app } }
    let date: Date
    var segments: [Segment]
    var total: Int { segments.reduce(0) { $0 + $1.words } }
    var id: Date { date }

    static func make(days: [(Date, Stats.Day)], grouping: StatisticsPane.Grouping, palette: AppPalette) -> [StackedBucket] {
        let cal = Calendar.current
        var starts: [Date] = []
        var sums: [Date: [String: Int]] = [:]
        for (date, day) in days {
            let start = cal.dateInterval(of: grouping.component, for: date)?.start ?? date
            if sums[start] == nil { starts.append(start); sums[start] = [:] }
            for (app, w) in day.appBreakdown { sums[start]![palette.group(app), default: 0] += w }
        }
        return starts.map { s in
            let m = sums[s] ?? [:]
            return StackedBucket(date: s, segments: palette.order.compactMap { k in
                m[k].flatMap { $0 > 0 ? Segment(app: k, words: $0) : nil }
            })
        }
    }
}

/// One column per period, split into soft pastel blocks per app. Hovering a block fades in its app and words.
struct StackedPastelHistogram: View {
    let buckets: [StackedBucket]
    let grouping: StatisticsPane.Grouping
    let palette: AppPalette
    /// Used by `--render-ui` to showcase the hover tooltip on a specific column index without affecting runtime state.
    static var previewHoverBucketIndex: Int? = nil
    @State private var hover: HoverKey?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct HoverKey: Equatable { let date: Date; let app: String }

    private let axisWidth: CGFloat = 38
    private let labelHeight: CGFloat = 18

    var body: some View {
        let maxValue = max(1, buckets.map(\.total).max() ?? 0)
        let scale = Self.niceCeiling(maxValue)
        let nonEmpty = buckets.filter { $0.total > 0 }
        let average = nonEmpty.isEmpty ? 0 : Double(nonEmpty.reduce(0) { $0 + $1.total }) / Double(buckets.count)

        GeometryReader { geo in
            let plotW = max(1, geo.size.width - axisWidth)
            let plotH = max(1, geo.size.height - labelHeight)
            let slot = plotW / CGFloat(max(1, buckets.count))
            let barW = max(2, min(34, slot * 0.62))
            let labelEvery = max(1, Int((44 / slot).rounded(.up)))

            ZStack(alignment: .topLeading) {
                // Grid and Y labels.
                ForEach(0...4, id: \.self) { i in
                    let v = scale * i / 4
                    let y = plotH - plotH * CGFloat(v) / CGFloat(scale)
                    Path { p in p.move(to: CGPoint(x: axisWidth, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(Color.primary.opacity(i == 0 ? 0.16 : 0.08), style: StrokeStyle(lineWidth: 0.5, dash: i == 0 ? [] : [3, 3]))
                    Text(Fmt.number(v))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: axisWidth - 6, alignment: .trailing)
                        .position(x: (axisWidth - 6) / 2, y: y)
                }

                // Columns.
                ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, b in
                    let x = axisWidth + slot * (CGFloat(idx) + 0.5)
                    column(b, width: barW, plotH: plotH, scale: scale)
                        .frame(width: barW, height: plotH, alignment: .bottom)
                        .position(x: x, y: plotH / 2)
                    if idx % labelEvery == 0 {
                        Text(label(b.date))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .position(x: x, y: plotH + labelHeight / 2 + 2)
                    }
                }

                // Average.
                if average > 0 {
                    let y = plotH - plotH * CGFloat(average) / CGFloat(scale)
                    Path { p in p.move(to: CGPoint(x: axisWidth, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                    Text(L("avg", "media") + " \(Fmt.number(Int(average.rounded())))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: geo.size.width - 26, y: max(7, y - 8))
                        .allowsHitTesting(false)
                }

                if buckets.allSatisfy({ $0.total == 0 }) {
                    Text(L("No words accepted in this period", "Nessuna parola accettata in questo periodo"))
                        .font(.callout).foregroundStyle(.tertiary)
                        .frame(width: plotW, height: plotH)
                        .offset(x: axisWidth)
                }

                // Tooltip.
                let activeHover: HoverKey? = hover ?? Self.previewHoverBucketIndex.flatMap { idx in
                    guard buckets.indices.contains(idx), let topSeg = buckets[idx].segments.first else { return nil }
                    return HoverKey(date: buckets[idx].date, app: topSeg.app)
                }
                if let activeHover, let bIdx = buckets.firstIndex(where: { $0.date == activeHover.date }),
                   let seg = buckets[bIdx].segments.first(where: { $0.app == activeHover.app }) {
                    let b = buckets[bIdx]
                    let below = b.segments.prefix { $0.app != activeHover.app }.reduce(0) { $0 + $1.words }
                    let segTop = plotH - plotH * CGFloat(below + seg.words) / CGFloat(scale)
                    let x = axisWidth + slot * (CGFloat(bIdx) + 0.5)
                    HistogramTooltip(app: seg.app, words: seg.words, period: tooltipPeriod(b.date), color: palette.color(seg.app))
                        .fixedSize()
                        .position(x: min(max(x, 90), geo.size.width - 90), y: max(30, segTop - 34))
                        .id(activeHover.date.timeIntervalSince1970.description + activeHover.app)
                        .transition(.opacity.combined(with: .offset(y: 3)))
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: hover)
    }

    /// Bottom-up blocks; a hair of space between them keeps them soft and distinct.
    private func column(_ b: StackedBucket, width: CGFloat, plotH: CGFloat, scale: Int) -> some View {
        let gap: CGFloat = b.segments.count > 1 ? 1.5 : 0
        return VStack(spacing: gap) {
            ForEach(b.segments.reversed()) { seg in
                let key = HoverKey(date: b.date, app: seg.app)
                let h = max(2, plotH * CGFloat(seg.words) / CGFloat(scale) - gap)
                RoundedRectangle(cornerRadius: min(5, width / 3), style: .continuous)
                    .fill(palette.color(seg.app))
                    .brightness(hover == key ? 0.06 : 0)
                    .opacity(hover == nil || hover == key ? 1 : 0.55)
                    .frame(width: width, height: h)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hover = key }
                        else {
                            // Moving to the next block: let its hover arrive first, so the card doesn't blink.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { if hover == key { hover = nil } }
                        }
                    }
            }
        }
    }

    private func label(_ d: Date) -> String {
        switch grouping {
        case .day: return buckets.count <= 7 ? d.formatted(.dateTime.weekday(.abbreviated).locale(Fmt.locale))
                                             : d.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale))
        case .week: return d.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale))
        case .month: return d.formatted(.dateTime.month(.abbreviated).locale(Fmt.locale))
        }
    }

    private func tooltipPeriod(_ d: Date) -> String {
        switch grouping {
        case .day: return d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Fmt.locale))
        case .week: return L("Week of \(d.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale)))",
                             "Settimana del \(d.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale)))")
        case .month: return d.formatted(.dateTime.month(.wide).year().locale(Fmt.locale))
        }
    }

    /// Four grid steps of 1, 2 or 5 × 10ⁿ above the value, so grid lines land on round numbers.
    static func niceCeiling(_ v: Int) -> Int {
        guard v > 4 else { return 4 }
        let need = Double(v) / 4
        var p = 1
        while true {
            for m in [1, 2, 5] where Double(m * p) >= need { return m * p * 4 }
            p *= 10
        }
    }
}

private struct HistogramTooltip: View {
    let app: String
    let words: Int
    let period: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if app == AppPalette.others || app == Stats.otherApp {
                    Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Image(nsImage: AppInfo.icon(app)).resizable()
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(AppPalette.displayName(app)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                Text("\(Fmt.number(words)) " + (words == 1 ? L("word", "parola") : L("words", "parole")) + " · " + period)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

/// App, its pastel color and its words: no progress bar.
private struct AppWordsRow: View {
    let app: String
    let words: Int
    let share: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 9, height: 9)
            Group {
                if app == AppPalette.others {
                    Image(systemName: "square.grid.2x2").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Image(nsImage: AppInfo.icon(app)).resizable()
                }
            }
            .frame(width: 20, height: 20)
            Text(AppPalette.displayName(app)).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer()
            Text("\(Fmt.number(words)) " + L("words", "parole"))
                .font(.system(size: 12).monospacedDigit())
            Text(share.formatted(.percent.precision(.fractionLength(0)).locale(Fmt.locale)))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
