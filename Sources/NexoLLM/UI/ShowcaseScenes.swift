import SwiftUI

// Scenes rendered by `--render-ui` for the public README: real NexoLLM views inside a macOS window frame,
// on a soft backdrop, in light and dark.

/// macOS window controls.
struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([Color(red: 1.0, green: 0.37, blue: 0.34), Color(red: 1.0, green: 0.74, blue: 0.18),
                     Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { c in
                Circle().fill(c).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            }
        }
    }
}

/// A window with rounded corners, a hairline, a shadow and the traffic lights, on a gradient backdrop.
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
                .overlay(alignment: .topLeading) { TrafficLights().padding(.leading, 16).padding(.top, 10) }
                .overlay(alignment: .top) {
                    if let title { Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(dark ? 0.16 : 0.09), lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0.55 : 0.18), radius: 32, y: 18)
        }
        .frame(width: size.width + 140, height: size.height + 140)
    }
}

/// A mail draft with a suggestion after the caret: what NexoLLM looks like in use.
struct HeroScene: View {
    var showAlternatives = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 38)
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
        .background(Color(nsColor: .textBackgroundColor))
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

/// A notes window with the ⌃⌥M quick menu open at the caret, Writing Tools expanded.
struct QuickMenuScene: View {
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
            QuickMenuItem(symbol: "waveform", title: "Audio Context", badge: "On · EN",
                          subitems: [QuickMenuItem(symbol: "checkmark", title: "Automatic (Multilingual)")]),
        ]
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 30)
            Text("Weekly update").font(.system(size: 20, weight: .bold))
            Text("hi team, the beta went out on monday and feedback has been great so far. we fixed the sync issue and the new onboarding is almost done")
                .font(.system(size: 14)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                .background(Theme.accent.opacity(0.18))
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topLeading) {
            QuickMenuView(status: "Ready · Gemma 4 E4B", words: 1284, items: items, selected: 0, expandedIndex: 0, selectedSubIndex: 1)
                .fixedSize()
                .offset(x: 250, y: 128)
        }
    }
}

/// A web page with a highlighted idiom and the ⌃⌥L lookup card next to it.
struct LookupScene: View {
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
            Color.clear.frame(height: 30)
            Text("Moving on").font(.system(size: 20, weight: .bold))
            (Text("After months of delays, the team decided to ")
             + Text("bite the bullet").foregroundColor(.primary).bold()
             + Text(" and rewrite the sync engine from scratch."))
                .font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .topLeading) {
            LookupCardView(query: "bite the bullet", card: card, onSelectArea: {}, onAskQuestion: nil)
                .fixedSize(horizontal: false, vertical: true)
                .offset(x: 170, y: 104)
        }
    }
}
