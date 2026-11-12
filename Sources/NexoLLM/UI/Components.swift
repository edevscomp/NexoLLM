import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Layout

/// Lays its children out left to right and wraps to a new line when the next one doesn't fit, so rows of
/// buttons, chips and key hints stay inside their card whatever the language.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8
    /// Children of one line are aligned on their first text baseline when true, centered otherwise.
    var alignToBaseline = false

    private func lines(_ sizes: [CGSize], width: CGFloat) -> [[Int]] {
        var out: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, s) in sizes.enumerated() {
            if !out[out.count - 1].isEmpty, x + hSpacing + s.width > width {
                out.append([]); x = 0
            }
            x += (out[out.count - 1].isEmpty ? 0 : hSpacing) + s.width
            out[out.count - 1].append(i)
        }
        return out
    }

    private func sizes(_ subviews: Subviews, width: CGFloat) -> [CGSize] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil)) }
    }

    /// Height of a line and each child's vertical offset in it.
    private func metrics(_ line: [Int], _ s: [CGSize], _ subviews: Subviews) -> (height: CGFloat, offsets: [CGFloat]) {
        guard alignToBaseline else {
            let lh = line.map { s[$0].height }.max() ?? 0
            return (lh, line.map { (lh - s[$0].height) / 2 })
        }
        let baselines = line.map { subviews[$0].dimensions(in: ProposedViewSize(s[$0]))[VerticalAlignment.firstTextBaseline] }
        let base = baselines.max() ?? 0
        let offsets = baselines.map { base - $0 }
        let lh = zip(line, offsets).map { s[$0.0].height + $0.1 }.max() ?? 0
        return (lh, offsets)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let s = sizes(subviews, width: width)
        var w: CGFloat = 0, h: CGFloat = 0
        for (n, line) in lines(s, width: width).enumerated() {
            let lw = line.reduce(0) { $0 + s[$1].width } + hSpacing * CGFloat(max(0, line.count - 1))
            w = max(w, lw)
            h += (n > 0 ? vSpacing : 0) + metrics(line, s, subviews).height
        }
        return CGSize(width: width.isFinite ? min(w, width) : w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let s = sizes(subviews, width: bounds.width)
        var y = bounds.minY
        for line in lines(s, width: bounds.width) {
            let m = metrics(line, s, subviews)
            var x = bounds.minX
            for (k, i) in line.enumerated() {
                subviews[i].place(at: CGPoint(x: x, y: y + m.offsets[k]), proposal: ProposedViewSize(s[i]))
                x += s[i].width + hSpacing
            }
            y += m.height + vSpacing
        }
    }
}

// MARK: - Rows

/// A System-Settings-style row: title (with an ⓘ that explains the setting) and an optional current
/// value under it on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let info: String?
    let detail: String?
    let indent: Bool
    let control: Control

    init(_ title: String, _ info: String? = nil, detail: String? = nil, indent: Bool = false,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.info = info
        self.detail = detail
        self.indent = indent
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let info, !info.isEmpty { InfoButton(text: info) }
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.leading, indent ? 22 : 0)
        .overlay(alignment: .leading) {
            if indent {   // tree guide for dependent options
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 2).padding(.vertical, 2).padding(.leading, 7)
            }
        }
    }
}

extension SettingRow where Control == EmptyView {
    init(_ title: String, _ info: String? = nil, detail: String? = nil, indent: Bool = false) {
        self.init(title, info, detail: detail, indent: indent) { EmptyView() }
    }
}

/// ⓘ next to a setting: opens a small popover that grows out of the icon.
struct InfoButton: View {
    let text: String
    @State private var shown = false
    @State private var hover = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: shown ? "info.circle.fill" : "info.circle")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(shown || hover ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 264, alignment: .leading)
                .padding(14)
        }
        .help(text)
        .accessibilityLabel(L("More about this setting", "Altro su questa impostazione"))
    }
}

/// Row with a trailing switch.
struct ToggleRow: View {
    let title: String
    var description: String? = nil
    var indent = false
    @Binding var isOn: Bool

    init(_ title: String, _ description: String? = nil, indent: Bool = false, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self.indent = indent
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, description, indent: indent) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(AuroraToggleStyle())
        }
    }
}

/// Row with a trailing menu picker over a CaseIterable enum.
struct EnumPickerRow<Value: CaseIterable & Identifiable & Hashable>: View where Value.AllCases: RandomAccessCollection {
    let title: String
    var description: String? = nil
    @Binding var selection: Value
    let label: (Value) -> String

    init(_ title: String, _ description: String? = nil, selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.title = title
        self.description = description
        self._selection = selection
        self.label = label
    }

    var body: some View {
        SettingRow(title, description) {
            GlassMenuPicker($selection, label: label)
        }
    }
}

/// Small status label ("Granted", "Ready", …) as a glowing pill.
struct StatusLabel: View {
    let text: String
    var ok = true
    var body: some View {
        StatusPill(text: text,
                   symbol: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                   color: ok ? Theme.mint : Theme.amber)
    }
}

// MARK: - Sidebar icon

/// Flat colored squircle with an SF Symbol.
struct SidebarIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(shape.fill(color))
    }
}

// MARK: - Helpers

enum SettingsUI {
    /// Lets the user pick a .gguf model file. Returns its path, or nil when cancelled.
    @MainActor static func chooseGGUF(startingAt path: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.title = L("Choose a GGUF model", "Scegli un modello GGUF")
        panel.prompt = L("Choose", "Scegli")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        }
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    static func fileName(_ path: String) -> String {
        path.isEmpty ? L("None", "Nessuno") : (path as NSString).lastPathComponent
    }
}

/// Resolves bundle IDs to display names and icons (cached).
enum AppInfo {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(_ id: String) -> String {
        if let n = names[id] { return n }
        var n = id
        if let url = url(id) {
            n = FileManager.default.displayName(atPath: url.path)
            if n.hasSuffix(".app") { n = String(n.dropLast(4)) }
        }
        names[id] = n
        return n
    }

    static func icon(_ id: String) -> NSImage {
        if let i = icons[id] { return i }
        let i: NSImage
        if let url = url(id) {
            i = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            i = NSWorkspace.shared.icon(for: .application)
        }
        icons[id] = i
        return i
    }
}
