import AppKit
import SwiftUI

// MARK: - Design system
//
// Calm and minimal: one accent color, flat translucent cards with a hairline border, system materials,
// no glows, no drifting backgrounds, no decorative motion. Performance rules:
// - No perpetual animation anywhere (overlays only fade in on appearance).
// - No in-window blur on cards; the Settings window is destroyed on close.

enum Theme {
    /// The one accent color (selection, switches, key caps, the orb).
    static let accent = Color(red: 0.35, green: 0.42, blue: 0.95)

    // Semantic colors, used sparingly (status, metrics).
    static let violet = Color(red: 0.50, green: 0.42, blue: 0.92)
    static let blue = Color(red: 0.25, green: 0.52, blue: 0.95)
    static let cyan = Color(red: 0.20, green: 0.68, blue: 0.82)
    static let mint = Color(red: 0.22, green: 0.72, blue: 0.52)
    static let amber = Color(red: 0.95, green: 0.62, blue: 0.20)
    static let rose = Color(red: 0.92, green: 0.36, blue: 0.45)

    // Former gradients, now flat accent fills (kept as names so every view shares one look).
    static let aurora = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)

    /// 1 px neutral border.
    static func hairline(_ strength: Double = 1) -> LinearGradient {
        LinearGradient(colors: [Color.primary.opacity(0.10 * strength), Color.primary.opacity(0.10 * strength)],
                       startPoint: .top, endPoint: .bottom)
    }

    static let spring = Animation.easeOut(duration: 0.15)
    static let snappy = Animation.easeOut(duration: 0.12)
}

// MARK: - Surfaces

/// Flat card: faint fill + hairline border. No gradients, no colored shadows.
struct GlassCardModifier: ViewModifier {
    var radius: CGFloat = 12
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.75)))
            .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.09 : 0.08), lineWidth: 1))
    }
}

extension View {
    func glassCard(radius: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint))
    }

    /// Surface for the floating overlays: system material (blends with the app underneath) + hairline.
    func overlayGlass<S: InsettableShape>(in shape: S) -> some View {
        self
            .background(shape.fill(.regularMaterial))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6))
    }
}

// MARK: - Window background

/// Plain window background with a barely-there accent wash at the top. Static.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Theme.accent.opacity(scheme == .dark ? 0.07 : 0.05), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page scaffolding (replaces Form/Section)

private struct SettingsPaneKey: EnvironmentKey { static let defaultValue: SettingsPane? = nil }
extension EnvironmentValues {
    var settingsPane: SettingsPane? {
        get { self[SettingsPaneKey.self] }
        set { self[SettingsPaneKey.self] = newValue }
    }
}

/// Scrollable page of glass sections, with the pane's hero header on top.
/// In Fullscreen mode, expands to fill the wide workspace and arranges sections in a 2-column dashboard grid.
struct GlassPage<Content: View>: View {
    var showsHeader = true
    @ViewBuilder var content: Content
    @Environment(\.settingsPane) private var pane
    @ObservedObject private var windowState = WindowState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if showsHeader, let pane { PageHeader(pane: pane) }
                if windowState.isFullScreen, #available(macOS 15.0, *) {
                    Group(subviews: content) { subviews in
                        if subviews.count >= 2 {
                            let hasHero = subviews.count >= 3
                            if hasHero { subviews[0] }
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(minimum: 380), spacing: 20, alignment: .top),
                                    GridItem(.flexible(minimum: 380), spacing: 20, alignment: .top),
                                ],
                                alignment: .leading,
                                spacing: 20
                            ) {
                                ForEach(hasHero ? Array(subviews.dropFirst()) : Array(subviews)) { sub in
                                    sub.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        } else {
                            content
                        }
                    }
                } else {
                    content
                }
            }
            .padding(.horizontal, windowState.isFullScreen ? 36 : 30)
            .padding(.top, windowState.isFullScreen ? 20 : 14)
            .padding(.bottom, 34)
            .frame(maxWidth: windowState.isFullScreen ? 1680 : 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
    }
}

/// Page title and one-line description.
struct PageHeader: View {
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pane.title)
                .font(.system(size: 24, weight: .semibold))
            Text(pane.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

/// A titled glass card. Rows are separated by hairline dividers.
struct GlassSection<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            rows
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
        }
    }

    @ViewBuilder private var rows: some View {
        if #available(macOS 15.0, *) {
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { sub in
                        sub.padding(.vertical, 9)
                        if sub.id != subviews.last?.id {
                            Divider().opacity(0.55)
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) { content }.padding(.vertical, 8)
        }
    }
}

