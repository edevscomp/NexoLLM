import AppKit
import SwiftUI

// MARK: - Panel base

/// Hosting view that accepts first-mouse clicks on non-activating panels and allows window dragging from non-control backgrounds.
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Borderless, non-activating floating panel hosting a SwiftUI view.
final class FloatingPanel: NSPanel {
    private let host = FirstMouseHostingView(rootView: AnyView(EmptyView()))

    init(clickThrough: Bool) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        isMovableByWindowBackground = !clickThrough
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        canHide = false   // ⌘H / Hide Others never hide an overlay behind the app's back
        alphaValue = 1
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Sets the content and returns its fitting size.
    @discardableResult
    func setContent<V: View>(_ view: V) -> NSSize {
        host.rootView = AnyView(view)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// Shows the panel at `frame`, always fully opaque. The window's alpha is never animated: an
    /// interrupted fade left the WindowServer surface at ~0 while the panel still counted as visible.
    /// `entrance`/`offset` are kept for callers; `animateResize` eases a size change of a visible panel.
    func place(_ frame: NSRect, entrance: Bool = false, offset: CGVector = CGVector(dx: -2, dy: 0), animateResize: Bool = false) {
        let f = frame.integral
        alphaValue = 1
        if animateResize, isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, f.size != self.frame.size {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(f, display: true)
            }
        } else {
            setFrame(f, display: true)
        }
        orderFrontRegardless()
    }

    func hide() {
        alphaValue = 1
        if isVisible { orderOut(nil) }
    }
}

private func screenFor(_ p: CGPoint) -> NSScreen? {
    NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main
}

// MARK: - Ghost suggestion

/// What the suggestion overlay is showing.
enum GhostStyle {
    /// Grey text right after the caret (end of line).
    case inline
    /// Floating bubble below the caret (mid-line suggestions, typo fixes, emoticons).
    case bubble
}

/// Keyboard key hint. `highlighted` = aurora key (primary action).
struct KeyCap: View {
    let label: String
    var highlighted = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4.5, style: .continuous)
        Text(label)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(highlighted ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(shape.fill(highlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.08))))
            .overlay(shape.strokeBorder(Color.primary.opacity(highlighted ? 0 : 0.12), lineWidth: 0.6))
            .fixedSize()
            .layoutPriority(1)
    }
}

/// Ghost text colors that contrast with the page under the caret (see `Backdrop`), not with the system
/// appearance. Solid colors, never translucent label colors (those vanished on white pages in dark mode).
/// `tinted`: a soft accent hue with the same contrast (≥ 3.4:1 on white and on black for `.unknown`).
enum GhostPalette {
    static func colors(_ tone: Backdrop.Tone, tinted: Bool = Settings.shared.prefs.ghostTint) -> (head: Color, tail: Color) {
        switch (tone, tinted) {
        case (.light, false): return (Color(white: 0.28), Color(white: 0.50))
        case (.dark, false): return (Color(white: 0.86), Color(white: 0.62))
        case (.unknown, false): return (Color(white: 0.44), Color(white: 0.55))   // ≥ 3.4:1 on white and on black
        case (.light, true): return (Color(red: 0.24, green: 0.30, blue: 0.72), Color(red: 0.38, green: 0.43, blue: 0.72))
        case (.dark, true): return (Color(red: 0.68, green: 0.74, blue: 0.98), Color(red: 0.52, green: 0.58, blue: 0.84))
        case (.unknown, true): return (Color(red: 0.36, green: 0.42, blue: 0.86), Color(red: 0.45, green: 0.50, blue: 0.78))
        }
    }
}

struct InlineGhostView: View {
    let text: String
    let fontSize: CGFloat
    let keyLabel: String
    /// Leading part inserted by the next-word key: drawn stronger so you see what one press takes.
    var head = ""
    var tone: Backdrop.Tone = .unknown
    var body: some View {
        HStack(spacing: 5) {
            ghostText
                .font(.system(size: fontSize))
                .lineLimit(1)
                .fixedSize()
                .opacity(max(0.5, min(1, Settings.shared.prefs.ghostOpacity)))
            KeyCap(label: keyLabel, highlighted: true)
        }
        .padding(.trailing, 3)
    }

    private var ghostText: Text {
        let c = GhostPalette.colors(tone)
        guard !head.isEmpty, head.count < text.count, text.hasPrefix(head) else {
            return Text(text).foregroundColor(head.isEmpty ? c.tail : c.head)
        }
        return Text(head).foregroundColor(c.head) + Text(String(text.dropFirst(head.count))).foregroundColor(c.tail)
    }
}

