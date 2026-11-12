import SwiftUI

/// Sidebar destinations of the Settings window.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case setup, general, models, context, personalization, emoji, shortcuts, battery, apps, tools, statistics, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return L("Overview", "Panoramica")
        case .general: return L("Behavior", "Comportamento")
        case .models: return L("Models", "Modelli")
        case .context: return L("Awareness", "Contesto")
        case .personalization: return L("Memory & Style", "Memoria e stile")
        case .emoji: return "Emoji"
        case .shortcuts: return L("Hotkeys", "Scorciatoie")
        case .battery: return L("Power", "Alimentazione")
        case .apps: return L("Per-App Rules", "Regole per app")
        case .tools: return L("Word Tools", "Strumenti testo")
        case .statistics: return L("Insights", "Statistiche")
        case .about: return L("About", "Informazioni")
        }
    }

    /// One-line description shown under the page title.
    var tagline: String {
        switch self {
        case .setup: return L("Permissions and status.", "Permessi e stato.")
        case .general: return L("How and when suggestions appear.", "Come e quando compaiono i suggerimenti.")
        case .models: return L("The model that writes with you.", "Il modello che scrive con te.")
        case .context: return L("What NexoLLM reads to understand the moment.", "Cosa legge NexoLLM per capire il momento.")
        case .personalization: return L("Your style, your history, your data.", "Il tuo stile, la tua cronologia, i tuoi dati.")
        case .emoji: return L("Emoji while you type.", "Emoji mentre scrivi.")
        case .shortcuts: return L("Keys to accept, dismiss and control suggestions.", "Tasti per accettare, ignorare e controllare i suggerimenti.")
        case .battery: return L("Lighter behavior when unplugged.", "Comportamento più leggero a batteria.")
        case .apps: return L("Settings for individual apps.", "Impostazioni per le singole app.")
        case .tools: return L("Other words and other phrasings, on demand.", "Altre parole e altre formulazioni, su richiesta.")
        case .statistics: return L("What NexoLLM has written for you.", "Quanto ha scritto NexoLLM per te.")
        case .about: return L("Version, updates and project information.", "Versione, aggiornamenti e informazioni sul progetto.")
        }
    }

    var symbol: String {
        switch self {
        case .setup: return "lock.shield"
        case .general: return "gearshape"
        case .models: return "shippingbox"
        case .context: return "text.viewfinder"
        case .personalization: return "wand.and.stars"
        case .emoji: return "face.smiling"
        case .shortcuts: return "command"
        case .battery: return "battery.100.bolt"
        case .apps: return "slider.horizontal.3"
        case .tools: return "text.badge.plus"
        case .statistics: return "chart.bar.fill"
        case .about: return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .setup: return Theme.amber
        case .general: return Color(red: 0.45, green: 0.52, blue: 0.68)
        case .models: return Theme.violet
        case .context: return Theme.cyan
        case .personalization: return Theme.violet
        case .emoji: return Color(red: 1.0, green: 0.78, blue: 0.20)
        case .shortcuts: return Color(red: 0.96, green: 0.36, blue: 0.70)
        case .battery: return Theme.mint
        case .apps: return Theme.rose
        case .tools: return Theme.accent
        case .statistics: return Color(red: 0.16, green: 0.72, blue: 0.78)
        case .about: return Theme.blue
        }
    }

    var tab: SettingsTab { SettingsTab.allCases.first { $0.panes.contains(self) } ?? .home }
}

/// Top-level sections of the window (top navigation). Each holds one or more panes (sub-tabs).
enum SettingsTab: String, CaseIterable, Identifiable {
    case home, engine, mind, input, apps, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .engine: return L("Engine", "Motore")
        case .mind: return L("Mind", "Mente")
        case .input: return "Input"
        case .apps: return L("Apps", "App")
        case .about: return L("About", "Info")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .engine: return "cpu.fill"
        case .mind: return "brain.head.profile"
        case .input: return "keyboard.fill"
        case .apps: return "square.grid.2x2.fill"
        case .about: return "sparkle"
        }
    }

    var panes: [SettingsPane] {
        switch self {
        case .home: return [.setup, .statistics]
        case .engine: return [.general, .models, .battery]
        case .mind: return [.context, .personalization]
        case .input: return [.shortcuts, .emoji, .tools]
        case .apps: return [.apps]
        case .about: return [.about]
        }
    }
}

/// Tracks whether the main Settings window is in full screen.
final class WindowState: ObservableObject {
    static let shared = WindowState()
    @Published var isFullScreen = false
}

