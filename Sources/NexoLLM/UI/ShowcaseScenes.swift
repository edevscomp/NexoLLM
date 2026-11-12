import SwiftUI

// Scenes rendered by `--render-ui` for the public README: real NexoLLM views on clean,
// OS-neutral translucent panes ready to be composited over a desktop wallpaper (scripts/readme_media.py).

/// Clean OS-neutral window frame (no OS-specific traffic lights) on a subtle backdrop.
struct ShowcaseFrame<Content: View>: View {
    let size: CGSize
    var title: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.09, green: 0.10, blue: 0.15), Color(red: 0.15, green: 0.13, blue: 0.25)]
                           : [Color(red: 0.88, green: 0.90, blue: 0.98), Color(red: 0.96, green: 0.93, blue: 0.99)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            content
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) {
                    if let title { Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary).padding(.top, 10) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(dark ? 0.16 : 0.09), lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.18), radius: 32, y: 18)
        }
        .frame(width: size.width + 140, height: size.height + 140)
    }
}

/// Semi-transparent panel surface used by `scripts/readme_media.py` so the frosted desktop wallpaper shines through.
struct FrostedPanelSurface<Content: View>: View {
    var title: String? = nil
    var badge: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || badge != nil {
                HStack(spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(Theme.accent.opacity(0.24)))
                            .overlay(Capsule(style: .continuous).strokeBorder(Theme.accent.opacity(0.45), lineWidth: 0.75))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 10)
                Divider().opacity(0.35)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.09, blue: 0.13).opacity(0.42))
    }
}

