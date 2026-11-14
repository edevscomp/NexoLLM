import SwiftUI

struct PersonalizationPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var history = History.shared
    @ObservedObject private var memory = Memory.shared
    @ObservedObject private var style = StyleProfile.shared
    @State private var cacheBytes: Int64 = 0
    @State private var cacheCleared = false
    @State private var confirmDelete = false
    @State private var confirmForget = false
    @State private var showData = false

    var body: some View {
        GlassPage {
            GlassSection(L("Writing History", "Cronologia di scrittura")) {
                ToggleRow(L("Learn from what I write", "Impara da ciò che scrivo"),
                          L("Keeps what you write, encrypted on this computer, to learn your vocabulary and style. Never uploaded.", "Conserva ciò che scrivi, cifrato su questo computer, per imparare il tuo lessico e il tuo stile. Mai caricato online."),
                          isOn: $settings.prefs.recordWriting)
                Group {
                    ToggleRow(L("Include text written without suggestions", "Includi il testo scritto senza suggerimenti"),
                              indent: true, isOn: $settings.prefs.recordWithoutAccept)
                    SettingRow(L("Personalization", "Personalizzazione"),
                               L("How strongly your past writing shapes suggestions.", "Quanto i tuoi testi passati influenzano i suggerimenti."), indent: true) {
                        Slider(value: $settings.prefs.personalizeStrength, in: 0...5, step: 1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text(L("Off", "No")).font(.caption)
                        } maximumValueLabel: {
                            Text("Max").font(.caption)
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    }
                }
                .disabled(!settings.prefs.recordWriting)
                SettingRow(L("Saved texts", "Testi salvati"),
                           detail: history.count == 1
                               ? L("1 text · \(Fmt.bytes(history.diskBytes)) on disk", "1 testo · \(Fmt.bytes(history.diskBytes)) su disco")
                               : L("\(history.count) texts · \(Fmt.bytes(history.diskBytes)) on disk", "\(history.count) testi · \(Fmt.bytes(history.diskBytes)) su disco")) {
                    HStack {
                        Button(L("Manage…", "Gestisci…")) { showData = true }
                            .disabled(history.count == 0)
                        Button(L("Delete All…", "Elimina tutto…")) { confirmDelete = true }
                            .disabled(history.count == 0)
                    }
                }
            }

            GlassSection(L("Memory", "Memoria")) {
                ToggleRow(L("Remember recent topics", "Ricorda gli argomenti recenti"),
                          L("Keeps short encrypted notes about what you wrote recently, so later suggestions have that context. Notes fade when a topic stops coming up. Follows each app's recording setting.", "Conserva brevi note cifrate su ciò che hai scritto di recente, così i suggerimenti successivi hanno quel contesto. Le note svaniscono quando un argomento non torna più. Segue l'impostazione di registrazione di ogni app."),
                          isOn: $settings.prefs.memoryEnabled)
                Group {
                    SettingRow(L("Forget after", "Dimentica dopo"),
                               L("A topic that comes back starts its timer again.", "Un argomento che ritorna fa ripartire il conto."), indent: true) {
                        GlassMenuPicker(selection: $settings.prefs.memoryDays,
                                        options: [(1, L("1 day", "1 giorno")), (3, L("3 days", "3 giorni")), (7, L("1 week", "1 settimana")), (14, L("2 weeks", "2 settimane"))])
                    }
                    SettingRow(L("Remembered topics", "Argomenti ricordati"),
                               detail: memory.count == 0 ? L("None yet", "Ancora nessuno")
                                   : (memory.count == 1 ? L("1 topic", "1 argomento") : L("\(memory.count) topics", "\(memory.count) argomenti")),
                               indent: true) {
                        Button(L("Forget All…", "Dimentica tutto…")) { confirmForget = true }
                            .disabled(memory.count == 0)
                    }
                    if memory.count > 0 {
                        DisclosureGroup(L("Show topics", "Mostra argomenti")) {
                            ForEach(memory.episodes.sorted { $0.touched > $1.touched }.prefix(50)) { e in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill(Theme.aurora)
                                        .frame(width: 8, height: 8)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.text).font(.callout).lineLimit(2)
                                        Text("\(e.appName) · \(Fmt.relative(e.touched))\(e.strength > 1.5 ? L(" · mentioned often", " · citato spesso") : "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { memory.delete(e.id) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                        .help(L("Forget this", "Dimentica"))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .disabled(!settings.prefs.memoryEnabled)
            }

            GlassSection(L("Writing Style", "Stile di scrittura")) {
                ToggleRow(L("Learn my style", "Impara il mio stile"),
                          L("Learns language, tone, sentence length, punctuation, greetings, sign-offs and favorite expressions from your history, per app. Analyzed on this computer while idle.", "Impara lingua, tono, lunghezza delle frasi, punteggiatura, saluti, chiusure ed espressioni preferite dalla tua cronologia, per ogni app. Analizzato su questo computer quando è inattivo."),
                          isOn: $settings.prefs.learnStyle)
                Group {
                    if style.global.isEmpty {
                        Text(history.count < 8
                             ? L("Needs a few more texts (\(history.count) of 8).", "Servono ancora alcuni testi (\(history.count) di 8).")
                             : (style.analyzing ? L("Analyzing your writing…", "Analisi della tua scrittura…") : L("Nothing learned yet. Press Analyze Now.", "Ancora niente di appreso. Premi Analizza ora.")))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        StyleSummary(profile: style.global)
                    }
                    HStack {
                        if let date = style.lastAnalyzed {
                            Text(L("Updated", "Aggiornato") + " \(date.formatted(.relative(presentation: .named).locale(Fmt.locale))) · \(style.global.samples) " + L("texts", "testi"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(style.analyzing ? L("Analyzing…", "Analisi…") : L("Analyze Now", "Analizza ora")) { style.refreshIfNeeded(force: true) }
                            .disabled(style.analyzing || history.count < 8)
                    }
                }
                .disabled(!settings.prefs.learnStyle || !settings.prefs.recordWriting)
                .opacity(settings.prefs.learnStyle && settings.prefs.recordWriting ? 1 : 0.5)
            }

            GlassSection(L("Instructions", "Istruzioni")) {
                Text(L("Added to every suggestion: your name, languages, tone, words to use or avoid.", "Aggiunte a ogni suggerimento: il tuo nome, le lingue, il tono, parole da usare o evitare."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GlassTextEditor(text: $settings.prefs.customInstructions, minHeight: 160)
                HStack {
                    Spacer()
                    Button(L("Reset to Default", "Ripristina predefinito")) { settings.prefs.customInstructions = "" }
                }
            }

            GlassSection("Cache") {
                SettingRow(L("Temporary data", "Dati temporanei"), L("Text read from the screen, recent suggestions and the log. Your history and memories stay.", "Testo letto dallo schermo, suggerimenti recenti e il log. Cronologia e memorie restano."),
                           detail: Fmt.bytes(cacheBytes)) {
                    Button(cacheCleared ? L("Cleared", "Svuotata") : L("Clear Cache", "Svuota cache")) {
                        TempCache.clear(); cacheBytes = TempCache.bytes; cacheCleared = true
                    }
                    .disabled(cacheCleared)
                }
            }
            .onAppear { cacheBytes = TempCache.bytes; cacheCleared = false }
        }
        .sheet(isPresented: $showData) { HistoryBrowser() }
        .alert(L("Delete all saved texts?", "Eliminare tutti i testi salvati?"), isPresented: $confirmDelete) {
            Button(L("Delete All", "Elimina tutto"), role: .destructive) { History.shared.deleteAll() }
            Button(L("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(L("Your writing history is removed from this computer. This can't be undone.", "La tua cronologia di scrittura viene rimossa da questo computer. L'operazione è irreversibile."))
        }
        .alert(L("Forget all remembered topics?", "Dimenticare tutti gli argomenti ricordati?"), isPresented: $confirmForget) {
            Button(L("Forget All", "Dimentica tutto"), role: .destructive) { Memory.shared.deleteAll() }
            Button(L("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(L("All remembered topics are removed.", "Tutti gli argomenti ricordati vengono rimossi."))
        }
    }
}

/// What NexoLLM learned about your writing: traits as glass chips, then your openings, closings and expressions.
private struct StyleSummary: View {
    let profile: StyleProfile.Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !profile.traits.isEmpty {
                FlowChips(items: profile.traits, symbol: "sparkle")
            }
            row(L("Opens with", "Apre con"), profile.openings, symbol: "hand.wave")
            row(L("Closes with", "Chiude con"), profile.closings, symbol: "signature")
            row(L("Your expressions", "Le tue espressioni"), profile.phrases, symbol: "quote.opening")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ title: String, _ items: [String], symbol: String) -> some View {
        if !items.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Text(items.map { "“\($0)”" }.joined(separator: "  ·  "))
                    .font(.system(size: 12.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Wrapping row of capsule chips.
private struct FlowChips: View {
    let items: [String]
    let symbol: String

    var body: some View {
        FlowLayout(hSpacing: 6, vSpacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(item).font(.system(size: 11.5, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.accent.opacity(0.10)))
            }
        }
    }
}

/// Every saved text: search, filter by app, delete one by one or keep only the recent ones.
private struct HistoryBrowser: View {
    @ObservedObject private var history = History.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var app: String? = nil

    private var apps: [String] { Array(Set(history.entries.map(\.app))).sorted { AppInfo.name($0) < AppInfo.name($1) } }

    private var rows: [(index: Int, entry: History.Entry)] {
        history.entries.enumerated().reversed()
            .filter { app == nil || $0.element.app == app }
            .filter { query.isEmpty || $0.element.text.localizedCaseInsensitiveContains(query) }
            .map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Saved Texts", "Testi salvati")).font(.system(size: 15, weight: .semibold))
                    Text(L("\(history.count) texts · \(Fmt.bytes(history.diskBytes)) on disk, encrypted", "\(history.count) testi · \(Fmt.bytes(history.diskBytes)) su disco, cifrati"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                GlassActionMenu(L("Keep Last…", "Tieni gli ultimi…"), items: [50, 100, 250].map { n in
                    ("\(n) " + L("texts", "testi"), history.count > n, { history.keepRecent(n) })
                })
                Button(L("Done", "Fine")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search", "Cerca"), text: $query).textFieldStyle(.plain)
                GlassMenuPicker(selection: $app,
                                options: [(String?.none, L("All apps", "Tutte le app"))] + apps.map { (String?.some($0), AppInfo.name($0)) })
            }
            .padding(.horizontal, 16).padding(.bottom, 10)
            Divider()
            List {
                ForEach(rows, id: \.index) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: AppInfo.icon(row.entry.app)).resizable().frame(width: 18, height: 18).padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.entry.text).font(.system(size: 12)).lineLimit(3)
                            Text("\(AppInfo.name(row.entry.app)) · \(row.entry.date.formatted(.relative(presentation: .named).locale(Fmt.locale)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { history.delete(at: [row.index]) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help(L("Delete this text", "Elimina questo testo"))
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)
            if let app {
                Divider()
                HStack {
                    Spacer()
                    Button(L("Delete All from \(AppInfo.name(app))", "Elimina tutto da \(AppInfo.name(app))"), role: .destructive) { history.delete(app: app); self.app = nil }
                }
                .padding(12)
            }
        }
        .frame(width: 640, height: 520)
    }
}