/// Coordinates animated language switches with a brief full-window spinner overlay.
final class LanguageTransition: ObservableObject {
    static let shared = LanguageTransition()
    @Published var isSwitching = false

    func switchTo(_ lang: ExampleLanguage) {
        guard Settings.shared.prefs.exampleLanguage != lang, !isSwitching else { return }
        withAnimation(.easeInOut(duration: 0.16)) { isSwitching = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            Settings.shared.prefs.exampleLanguage = lang
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeOut(duration: 0.18)) { self.isSwitching = false }
            }
        }
    }
}

/// Glass language selector: a popover with every interface language.
struct LanguagePickerButton: View {
    var compact: Bool = false
    @ObservedObject private var settings = Settings.shared
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                Text(compact ? settings.prefs.exampleLanguage.code : settings.prefs.exampleLanguage.label)
                    .font(.system(size: compact ? 11 : 12.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(GlassButtonStyle(capsule: compact))
        .controlSize(compact ? .small : .regular)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("APP LANGUAGE", "LINGUA DELL'APP"))
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                ForEach(ExampleLanguage.allCases) { lang in
                    LanguageRowButton(title: "\(lang.flag)  \(lang.label)",
                                      selected: settings.prefs.exampleLanguage == lang,
                                      badge: nil) {
                        open = false
                        LanguageTransition.shared.switchTo(lang)
                    }
                }
            }
            .padding(8)
            .frame(width: 215)
        }
    }
}

private struct LanguageRowButton: View {
    let title: String
    let selected: Bool
    let badge: String?
    let action: (() -> Void)?
    @State private var hover = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(action == nil ? .tertiary : .primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                } else if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.14) : (hover && action != nil ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { hover = $0 }
    }
}

/// Full-window animated spinner overlay shown briefly while switching app language.
private struct LanguageLoadingOverlay: View {
    @State private var spin = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 12) {
                Circle()
                    .trim(from: 0.15, to: 0.88)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.65).repeatForever(autoreverses: false), value: spin)
                Text(L("Updating language…", "Aggiornamento lingua…"))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
        }
        .onAppear { spin = true }
        .transition(.opacity)
    }
}

/// Floating circular widget button anchored at the bottom-right of the Settings window that opens Buy Me a Coffee.
private struct FloatingCoffeeWidget: View {
    @State private var hover = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(Brand.coffee)
        } label: {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(hover ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(hover ? 0.28 : 0.18), radius: hover ? 12 : 8, y: 4)
                )
                .overlay(
                    Circle()
                        .strokeBorder(hover ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.14), lineWidth: 1)
                )
                .scaleEffect(hover ? 1.07 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hover = hovering }
        }
        .help(L("Support \(Brand.author) · Buy Me a Coffee (\(Brand.coffeeLabel))",
                "Supporta \(Brand.author) · Offrimi un caffè (\(Brand.coffeeLabel))"))
    }
}

/// Root view of the Settings window (hosted by AppDelegate in an NSWindow).
struct SettingsRootView: View {
    let actions: SettingsActions
    @State private var tab: SettingsTab
    @State private var pane: SettingsPane
    @State private var lastPane: [SettingsTab: SettingsPane] = [:]
    @Namespace private var nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var modals = ModalCenter.shared
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var langTransition = LanguageTransition.shared
    @ObservedObject private var windowState = WindowState.shared
    @ObservedObject private var stats = Stats.shared
    @ObservedObject private var network = NetworkMonitor.shared