/// A mail draft with a suggestion after the caret: what NexoLLM looks like in use.
struct HeroScene: View {
    var showAlternatives = false
    var translucent = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: translucent ? 10 : 38)
            field("To", "Alex Morgan")
            field("Subject", "Launch plan, final draft")
            VStack(alignment: .leading, spacing: 12) {
                Text("Hi Alex,").font(.system(size: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thanks for sending the final draft over. The timeline looks right and the")
                        .font(.system(size: 15))
                    HStack(spacing: 0) {
                        Text("budget section reads much better now. I'll go through it").font(.system(size: 15))
                        Rectangle().fill(Theme.accent).frame(width: 1.5, height: 18)
                        if !showAlternatives {
                            InlineGhostView(text: " tonight and send you my notes", fontSize: 15, keyLabel: "⇥",
                                            head: " tonight", tone: dark ? .dark : .light)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if showAlternatives {
                            ListPanelView(header: "Alternatives",
                                          items: ["tonight", "tomorrow", "today", "carefully", "again"].map { ListItem(leading: "", title: $0) },
                                          scope: .word)
                                .fixedSize()
                                .offset(x: 196, y: 16)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(translucent ? Color.clear : Color(nsColor: .textBackgroundColor))
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(label + ":").font(.system(size: 13)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 24).padding(.vertical, 9)
            Divider().padding(.leading, 24)
        }
    }
}

/// Animated 72-frame sequence for `live.gif`: inline ghost -> `Tab` word commit -> `⇧Tab` phrase -> `⌥Tab` alternatives -> `Return` insert.
struct LiveDemoScene: View {
    let frame: Int
    static let totalFrames = 72

    var body: some View {
        let state = Self.frameState(frame)
        let caretPulse = 0.62 + 0.38 * (0.5 + 0.5 * sin(Double(frame) * 0.48))
        let progress = CGFloat(frame + 1) / CGFloat(Self.totalFrames)
        FrostedPanelSurface(title: "Mail — Launch plan, final draft", badge: state.keyBadge) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Text("To:").foregroundStyle(.secondary)
                        Text("Alex Morgan")
                    }
                    Text("·").foregroundStyle(.tertiary)
                    HStack(spacing: 5) {
                        Text("Subject:").foregroundStyle(.secondary)
                        Text("Launch plan, final draft")
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green.opacity(caretPulse))
                            .frame(width: 6, height: 6)
                        Text("Local · 18 ms")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12.5))
                .padding(.bottom, 4)

                Text("Hi Alex,")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 5) {
                    Text("The timeline looks solid and the budget section reads much better now.")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)

                    HStack(spacing: 0) {
                        Text(state.committedLine)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Rectangle()
                            .fill(Theme.accent.opacity(state.cursorVisible ? caretPulse : 0.22))
                            .frame(width: 2, height: 18)
                        if let ghost = state.ghost, let head = state.ghostHead {
                            InlineGhostView(text: ghost, fontSize: 15, keyLabel: state.ghostKey, head: head, tone: .dark)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let altSelected = state.altIndex {
                            ListPanelView(
                                header: "Alternatives",
                                items: ["on Thursday", "tomorrow morning", "this afternoon", "after standup"].map {
                                    ListItem(leading: "", title: $0)
                                },
                                scope: .phrase,
                                selected: altSelected
                            )
                            .fixedSize()
                            .offset(x: 340, y: 24)
                        }
                    }
                }
                Spacer(minLength: 0)

                // Subtle bottom HUD bar showing the active keystroke and timeline progress
                VStack(spacing: 7) {
                    HStack(spacing: 8) {
                        ForEach(Array(Self.steps.enumerated()), id: \.offset) { idx, item in
                            let active = idx == state.activeStep
                            HStack(spacing: 5) {
                                Text(item.key)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(active ? Theme.accent : Color.white.opacity(0.10)))
                                    .foregroundStyle(active ? Color.white : Color.white.opacity(0.65))
                                Text(item.label)
                                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                                    .foregroundStyle(active ? Color.white.opacity(0.92) : Color.white.opacity(0.45))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous)
                                .fill(active ? Theme.accent.opacity(0.20) : Color.white.opacity(0.03)))
                        }
                        Spacer()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule().fill(Theme.accent.opacity(0.65))
                                .frame(width: max(8, geo.size.width * progress))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
    }

    private static let steps: [(key: String, label: String)] = [
        ("⇥", "Next word"),
        ("⇧⇥", "Full phrase"),
        ("⌥⇥", "Alternatives"),
        ("↩", "Insert"),
    ]

    struct StateSnapshot {
        var committedLine: String
        var ghost: String?
        var ghostHead: String?
        var ghostKey: String = "⇥"
        var keyBadge: String
        var activeStep: Int = 0
        var altIndex: Int? = nil
        var cursorVisible: Bool = true
    }

    static func frameState(_ f: Int) -> StateSnapshot {
        if f < 14 {
            // Starts immediately with an active inline ghost suggestion on Frame 0!
            return StateSnapshot(
                committedLine: "I'll review it",
                ghost: " tonight and send my notes",
                ghostHead: " tonight",
                ghostKey: "⇥",
                keyBadge: "⇥ Tab · accept next word",
                activeStep: 0
            )
        } else if f < 26 {
            return StateSnapshot(
                committedLine: "I'll review it tonight",
                ghost: " and send my notes",
                ghostHead: " and",
                ghostKey: "⇧⇥",
                keyBadge: "⇧Tab · accept full phrase",
                activeStep: 1
            )
        } else if f < 36 {
            let extra = " Let's sync "
            let c = min(extra.count, max(0, (f - 26) * extra.count / 6))
            let showGhost = c == extra.count
            return StateSnapshot(
                committedLine: "I'll review it tonight and send my notes." + String(extra.prefix(c)),
                ghost: showGhost ? "tomorrow morning" : nil,
                ghostHead: showGhost ? "tomorrow" : nil,
                ghostKey: "⇥",
                keyBadge: showGhost ? "Suggestion ready" : "Typing…",
                activeStep: 1
            )
        } else if f < 56 {
            let sel = f < 46 ? 1 : 0
            return StateSnapshot(
                committedLine: "I'll review it tonight and send my notes. Let's sync ",
                ghost: nil,
                ghostHead: nil,
                keyBadge: "⌥Tab · browse alternatives",
                activeStep: 2,
                altIndex: sel
            )
        } else if f < 66 {
            return StateSnapshot(
                committedLine: "I'll review it tonight and send my notes. Let's sync on Thursday.",
                ghost: nil,
                ghostHead: nil,
                keyBadge: "Return · inserted choice",
                activeStep: 3,
                cursorVisible: (f / 2) % 2 == 0
            )
        } else {
            let typingTarget = "I'll review it"
            let count = min(typingTarget.count, max(4, (f - 65) * typingTarget.count / 6))
            return StateSnapshot(
                committedLine: String(typingTarget.prefix(count)),
                ghost: count == typingTarget.count ? " tonight and send my notes" : nil,
                ghostHead: count == typingTarget.count ? " tonight" : nil,
                ghostKey: "⇥",
                keyBadge: "On-device · Gemma 4",
                activeStep: 0
            )
        }
    }
}