// MARK: - Small components

/// Colored capsule with a symbol and text ("Granted", "Ready"…).
struct StatusPill: View {
    let text: String
    var symbol: String = "checkmark.circle.fill"
    var color: Color = Theme.mint

    var body: some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// Large hero banner (setup state, about…).
struct HeroBanner<Accessory: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    var colors: [Color] = [Theme.accent]
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(colors.first ?? Theme.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((colors.first ?? Theme.accent).opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(14)
        .glassCard()
    }
}

extension HeroBanner where Accessory == EmptyView {
    init(symbol: String, title: String, subtitle: String, colors: [Color] = [Theme.accent]) {
        self.init(symbol: symbol, title: title, subtitle: subtitle, colors: colors) { EmptyView() }
    }
}

/// Text editor styled as an inset glass field.
struct GlassTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 120

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(minHeight: minHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - Controls

/// Switch: outlined capsule that fills with the accent when on. Grows slightly and lights its border on
/// hover or keyboard focus, so you always see which control you're on. Space toggles it when focused.
/// Pressing squishes the track and stretches the knob; toggling slides it across on a bouncy spring.
struct AuroraToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { AuroraSwitch(configuration: configuration) }
}

private struct AuroraSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hover = false

    var body: some View {
        Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.66)) { configuration.isOn.toggle() } } label: { EmptyView() }
            .buttonStyle(AuroraSwitchBody(isOn: configuration.isOn, active: (hover || isFocused) && isEnabled))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hover = $0 }
            .accessibilityValue(configuration.isOn ? L("On", "Attivo") : L("Off", "Disattivo"))
    }
}

private struct AuroraSwitchBody: ButtonStyle {
    let isOn: Bool
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.accent.opacity(pressed ? 0.32 : 0.22) : Color.primary.opacity(pressed ? 0.08 : 0))
            Capsule().strokeBorder(isOn || active ? Theme.accent.opacity(isOn ? 1 : 0.7) : Color.primary.opacity(0.25),
                                   lineWidth: active || pressed ? 1.4 : 1.1)
            Capsule().fill(isOn ? Theme.accent : Color.primary.opacity(pressed ? 0.6 : 0.45))
                .frame(width: pressed ? 19 : 15, height: 15)
                .shadow(color: isOn ? Theme.accent.opacity(0.35) : .clear, radius: 3, y: 1)
                .padding(3)
        }
        .frame(width: 38, height: 21)
        .contentShape(Capsule())
        .scaleEffect(pressed ? 0.95 : active ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.66), value: isOn)
        .animation(.spring(response: 0.2, dampingFraction: 0.72), value: pressed)
        .animation(Theme.snappy, value: active)
    }
}

/// Outlined button on a transparent background. Hover or keyboard focus lights the border with the accent
/// and grows it a touch; pressing shrinks it back.
struct GlassButtonStyle: ButtonStyle {
    /// Pill shape (links in About).
    var capsule = false
    func makeBody(configuration: Configuration) -> some View { GlassButtonBody(configuration: configuration, capsule: capsule) }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let capsule: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hover = false

    var body: some View {
        let active = (hover || isFocused) && isEnabled
        let shape = RoundedRectangle(cornerRadius: capsule ? 100 : 8, style: .continuous)
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, capsule ? 14 : 12)
            .padding(.vertical, capsule ? 7 : 5)
            .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.10 : active ? 0.04 : 0)))
            .overlay(shape.strokeBorder(active ? Theme.accent.opacity(0.8) : Color.primary.opacity(0.22), lineWidth: active ? 1.2 : 1))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : active ? 1.035 : 1)
            .animation(Theme.snappy, value: active)
            .animation(Theme.snappy, value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hover = $0 }
    }
}

/// Segmented control in the button style: transparent, outlined; the chosen option sits on an accent pill.
/// Hover/focus lights a segment and grows it a touch; ←/→ move the selection.
struct GlassSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    init(selection: Binding<Value>, options: [Value], label: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { o in
                SegmentButton(title: label(o), selected: o == selection) { selection = o }
            }
        }
        .padding(2.5)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        .fixedSize()
        .onMoveCommand { dir in
            guard let i = options.firstIndex(of: selection) else { return }
            let j = dir == .left ? i - 1 : dir == .right ? i + 1 : i
            if options.indices.contains(j) { selection = options[j] }
        }
    }
}