    /// The only motion in the window: a 140 ms ease when switching pages (none with Reduce Motion).
    private var pageAnimation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.14) }

    init(actions: SettingsActions, initial: SettingsPane = .setup) {
        self.actions = actions
        _tab = State(initialValue: initial.tab)
        _pane = State(initialValue: initial)
    }

    var body: some View {
        Group {
            if windowState.isFullScreen {
                fullscreenDashboard
            } else {
                windowedBody
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if modals.current == nil {
                FloatingCoffeeWidget()
                    .padding(.trailing, 20)
                    .padding(.bottom, 18)
            }
        }
        .id(settings.prefs.exampleLanguage)   // a new app language redraws every page at once
        .background(AuroraBackground())
        .environment(\.locale, Fmt.locale)   // dates, numbers and charts in the app language
        .tint(Theme.accent)
        .frame(minWidth: 860, minHeight: 600)
        .blur(radius: modals.current == nil ? 0 : 14)
        .overlay { if let m = modals.current { ModalHost(modal: m, actions: actions) } }
        .overlay { if langTransition.isSwitching { LanguageLoadingOverlay() } }
        .buttonStyle(GlassButtonStyle())
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: modals.current)
    }

    private var windowedBody: some View {
        VStack(spacing: 0) {
            titleRow
            TabCapsule(selection: tab, namespace: nav) { select($0) }
                .padding(.top, 4)
            if tab.panes.count > 1 {
                SubTabs(panes: tab.panes, selection: pane, namespace: nav) { p in
                    withAnimation(pageAnimation) { pane = p; lastPane[tab] = p }
                }
                .padding(.top, 12)
            }
            detail(pane)
                .environment(\.settingsPane, pane)
                .id(pane)
                .transition(.opacity.combined(with: .offset(y: 4)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 6)
        }
    }

    /// Fullscreen Dashboard layout: uses the entire screen with a left command sidebar, top metrics bar,
    /// and a wide multi-column workspace (with Overview + Insights side-by-side on Home).
    private var fullscreenDashboard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    BrandOrb(size: 22)
                    Text(Brand.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(L("DASHBOARD", "DASHBOARD"))
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent.opacity(0.14)))
                }
                Spacer(minLength: 20)
                HStack(spacing: 10) {
                    StatusPill(
                        text: L("\(Fmt.number(stats.today.words)) words today", "\(Fmt.number(stats.today.words)) parole oggi"),
                        symbol: "sparkles",
                        color: Theme.accent
                    )
                    StatusPill(
                        text: network.isOnline ? L("Online", "Online") : L("100% Offline", "100% Offline"),
                        symbol: network.isOnline ? "wifi" : "checkmark.shield.fill",
                        color: Theme.mint
                    )
                    LanguagePickerButton(compact: true)
                    Button { ModalCenter.shared.current = .walkthrough } label: {
                        Label("Tour", systemImage: "sparkles").font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(GlassButtonStyle(capsule: true))
                    Button { actions.restartServices() } label: {
                        Label(L("Restart", "Riavvia"), systemImage: "arrow.clockwise")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(GlassButtonStyle(capsule: true))
                    EngineChip()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.03))
            Divider().opacity(0.5)

            HStack(spacing: 0) {
                // Fullscreen left sidebar with all sections and panes
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(SettingsTab.allCases) { sectionTab in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sectionTab.title.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.7)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 2)
                                ForEach(sectionTab.panes) { p in
                                    let isSelected = (pane == p)
                                    Button {
                                        withAnimation(pageAnimation) {
                                            tab = sectionTab
                                            pane = p
                                            lastPane[sectionTab] = p
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: p.symbol)
                                                .font(.system(size: 12.5, weight: .semibold))
                                                .foregroundStyle(isSelected ? .white : p.color)
                                                .frame(width: 24, height: 24)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .fill(isSelected ? Color.white.opacity(0.2) : p.color.opacity(0.14))
                                                )
                                            Text(p.title)
                                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                                .foregroundStyle(isSelected ? .white : .primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(isSelected ? Theme.accent : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(width: 248)
                .background(Color.primary.opacity(0.025))

                Divider().opacity(0.5)

                // Fullscreen wide workspace
                Group {
                    if pane == .setup || pane == .statistics {
                        HStack(alignment: .top, spacing: 0) {
                            SetupPane(actions: actions)
                                .environment(\.settingsPane, .setup)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Divider().opacity(0.4)
                            StatisticsPane()
                                .environment(\.settingsPane, .statistics)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        detail(pane)
                            .environment(\.settingsPane, pane)
                            .id(pane)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    /// Lowered slightly with breathing room between the traffic lights, wordmark, and right-hand action pills.
    private var titleRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                BrandOrb(size: 17)
                Text(Brand.name)
                    .font(.system(size: 13.5, weight: .semibold))
            }
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                LanguagePickerButton(compact: true)
                    .help(L("Choose app language", "Scegli la lingua dell'app"))
                Button { ModalCenter.shared.current = .walkthrough } label: {
                    Label("Tour", systemImage: "sparkles").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(GlassButtonStyle(capsule: true))
                .controlSize(.small)
                .help(L("Replay the interactive tour", "Rivedi il tour interattivo"))
                Button { actions.restartServices() } label: {
                    Label(L("Restart", "Riavvia"), systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(GlassButtonStyle(capsule: true))
                .controlSize(.small)
                .help(L("Restart NexoLLM services (\(settings.prefs.restartShortcut.display))",
                        "Riavvia i servizi di NexoLLM (\(settings.prefs.restartShortcut.display))"))
                EngineChip()
            }
        }
        .padding(.leading, 86)
        .padding(.trailing, 18)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(height: 38)
    }

    private func select(_ t: SettingsTab) {
        guard t != tab else { return }
        withAnimation(pageAnimation) {
            lastPane[tab] = pane
            tab = t
            pane = lastPane[t] ?? t.panes[0]
        }
    }

    @ViewBuilder
    private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .setup: SetupPane(actions: actions)
        case .general: GeneralPane(actions: actions)
        case .models: ModelsPane()
        case .context: ContextPane(actions: actions)
        case .personalization: PersonalizationPane()
        case .emoji: EmojiPane()
        case .shortcuts: ShortcutsPane()
        case .battery: BatteryPane(actions: actions)
        case .apps: AppSettingsPane()
        case .tools: WordToolsPane()
        case .statistics: StatisticsPane()
        case .about: AboutPane()
        }
    }
}

// MARK: - Navigation pieces

/// Segmented bar with the main sections; the active one sits on an accent pill.
private struct TabCapsule: View {
    let selection: SettingsTab
    let namespace: Namespace.ID
    let onSelect: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { t in
                TabButton(tab: t, selected: t == selection, namespace: namespace) { onSelect(t) }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

private struct TabButton: View {
    let tab: SettingsTab
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol).font(.system(size: 11, weight: .medium))
                Text(tab.title).font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent)
                        .matchedGeometryEffect(id: "tab.pill", in: namespace)   // the pill slides between tabs
                } else if hover {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h } }
    }
}