struct BubbleView: View {
    let content: AnyView
    let keyLabel: String
    var body: some View {
        HStack(spacing: 8) {
            content
            KeyCap(label: keyLabel, highlighted: true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .overlayGlass(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
        .padding(8)
    }
}

/// Grey ghost text (or a bubble) next to the caret.
final class GhostOverlay {
    private var panel = FloatingPanel(clickThrough: true)

    /// A fresh window: macOS can silently drop a long-lived borderless panel's surface (spaces, sleep).
    func rebuildPanel() { panel.hide(); panel = FloatingPanel(clickThrough: true); shownText = ""; shownStyle = nil }

    /// Places the panel; if it didn't come on screen, rebuilds it once and tries again.
    private var content = AnyView(EmptyView())
    private func setContent<V: View>(_ view: V) -> NSSize { content = AnyView(view); return panel.setContent(content) }
    private func place(_ frame: NSRect, entrance: Bool, offset: CGVector = CGVector(dx: -2, dy: 0)) {
        panel.place(frame, entrance: entrance, offset: offset)
        guard !panel.isVisible else { return }
        Log.info("overlay: suggestion panel was not visible — rebuilt")
        let (text, style) = (shownText, shownStyle)
        rebuildPanel()
        (shownText, shownStyle) = (text, style)
        panel.setContent(content)
        panel.place(frame, entrance: entrance, offset: offset)
    }
    /// On screen, opaque *and* wide enough to read: Tab must never accept something unseen.
    var isVisible: Bool { panel.isVisible && panel.alphaValue > 0.9 && panel.frame.width >= 10 }
    /// What's on screen, to tell a new suggestion (animated in) from the same one getting shorter as the
    /// user types or accepts it (moved instantly, never re-animated).
    private var shownText = ""
    private var shownStyle: GhostStyle?

    private func isNew(_ text: String, _ style: GhostStyle) -> Bool {
        defer { shownText = text; shownStyle = style }
        return !panel.isVisible || shownStyle != style || !shownText.hasSuffix(text)
    }

    func showInline(_ text: String, caretAX: CGRect, fontSize: CGFloat?, keyLabel: String, head: String = "",
                    tone: Backdrop.Tone = .unknown) {
        guard !text.isEmpty else { hide(); return }
        let caret = Geometry.toCocoa(caretAX)
        let size = fontSize ?? max(10, min(30, caret.height * 0.78))
        let fitting = setContent(InlineGhostView(text: text, fontSize: size, keyLabel: keyLabel, head: head, tone: tone))
        var width = fitting.width
        let x = caret.minX + 1
        if let s = screenFor(CGPoint(x: caret.minX, y: caret.midY)) { width = min(width, max(0, s.visibleFrame.maxX - x)) }
        // No room after the caret (right edge of the screen, or an app reporting a caret out there):
        // show it in a bubble below the line instead of an invisible sliver.
        if width < 48 {
            showBubble(Text(text.trimmingCharacters(in: .whitespaces)).font(.system(size: 12.5)), caretAX: caretAX,
                       keyLabel: keyLabel, id: text)
            return
        }
        let y = caret.midY - fitting.height / 2
        place(NSRect(x: x, y: y, width: width, height: fitting.height), entrance: isNew(text, .inline))
    }

    /// Bubble below the caret line. `content` is the main label (e.g. text, or strikethrough + fix).
    func showBubble<V: View>(_ content: V, caretAX: CGRect, keyLabel: String, id: String = "") {
        let caret = Geometry.toCocoa(caretAX)
        let fitting = setContent(BubbleView(content: AnyView(content), keyLabel: keyLabel))
        var x = caret.minX - 14
        var y = caret.minY - fitting.height + 2           // just below the line
        if let s = screenFor(CGPoint(x: caret.minX, y: caret.midY)) {
            x = min(max(x, s.visibleFrame.minX), s.visibleFrame.maxX - fitting.width)
            if y < s.visibleFrame.minY { y = caret.maxY - 2 }  // no room below: go above
        }
        place(NSRect(x: x, y: y, width: fitting.width, height: fitting.height),
              entrance: isNew(id, .bubble), offset: CGVector(dx: 0, dy: 2))
    }

    func hide() { panel.hide(); shownText = ""; shownStyle = nil }
}

// MARK: - Toast (manual screen capture feedback & top error banner)

private struct ToastView: View {
    let symbol: String
    let text: String
    let busy: Bool
    var topBanner: Bool = false

    var body: some View {
        HStack(spacing: topBanner ? 9 : 7) {
            if busy {
                ProgressView().controlSize(.mini).scaleEffect(0.85)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: topBanner ? 12.5 : 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Text(text)
                .font(.system(size: topBanner ? 12.5 : 11.5, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, topBanner ? 16 : 11)
        .padding(.vertical, topBanner ? 9 : 5.5)
        .overlayGlass(in: RoundedRectangle(cornerRadius: topBanner ? 12 : 999, style: .continuous))
        .shadow(color: .black.opacity(topBanner ? 0.20 : 0.14), radius: topBanner ? 12 : 6, y: topBanner ? 4 : 2)
        .padding(8)
    }
}

/// Small capsule above the caret (or a top-centered banner right below the menu bar when `nearAX` is `nil`). Hides itself.
final class ToastOverlay {
    private var panel = FloatingPanel(clickThrough: true)
    func rebuildPanel() { hide(); panel = FloatingPanel(clickThrough: true) }
    private var hideWork: DispatchWorkItem?

    func show(_ text: String, symbol: String = "camera.viewfinder", busy: Bool = false, nearAX caretAX: CGRect?,
              duration: TimeInterval = 1.8) {
        let isTopBanner = (caretAX == nil)
        let fitting = panel.setContent(ToastView(symbol: symbol, text: text, busy: busy, topBanner: isTopBanner))
        var origin: NSPoint
        if let caretAX {
            let caret = Geometry.toCocoa(caretAX)
            origin = NSPoint(x: caret.minX - 14, y: caret.maxY + 2)
            if let s = screenFor(CGPoint(x: caret.minX, y: caret.midY)) {
                origin.x = min(max(origin.x, s.visibleFrame.minX), s.visibleFrame.maxX - fitting.width)
                if origin.y + fitting.height > s.visibleFrame.maxY { origin.y = caret.minY - fitting.height - 2 }
            }
        } else {
            let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            let s = mouseScreen?.visibleFrame ?? .zero
            origin = NSPoint(x: s.midX - fitting.width / 2, y: s.maxY - fitting.height - 14)
        }
        panel.place(NSRect(origin: origin, size: fitting), entrance: !panel.isVisible, offset: CGVector(dx: 0, dy: -2))
        hideWork?.cancel()
        guard !busy else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.hide()
        panel.setContent(EmptyView())   // drop the hosted view: nothing stays alive offscreen
    }
}

// MARK: - Numbered list (emoji, alternatives, synonyms)

struct ListItem: Identifiable {
    let id = UUID()
    let leading: String     // e.g. emoji glyph; may be empty
    let title: String
}

struct ListPanelView: View {
    let header: String
    let items: [ListItem]
    /// Alternatives: which list is showing; the same shortcut switches to the other one.
    var scope: AlternativesScope?
    var switchKey = "⌥⇥"
    /// Highlighted row (moved with ↑/↓, inserted with ↩/⇥).
    var selected = 0
    var onSelect: ((Int) -> Void)?
    /// Results on their way: placeholder rows instead of an empty wait.
    var loading = false

    private var symbol: String {
        switch header.lowercased() {
        case "emoji": return "face.smiling"
        case "synonyms", "sinonimi": return "character.book.closed"
        default: return "sparkles"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let scope {
                    HStack(spacing: 2) {
                        ForEach(AlternativesScope.allCases) { s in
                            Text(s.label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(s == scope ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(s == scope ? Theme.accent : Color.clear))
                        }
                    }
                    .padding(2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                    Spacer(minLength: 8)
                    KeyCap(label: "← →", highlighted: true)
                    KeyCap(label: switchKey, highlighted: true)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(header.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 3)
            .padding(.bottom, 4)
            if loading && items.isEmpty {
                ForEach(0..<4, id: \.self) { i in SkeletonRow(width: [120, 88, 104, 72][i]) }
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                Button {
                    onSelect?(i)
                } label: {
                    HStack(spacing: 9) {
                        KeyCap(label: "\(i + 1)", highlighted: i == selected)
                        if !item.leading.isEmpty { Text(item.leading).font(.system(size: 15)) }
                        Text(item.title)
                            .font(.system(size: 12.5, weight: i == selected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        if i == selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent.opacity(0.14))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .frame(minWidth: 200, alignment: .leading)
        .overlayGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .padding(10)
    }
}

/// Placeholder row while results are computed: a gentle pulse that ends when the list is filled.
private struct SkeletonRow: View {
    let width: CGFloat
    @State private var dim = false

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(Color.primary.opacity(0.10)).frame(width: 16, height: 14)
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.10)).frame(width: width, height: 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .opacity(dim ? 0.45 : 1)
        .onAppear {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
        }
    }
}

final class ListOverlay {
    /// Clickable but non-activating: picking a row never takes focus from the app you're typing in.
    private var panel = FloatingPanel(clickThrough: false)
    func rebuildPanel() { hide(); panel = FloatingPanel(clickThrough: false) }
    private(set) var items: [ListItem] = []
    private(set) var selectedIndex = 0
    private(set) var loading = false
    var isVisible: Bool { panel.isVisible && (!items.isEmpty || loading) }
    /// A row was clicked.
    var onPick: ((Int) -> Void)?
    private var header = ""
    private var scope: AlternativesScope?
    private var switchKey = "⌥⇥"

    private func view() -> ListPanelView {
        ListPanelView(header: header, items: items, scope: scope, switchKey: switchKey, selected: selectedIndex,
                      onSelect: { [weak self] i in self?.onPick?(i) }, loading: loading)
    }

    /// ↑/↓: moves the highlight, wrapping around.
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + items.count) % items.count
        panel.setContent(view())
    }

    /// Opens the list right away with placeholder rows; `show` fills it in.
    func showLoading(header: String, belowAX rect: CGRect, scope: AlternativesScope? = nil, switchKey: String = "⌥⇥") {
        items = []; loading = true
        present(header: header, belowAX: rect, scope: scope, switchKey: switchKey)
    }

    func show(header: String, items: [ListItem], belowAX rect: CGRect, scope: AlternativesScope? = nil, switchKey: String = "⌥⇥") {
        guard !items.isEmpty else { hide(); return }
        self.items = items; loading = false
        present(header: header, belowAX: rect, scope: scope, switchKey: switchKey)
    }

    private func present(header: String, belowAX rect: CGRect, scope: AlternativesScope?, switchKey: String) {
        self.header = header; self.scope = scope; self.switchKey = switchKey; selectedIndex = 0
        let anchor = Geometry.toCocoa(rect)
        let fitting = panel.setContent(view())
        var x = anchor.minX - 14
        var y = anchor.minY - fitting.height
        if let s = screenFor(CGPoint(x: anchor.minX, y: anchor.midY)) {
            x = min(max(x, s.visibleFrame.minX), s.visibleFrame.maxX - fitting.width)
            if y < s.visibleFrame.minY { y = anchor.maxY }
        }
        panel.place(NSRect(x: x, y: y, width: fitting.width, height: fitting.height),
                    entrance: !panel.isVisible, offset: CGVector(dx: 0, dy: 2), animateResize: true)
    }

    func hide() { items = []; loading = false; selectedIndex = 0; panel.hide() }

    /// The mouse is over the list (a click there picks a row instead of dismissing it).
    func contains(_ point: NSPoint) -> Bool { isVisible && panel.frame.contains(point) }
}

// MARK: - Quick menu (⌃⌥M)

struct QuickMenuItem: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    var badge: String?
    var subitems: [QuickMenuItem] = []
    var keepOpen: Bool = false
    var action: () -> Void = {}
}

struct QuickMenuView: View {
    let status: String
    var statusColor: Color = Theme.mint
    let words: Int
    let items: [QuickMenuItem]
    let selected: Int
    var expandedIndex: Int? = nil
    var selectedSubIndex: Int? = nil
    var onSelect: ((Int) -> Void)?
    var onSelectSubitem: ((Int) -> Void)?
    var onHoverRow: ((Int) -> Void)?
    var onHoverSubitem: ((Int) -> Void)?

    @State private var hoveredRow: Int? = nil
    @State private var hoveredSubRow: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                BrandOrb(size: 15)
                Text(Brand.name).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 10)
                if words > 0 {
                    Text(L("\(Fmt.number(words)) words today", "\(Fmt.number(words)) parole oggi"))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }
            .padding(.horizontal, 6).padding(.top, 3).padding(.bottom, 6)
            Divider().opacity(0.5)
            HStack(spacing: 7) {   // what NexoLLM is doing right now
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(status).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider().opacity(0.5).padding(.bottom, 3)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let isExpanded = expandedIndex == i
                let isHovered = hoveredRow == i
                let isHighlighted = (i == selected && selectedSubIndex == nil) || isExpanded || isHovered
                Button {
                    onSelect?(i)
                } label: {
                    HStack(spacing: 9) {
                        KeyCap(label: "\(i + 1)", highlighted: isHighlighted)
                        Image(systemName: item.symbol)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isHighlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 12.5, weight: isHighlighted ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let badge = item.badge {
                            Text(badge).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        if !item.subitems.isEmpty {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(isExpanded ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                                .rotationEffect(.degrees(isExpanded ? 0 : 0))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHighlighted ? Theme.accent.opacity(isHovered ? 0.20 : (isExpanded ? 0.16 : 0.14)) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredRow = hovering ? i : (hoveredRow == i ? nil : hoveredRow)
                    }
                    if hovering { onHoverRow?(i) }
                }

                if isExpanded, !item.subitems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(item.subitems.enumerated()), id: \.element.id) { j, sub in
                            let isSubHovered = hoveredSubRow == j
                            let isSubSelected = selectedSubIndex == j || isSubHovered
                            Button {
                                onSelectSubitem?(j)
                            } label: {
                                HStack(spacing: 8) {
                                    KeyCap(label: "⇧\(j + 1)", highlighted: isSubSelected)
                                    Image(systemName: sub.symbol)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isSubSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                                        .frame(width: 15)
                                    Text(sub.title)
                                        .font(.system(size: 12, weight: isSubSelected ? .semibold : .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 6)
                                    if let badge = sub.badge {
                                        Text(badge).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                                    }
                                    if !sub.subitems.isEmpty {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(isSubSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                        .fill(isSubSelected ? Theme.accent.opacity(isSubHovered ? 0.20 : 0.15) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredSubRow = hovering ? j : (hoveredSubRow == j ? nil : hoveredSubRow)
                                }
                                if hovering { onHoverSubitem?(j) }
                            }
                        }
                    }
                    .padding(4)
                    .padding(.leading, 14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.84), value: expandedIndex)
        .padding(7)
        .frame(minWidth: 295, alignment: .leading)
        .clipped()
        .overlayGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .padding(10)
    }
}

/// The ⌃⌥M menu: a floating glass list at the mouse cursor. ↑/↓/←/→ + ↩, 1–9 (or ⇧1–⇧9 when a submenu is open) or a click; ⎋ closes it.
/// Never takes focus from the app underneath.
final class QuickMenuOverlay {
    private var panel = FloatingPanel(clickThrough: false)
    func rebuildPanel() { hide(); panel = FloatingPanel(clickThrough: false) }
    private(set) var items: [QuickMenuItem] = []
    private(set) var selectedIndex = 0
    private(set) var expandedIndex: Int? = nil
    private(set) var selectedSubIndex: Int? = nil
    private var parentSubitemsStack: [(index: Int, subitems: [QuickMenuItem], selectedSub: Int)] = []
    private var status = ""
    private var statusColor = Theme.mint
    private var words = 0
    private var anchorTopLeft: NSPoint = .zero
    var isVisible: Bool { panel.isVisible && !items.isEmpty }
    var hasExpandedSubmenu: Bool {
        guard let exp = expandedIndex, exp < items.count else { return false }
        return !items[exp].subitems.isEmpty
    }

    private func view() -> QuickMenuView {
        QuickMenuView(
            status: status,
            statusColor: statusColor,
            words: words,
            items: items,
            selected: selectedIndex,
            expandedIndex: expandedIndex,
            selectedSubIndex: selectedSubIndex,
            onSelect: { [weak self] i in self?.activate(i) },
            onSelectSubitem: { [weak self] j in self?.activateSubitem(j) },
            onHoverRow: { [weak self] i in
                guard let self, i >= 0, i < self.items.count else { return }
                if self.selectedIndex != i || self.selectedSubIndex != nil {
                    self.selectedIndex = i
                    self.selectedSubIndex = nil
                }
            },
            onHoverSubitem: { [weak self] j in
                guard let self, let exp = self.expandedIndex, exp < self.items.count,
                      j >= 0, j < self.items[exp].subitems.count else { return }
                if self.selectedSubIndex != j {
                    self.selectedSubIndex = j
                }
            }
        )
    }

    /// `topLeft`: Cocoa point the menu hangs from.
    func show(status: String, statusColor: Color, words: Int, items: [QuickMenuItem], topLeft: NSPoint) {
        guard !items.isEmpty else { hide(); return }
        self.status = status
        self.statusColor = statusColor
        self.words = words
        self.items = items
        self.selectedIndex = 0
        self.expandedIndex = nil
        self.selectedSubIndex = nil
        self.parentSubitemsStack = []
        self.anchorTopLeft = topLeft
        refreshLayout(entrance: true)
    }

    private func refreshLayout(entrance: Bool = false) {
        let size = panel.setContent(view())
        let currentTopLeft = panel.isVisible ? NSPoint(x: panel.frame.minX + 14, y: panel.frame.maxY) : anchorTopLeft
        var origin = NSPoint(x: currentTopLeft.x - 14, y: currentTopLeft.y - size.height)
        if let s = screenFor(currentTopLeft)?.visibleFrame {
            origin.x = min(max(origin.x, s.minX), s.maxX - size.width)
            origin.y = min(max(origin.y, s.minY), s.maxY - size.height)
        }
        panel.place(NSRect(origin: origin, size: size), entrance: entrance, offset: CGVector(dx: 0, dy: 2), animateResize: false)
    }

    /// ↑ / ↓ navigation: navigates inside the open dropdown if one is expanded, otherwise navigates top-level items.
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        if let exp = expandedIndex, exp < items.count, !items[exp].subitems.isEmpty {
            let subs = items[exp].subitems
            if let cur = selectedSubIndex {
                selectedSubIndex = (cur + delta + subs.count) % subs.count
            } else {
                selectedSubIndex = delta >= 0 ? 0 : (subs.count - 1)
            }
        } else {
            selectedIndex = (selectedIndex + delta + items.count) % items.count
        }
        panel.setContent(view())
    }

    /// → (Right Arrow): opens the selected item's dropdown (or enters a nested submenu like `Translate…`).
    func expandRight() {
        guard !items.isEmpty else { return }
        if let exp = expandedIndex, exp < items.count {
            let subs = items[exp].subitems
            if let subIdx = selectedSubIndex, subIdx >= 0, subIdx < subs.count, !subs[subIdx].subitems.isEmpty {
                parentSubitemsStack.append((index: exp, subitems: subs, selectedSub: subIdx))
                items[exp].subitems = subs[subIdx].subitems
                selectedSubIndex = 0
                refreshLayout()
                return
            }
            if selectedSubIndex == nil, !subs.isEmpty {
                selectedSubIndex = 0
                panel.setContent(view())
                return
            }
        }
        guard selectedIndex >= 0, selectedIndex < items.count, !items[selectedIndex].subitems.isEmpty else { return }
        parentSubitemsStack.removeAll()
        expandedIndex = selectedIndex
        selectedSubIndex = 0
        refreshLayout()
    }

    /// ← (Left Arrow): exits a nested submenu (e.g. `Translate…`) or closes the open dropdown.
    func collapseLeft() {
        if let last = parentSubitemsStack.popLast(), last.index < items.count {
            items[last.index].subitems = last.subitems
            expandedIndex = last.index
            selectedSubIndex = last.selectedSub
            refreshLayout()
            return
        }
        if let exp = expandedIndex {
            selectedIndex = exp
            expandedIndex = nil
            selectedSubIndex = nil
            refreshLayout()
        }
    }

    /// ↩ / ⇥: activates the currently highlighted sub-item when navigating inside a dropdown, or the top-level item.
    func activateCurrent() {
        if let exp = expandedIndex, exp < items.count, let subIdx = selectedSubIndex {
            activateSubitem(subIdx)
        } else {
            activate(selectedIndex)
        }
    }

    func activate(_ index: Int) {
        guard index >= 0 && index < items.count else { return }
        selectedIndex = index
        if !items[index].subitems.isEmpty {
            parentSubitemsStack.removeAll()
            if expandedIndex == index {
                expandedIndex = nil
                selectedSubIndex = nil
            } else {
                expandedIndex = index
                selectedSubIndex = 0
            }
            refreshLayout()
            return
        }
        if items[index].keepOpen {
            items[index].action()
            refreshLayout()
            return
        }
        let action = items[index].action
        hide()
        DispatchQueue.main.async(execute: action)   // never run actions inside the event tap
    }

    /// Activates subitem `subIndex` (0-based, triggered by `Shift + 1..9`, `↩`, or mouse click) ONLY when a dropdown is open.
    func activateSubitem(_ subIndex: Int) {
        guard let exp = expandedIndex, exp < items.count else { return }
        let subs = items[exp].subitems
        guard subIndex >= 0 && subIndex < subs.count else { return }
        selectedSubIndex = subIndex
        let sub = subs[subIndex]
        if !sub.subitems.isEmpty {
            parentSubitemsStack.append((index: exp, subitems: subs, selectedSub: subIndex))
            items[exp].subitems = sub.subitems
            selectedSubIndex = 0
            refreshLayout()
            return
        }
        if sub.keepOpen {
            sub.action()
            refreshLayout()
            return
        }
        let action = sub.action
        hide()
        DispatchQueue.main.async(execute: action)
    }

    func contains(_ point: NSPoint) -> Bool { isVisible && panel.frame.contains(point) }

    func hide() {
        items = []
        expandedIndex = nil
        selectedSubIndex = nil
        parentSubitemsStack = []
        panel.hide()
    }
}

/// What NexoLLM is doing in the focused field (for status reporting).
enum ActivityState { case active, thinking, paused }

// MARK: - Web lookup card (⌃⌥L)

struct LookupCardView: View {
    let query: String
    let card: WebLookup.ResultCard?
    var onSelectArea: (() -> Void)? = nil
    var onAskQuestion: ((String) -> Void)? = nil
    var onClose: () -> Void = {}
    @State private var inputText = ""
    @State private var copied = false

    /// Summary + key points as plain text, for the Copy button.
    nonisolated static func copyText(_ card: WebLookup.ResultCard) -> String {
        ([card.summary] + card.bullets.map { "• " + $0 }).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(L("WEB LOOKUP", "RICERCA WEB")).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let onSelectArea {
                    Button(action: onSelectArea) {
                        HStack(spacing: 4) {
                            Image(systemName: "viewfinder").font(.system(size: 9.5, weight: .semibold))
                            Text(L("Select Area", "Seleziona area")).font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help(L("Drag with the mouse to select any text on screen", "Trascina col mouse per selezionare qualsiasi testo sullo schermo"))
                }
                if let card {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(Self.copyText(card), forType: .string)
                        withAnimation(.easeOut(duration: 0.15)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(copied ? Theme.mint : Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2.5)
                            .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help(L("Copy summary", "Copia il sunto"))
                }
                KeyCap(label: "⎋")
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let onAskQuestion {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    TextField(L("Ask a question or search…", "Fai una domanda o cerca…"), text: $inputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !q.isEmpty { onAskQuestion(q) }
                        }
                    if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !q.isEmpty { onAskQuestion(q) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, 5.5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8))
            }
            Text(query).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if let card {
                Text(card.summary).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !card.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if !card.bulletTitle.isEmpty {
                            Text(card.bulletTitle.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(.tertiary)
                        }
                        ForEach(Array(card.bullets.enumerated()), id: \.offset) { _, b in
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Circle().fill(Theme.accent).frame(width: 5, height: 5).offset(y: -1)
                                Text(b).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
                }
                if !card.sources.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(card.sources.prefix(4)) { s in
                            Button {
                                if WebLookup.isWebLink(s.url) { NSWorkspace.shared.open(s.url) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(s.source).lineLimit(1)
                                    Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini).scaleEffect(0.8)
                    Text(L("Searching live sources…", "Ricerca sulle fonti live…")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                ForEach(0..<3, id: \.self) { i in SkeletonRow(width: [300, 240, 270][i]) }
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .overlayGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .padding(10)
        .onAppear { inputText = query }
    }
}

/// Floating, clickable (non-activating) card with the result of a web lookup, at the cursor.
final class LookupOverlay {
    private var panel = FloatingPanel(clickThrough: false)
    private var query = ""
    var onSelectArea: (() -> Void)?
    var onAskQuestion: ((String) -> Void)?
    var isVisible: Bool { panel.isVisible }
    /// When the card appeared: clicks in the first instant (the one that submitted the search) never close it.
    private(set) var shownAt = Date.distantPast
    var age: TimeInterval { Date().timeIntervalSince(shownAt) }
    /// The answer is on screen (not the "searching…" placeholder): from now on a click elsewhere closes it.
    private(set) var hasResult = false
    /// A click outside the card closes it once the answer is shown; while it's still searching, clicks are ignored.
    func shouldClose(onClickAt point: NSPoint) -> Bool { isVisible && hasResult && age > 0.3 && !contains(point) }

    func rebuildPanel() { hide(); panel = FloatingPanel(clickThrough: false) }

    func showLoading(query: String, nearAX rect: CGRect?) {
        self.query = query
        hasResult = false
        present(LookupCardView(query: query, card: nil,
                               onSelectArea: { [weak self] in self?.onSelectArea?() },
                               onAskQuestion: { [weak self] q in self?.onAskQuestion?(q) },
                               onClose: { [weak self] in self?.hide() }), nearAX: rect)
    }

    func show(card: WebLookup.ResultCard, nearAX rect: CGRect?) {
        hasResult = true
        present(LookupCardView(query: query, card: card,
                               onSelectArea: { [weak self] in self?.onSelectArea?() },
                               onAskQuestion: { [weak self] q in self?.onAskQuestion?(q) },
                               onClose: { [weak self] in self?.hide() }), nearAX: rect)
    }

    private func present(_ view: LookupCardView, nearAX rect: CGRect?) {
        let wasVisible = panel.isVisible
        if !wasVisible { shownAt = Date() }
        let currentOrigin = panel.frame.origin
        let size = panel.setContent(view)
        var origin: NSPoint
        if wasVisible {
            origin = NSPoint(x: currentOrigin.x, y: panel.frame.maxY - size.height)
            if let s = screenFor(origin)?.visibleFrame {
                origin.x = min(max(origin.x, s.minX), s.maxX - size.width)
                origin.y = min(max(origin.y, s.minY), s.maxY - size.height)
            }
        } else if let rect {
            let a = Geometry.toCocoa(rect)
            origin = NSPoint(x: a.minX - 14, y: a.minY - size.height)
            if let s = screenFor(CGPoint(x: a.minX, y: a.midY))?.visibleFrame {
                origin.x = min(max(origin.x, s.minX), s.maxX - size.width)
                if origin.y < s.minY { origin.y = min(a.maxY, s.maxY - size.height) }
            }
        } else {
            let s = NSScreen.main?.visibleFrame ?? .zero
            origin = NSPoint(x: s.midX - size.width / 2, y: s.maxY - size.height - 40)
        }
        panel.place(NSRect(origin: origin, size: size), animateResize: true)
    }

    func hide() { hasResult = false; panel.hide(); panel.setContent(EmptyView()) }

    func contains(_ point: NSPoint) -> Bool { isVisible && panel.frame.contains(point) }
}

// MARK: - Screenshot-style region selector + question prompt for Web Lookup

private final class KeyableOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CrosshairHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }
}

private struct ScreenSelectionView: View {
    @State var query: String
    let onSubmitQuestion: (String) -> Void
    let onSelectRect: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var appeared = false
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var barOffset: CGSize = ScreenSelectionOverlay.currentBarOffset()
    @State private var barDragStart: CGSize = ScreenSelectionOverlay.currentBarOffset()
    @State private var barHovered = false
    @FocusState private var isSearchFocused: Bool

    /// As soon as something is typed, the bar is fully opaque so the text is perfectly readable.
    private var isTypingQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var selectionRect: CGRect? {
        guard let a = dragStart, let b = dragCurrent else { return nil }
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        return r.width > 4 && r.height > 4 ? r : nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Dimmed screen with a normal-brightness cutout over the dragged selection area.
                ZStack {
                    Color.black.opacity(appeared ? 0.44 : 0)
                    if let r = selectionRect {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        if !barHovered { NSCursor.crosshair.set() }
                    case .ended:
                        break
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in
                            NSCursor.crosshair.set()
                            if dragStart == nil { dragStart = v.startLocation }
                            dragCurrent = v.location
                        }
                        .onEnded { v in
                            let a = dragStart ?? v.startLocation
                            let b = v.location
                            let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                            dragStart = nil; dragCurrent = nil
                            if r.width > 12 && r.height > 8 {
                                onSelectRect(r)
                            }
                        }
                )

                if let r = selectionRect {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accent.opacity(0.05)))
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                }

                // Floating, draggable, translucent top prompt bar (remembers position for 10m; fades when selecting behind it).
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Capsule()
                            .fill(Color.primary.opacity(0.24))
                            .frame(width: 28, height: 4)
                            .help(L("Drag to move this search bar (remembers position for 10m)",
                                    "Trascina per spostare la barra (ricorda la posizione per 10 min)"))
                        Image(systemName: "viewfinder").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                        Text(L("Drag on screen to select an area, or ask a question below",
                               "Trascina sullo schermo per selezionare un'area, o fai una domanda qui sotto"))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if barOffset != .zero {
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                    barOffset = .zero
                                    barDragStart = .zero
                                }
                                ScreenSelectionOverlay.resetBarOffset()
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L("Reset position", "Ripristina posizione"))
                        }
                        KeyCap(label: "⎋")
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "globe").foregroundStyle(Theme.accent)
                        TextField(L("Search the web or ask a question…",
                                    "Cerca sul web o fai una domanda…"),
                                  text: $query)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5))
                            .focused($isSearchFocused)
                            .onSubmit {
                                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !q.isEmpty { onSubmitQuestion(q) }
                            }
                        Button(L("Search", "Cerca")) {
                            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !q.isEmpty { onSubmitQuestion(q) }
                        }
                        .buttonStyle(GlassButtonStyle(capsule: true))
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .padding(14)
                .frame(width: 580)
                .overlayGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .opacity(isTypingQuery ? 0.9 : 0))
                .shadow(color: .black.opacity(0.24), radius: 16, y: 6)
                .opacity(dragStart != nil ? 0.14 : (isTypingQuery ? 1.0 : (barHovered ? 0.88 : 0.56)))
                .animation(.easeOut(duration: 0.15), value: isTypingQuery)
                .animation(.easeOut(duration: 0.15), value: barHovered)
                .allowsHitTesting(dragStart == nil)
                .onHover { hovering in
                    barHovered = hovering
                    if hovering {
                        NSCursor.arrow.set()
                    } else {
                        NSCursor.crosshair.set()
                    }
                }
                .padding(.top, 48)
                .offset(barOffset)
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { v in
                            barOffset = CGSize(
                                width: barDragStart.width + v.translation.width,
                                height: barDragStart.height + v.translation.height
                            )
                        }
                        .onEnded { _ in
                            barDragStart = barOffset
                            ScreenSelectionOverlay.saveBarOffset(barOffset)
                        }
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            let saved = ScreenSelectionOverlay.currentBarOffset()
            barOffset = saved
            barDragStart = saved
            NSCursor.crosshair.set()
            isSearchFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                isSearchFocused = true
            }
            withAnimation(.easeOut(duration: 0.18)) { appeared = true }
        }
    }
}

final class ScreenSelectionOverlay {
    private var panel: KeyableOverlayPanel?
    private var keyMonitor: Any?
    var isVisible: Bool { panel?.isVisible ?? false }

    /// Remembers the user's dragged search bar offset for 10 minutes (600 seconds), then resets to default.
    static let positionMemoryDuration: TimeInterval = 600
    private static var savedBarOffset: CGSize = .zero
    private static var savedBarTimestamp: Date?

    static func currentBarOffset(now: Date = Date()) -> CGSize {
        if let ts = savedBarTimestamp, now.timeIntervalSince(ts) < positionMemoryDuration {
            return savedBarOffset
        }
        savedBarOffset = .zero
        savedBarTimestamp = nil
        return .zero
    }

    static func saveBarOffset(_ offset: CGSize, now: Date = Date()) {
        savedBarOffset = offset
        savedBarTimestamp = now
    }

    static func resetBarOffset() {
        savedBarOffset = .zero
        savedBarTimestamp = nil
    }

    func begin(initialQuery: String = "",
               onQuestion: @escaping (String) -> Void,
               onRegion: @escaping (CGRect) -> Void) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let p = KeyableOverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let sFrame = screen.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? sFrame.height
        let view = ScreenSelectionView(
            query: initialQuery,
            onSubmitQuestion: { [weak self] q in
                self?.hide()
                onQuestion(q)
            },
            onSelectRect: { [weak self] localRect in
                self?.hide()
                // Convert top-left SwiftUI view coordinates on `screen` into global AX coordinates.
                let axX = sFrame.minX + localRect.minX
                let axY = (primaryHeight - sFrame.maxY) + localRect.minY
                let region = CGRect(x: axX, y: axY, width: localRect.width, height: localRect.height)
                // Brief 50ms pause so the dimmed selection overlay is completely gone before capturing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onRegion(region)
                }
            },
            onCancel: { [weak self] in self?.hide() }
        )
        let host = CrosshairHostingView(rootView: view)
        p.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(host)
        p.invalidateCursorRects(for: host)
        NSCursor.crosshair.push()
        NSCursor.crosshair.set()
        panel = p
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }

    func hide() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if panel != nil {
            NSCursor.pop()
            NSCursor.arrow.set()
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Design review gallery (used by `--render-ui`)

struct OverlayGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 0) {
                Text("Thanks for sending the draft over. I'll go through it").font(.system(size: 15))
                InlineGhostView(text: " tonight and send you my notes", fontSize: 15, keyLabel: "⇥", head: " tonight")
            }
            HStack(alignment: .top, spacing: 18) {
                BubbleView(content: AnyView(Text("sounds good to me").font(.system(size: 12.5))), keyLabel: "⇥")
                BubbleView(content: AnyView(HStack(spacing: 6) {
                    Text("recieve").strikethrough(color: Theme.rose.opacity(0.8)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.aurora)
                    Text("receive").fontWeight(.semibold)
                }.font(.system(size: 12.5))), keyLabel: "⇥")
            }
            HStack(alignment: .top, spacing: 18) {
                ListPanelView(header: "Alternatives", items: [ListItem(leading: "", title: "tonight"),
                                                              ListItem(leading: "", title: "tomorrow"),
                                                              ListItem(leading: "", title: "today"),
                                                              ListItem(leading: "", title: "carefully")], scope: .word)
                ListPanelView(header: "Emoji", items: [ListItem(leading: "😄", title: ":smile:"),
                                                       ListItem(leading: "😂", title: ":joy:"),
                                                       ListItem(leading: "🥲", title: ":smiling_tear:")])
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