extension GlassSegmentedPicker where Value: CaseIterable, Value.AllCases: RandomAccessCollection {
    init(_ selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.init(selection: selection, options: Array(Value.allCases), label: label)
    }
}

private struct SegmentButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @State private var hover = false

    var body: some View {
        let active = (hover || isFocused) && isEnabled
        let shape = RoundedRectangle(cornerRadius: 6.5, style: .continuous)
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(shape.fill(selected ? Theme.accent.opacity(0.20) : Color.primary.opacity(active ? 0.04 : 0)))
                .overlay(shape.strokeBorder(selected ? Theme.accent.opacity(active ? 1 : 0.85) : (active ? Theme.accent.opacity(0.75) : .clear),
                                            lineWidth: active ? 1.3 : 1.1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .scaleEffect(active ? 1.035 : 1)
        .animation(Theme.snappy, value: active)
        .animation(Theme.snappy, value: selected)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hover = $0 }
    }
}

/// The NSView a popup menu opens from.
private final class MenuAnchorBox { weak var view: NSView? }

private struct MenuAnchor: NSViewRepresentable {
    let box: MenuAnchorBox
    func makeNSView(context: Context) -> NSView { let v = NSView(); box.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { box.view = v }
}

/// Native menu over the control: the selected item lands on it, like a popup button; else just below.
private func popUp(_ menu: NSMenu, selected: NSMenuItem?, from box: MenuAnchorBox) {
    guard let v = box.view else { return }
    menu.autoenablesItems = false
    let y = selected != nil ? (v.isFlipped ? 0 : v.bounds.height) : (v.isFlipped ? v.bounds.height + 4 : -4)
    menu.popUp(positioning: selected, at: NSPoint(x: 0, y: y), in: v)
}

/// Dropdown in the button style (transparent, outlined, accent + grow on hover/focus) that opens the
/// native menu with a ✓ on the current value. Click, Space or Return opens it.
struct GlassMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    private let options: [(value: Value, label: String, dividerBefore: Bool)]
    @State private var box = MenuAnchorBox()

    init(selection: Binding<Value>, options: [(Value, String, Bool)]) {
        _selection = selection
        self.options = options.map { (value: $0.0, label: $0.1, dividerBefore: $0.2) }
    }

    init(selection: Binding<Value>, options: [(Value, String)]) {
        self.init(selection: selection, options: options.map { ($0.0, $0.1, false) })
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.label ?? "").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(GlassButtonStyle())
        .background(MenuAnchor(box: box))
        .fixedSize()
    }

    private func open() {
        let menu = NSMenu()
        let binding = $selection
        var selected: NSMenuItem?
        for o in options {
            if o.dividerBefore { menu.addItem(.separator()) }
            let item = ClosureMenuItem(o.label) { binding.wrappedValue = o.value }
            if o.value == selection { item.state = .on; selected = item }
            menu.addItem(item)
        }
        popUp(menu, selected: selected, from: box)
    }
}

extension GlassMenuPicker where Value: CaseIterable, Value.AllCases: RandomAccessCollection {
    init(_ selection: Binding<Value>, label: @escaping (Value) -> String) {
        self.init(selection: selection, options: Value.allCases.map { ($0, label($0), false) })
    }
}

/// Button-styled menu of actions ("Use", "Keep Last…").
struct GlassActionMenu: View {
    let title: String
    let items: [(title: String, enabled: Bool, action: () -> Void)]
    @State private var box = MenuAnchorBox()

    init(_ title: String, items: [(String, Bool, () -> Void)]) {
        self.title = title
        self.items = items.map { (title: $0.0, enabled: $0.1, action: $0.2) }
    }

    var body: some View {
        Button {
            let menu = NSMenu()
            for i in items {
                let item = ClosureMenuItem(i.title, i.action)
                item.isEnabled = i.enabled
                menu.addItem(item)
            }
            popUp(menu, selected: nil, from: box)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(GlassButtonStyle())
        .background(MenuAnchor(box: box))
        .fixedSize()
    }
}