/// Text sub-tabs with an accent underline.
private struct SubTabs: View {
    let panes: [SettingsPane]
    let selection: SettingsPane
    let namespace: Namespace.ID
    let onSelect: (SettingsPane) -> Void

    var body: some View {
        HStack(spacing: 22) {
            ForEach(panes) { p in
                Button { onSelect(p) } label: {
                    VStack(spacing: 5) {
                        Text(p.title)
                            .font(.system(size: 13, weight: p == selection ? .semibold : .regular))
                            .foregroundStyle(p == selection ? .primary : .secondary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2)
                            if p == selection {
                                Capsule().fill(Theme.accent).frame(height: 2)
                                    .matchedGeometryEffect(id: "subtab.line", in: namespace)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The NexoLLM mark, drawn like the app icon: an accent tile with a text cursor followed by ghost text.
struct BrandOrb: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, sz in
            // Coordinates of the 824 pt icon body (scripts/make-icon.swift), top-left origin.
            let k = sz.width / 824
            let thick: CGFloat = sz.width < 24 ? 1.5 : 1   // keep the strokes visible at title-bar size
            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                let r = CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
                return Path(roundedRect: r, cornerRadius: min(r.width, r.height) / 2)
            }
            let tile = Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 186 * k, style: .continuous)
            ctx.fill(tile, with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.52, blue: 1.0),
                                                                   Color(red: 0.28, green: 0.33, blue: 0.86)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
            ctx.fill(bar(252 - 17 * thick, 224, 34 * thick, 376), with: .color(.white))
            ctx.fill(bar(192, 224, 120, 30 * thick), with: .color(.white))
            ctx.fill(bar(192, 600 - 30 * thick, 120, 30 * thick), with: .color(.white))
            ctx.fill(bar(342, 312, 300, 64 * thick), with: .color(.white.opacity(0.45)))
            ctx.fill(bar(342, 448, 196, 64 * thick), with: .color(.white.opacity(0.28)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Brand.name)
    }
}

/// Live engine state, top right.
private struct EngineChip: View {
    @ObservedObject private var status = AppStatus.shared
    @State private var onBattery = Power.onBattery

    private var label: String {
        let s = status.engine
        return Fmt.status(s.range(of: " · ").map { String(s[..<$0.lowerBound]) } ?? s)
    }

    private var color: Color {
        if status.engine.hasPrefix("Sleeping") { return Theme.violet }
        if status.engine.hasPrefix("Error") { return Theme.rose }
        return status.modelReady ? Theme.mint : Theme.amber
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11, weight: .medium))
            Image(systemName: onBattery ? "battery.75percent" : "powerplug.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .help(Fmt.status(status.engine))
        .onReceive(NotificationCenter.default.publisher(for: Power.changed)) { _ in onBattery = Power.onBattery }
    }
}