/// A notes window with the ⌃⌥M quick menu open at the caret, Writing Tools expanded.
struct QuickMenuScene: View {
    var translucent = false

    var body: some View {
        let tools: [QuickMenuItem] = [
            QuickMenuItem(symbol: "wand.and.stars", title: "Improve Writing"),
            QuickMenuItem(symbol: "checkmark.seal", title: "Fix Grammar"),
            QuickMenuItem(symbol: "briefcase", title: "Make Formal"),
            QuickMenuItem(symbol: "arrow.down.right.and.arrow.up.left", title: "Make Shorter"),
            QuickMenuItem(symbol: "globe", title: "Translate…", subitems: [QuickMenuItem(symbol: "globe", title: "English")]),
        ]
        let items: [QuickMenuItem] = [
            QuickMenuItem(symbol: "wand.and.stars", title: "Writing Tools", subitems: tools),
            QuickMenuItem(symbol: "circle.fill", title: "Disable in Notes", badge: "Active"),
            QuickMenuItem(symbol: "pause.circle", title: "Pause Suggestions…", subitems: [QuickMenuItem(symbol: "timer", title: "Pause 10m")]),
            QuickMenuItem(symbol: "sparkle.magnifyingglass", title: "Smart Web Lookup", badge: "⌃⌥L"),
            QuickMenuItem(symbol: "text.viewfinder", title: "Read the Screen Now", badge: "⌃⌥S"),
            QuickMenuItem(symbol: "waveform", title: "Audio Context", badge: "On · Auto",
                          subitems: [QuickMenuItem(symbol: "checkmark", title: "Automatic (Multilingual)")]),
        ]
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: translucent ? 14 : 30)
            Text("Weekly update").font(.system(size: 20, weight: .bold))
            Text("hi team, the beta went out on monday and feedback has been great so far. we fixed the sync issue and the new onboarding is almost done")
                .font(.system(size: 14)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                .background(Theme.accent.opacity(0.18))
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(translucent ? Color.clear : Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topLeading) {
            QuickMenuView(status: "Ready · Gemma 4 E4B", words: 1284, items: items, selected: 0, expandedIndex: 0, selectedSubIndex: 1)
                .fixedSize()
                .offset(x: 228, y: translucent ? 96 : 128)
        }
    }
}

/// A document/browser pane with a highlighted idiom and the ⌃⌥L lookup card next to it.
struct LookupScene: View {
    var translucent = false

    var body: some View {
        let card = WebLookup.ResultCard(
            query: "bite the bullet", isDefinition: true,
            summary: "To force yourself to do something unpleasant that can't be avoided.",
            bullets: ["«In the end she bit the bullet and told her boss she was leaving.»",
                      "«Sometimes you just have to bite the bullet and get it done.»"],
            bulletTitle: "Usage examples",
            sources: [WebLookup.SourceItem(title: "Wiktionary", source: "Wiktionary", url: URL(string: "https://en.wiktionary.org")!),
                      WebLookup.SourceItem(title: "Wikiquote", source: "Wikiquote", url: URL(string: "https://en.wikiquote.org")!)])
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: translucent ? 14 : 30)
            Text("Moving on").font(.system(size: 20, weight: .bold))
            (Text("After months of delays, the team decided to ")
             + Text("bite the bullet").foregroundColor(.primary).bold()
             + Text(" and rewrite the sync engine from scratch."))
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(translucent ? Color.clear : Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topLeading) {
            LookupCardView(query: "bite the bullet", card: card, onSelectArea: {}, onAskQuestion: nil)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: 150, y: translucent ? 86 : 104)
        }
    }
}
