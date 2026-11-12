import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var stats = Stats.shared
    @ObservedObject private var history = History.shared
    @State private var selection: String?
    @State private var search = ""

    private var recordedCounts: [String: Int] {
        history.entries.reduce(into: [:]) { $0[$1.app, default: 0] += 1 }
    }

    private func appIDs(_ counts: [String: Int]) -> [String] {
        let all = Set(settings.prefs.apps.keys).union(stats.perApp.keys).union(counts.keys).filter { !$0.isEmpty }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return all
            .filter { q.isEmpty || AppInfo.name($0).lowercased().contains(q) || $0.lowercased().contains(q) }
            .sorted { AppInfo.name($0).localizedCaseInsensitiveCompare(AppInfo.name($1)) == .orderedAscending }
    }

    var body: some View {
        let counts = recordedCounts
        let ids = appIDs(counts)
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(pane: .apps)
                .padding(.horizontal, 30)
                .padding(.top, 14)
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Search apps", "Cerca app"), text: $search).textFieldStyle(.plain)
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
                .padding(8)

                List(ids, id: \.self, selection: $selection) { id in
                    HStack(spacing: 8) {
                        Image(nsImage: AppInfo.icon(id)).resizable().frame(width: 20, height: 20)
                        Text(AppInfo.name(id))
                            .strikethrough(settings.config(id).enabled == .off)
                            .foregroundStyle(settings.config(id).enabled == .off ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                        if let n = counts[id], n > 0 {
                            Text("\(n)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .tag(id)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                Divider()
                HStack(spacing: 0) {
                    Button(action: addApp) { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help(L("Add an app", "Aggiungi un'app"))
                    Button(action: removeSelected) { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .help(L("Reset the selected app to default settings", "Ripristina le impostazioni predefinite dell'app selezionata"))
                        .disabled(selection.map { settings.prefs.apps[$0] == nil } ?? true)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 250)
            .glassCard()
            .padding(.leading, 30)
            .padding(.bottom, 24)

            Group {
                if let id = selection {
                    AppDetail(id: id, recorded: counts[id] ?? 0)
                        .id(id)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed").font(.system(size: 40)).foregroundStyle(.tertiary)
                        Text(L("Select an app to customize its settings", "Seleziona un'app per personalizzarne le impostazioni")).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = L("Add an App", "Aggiungi un'app")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        if settings.prefs.apps[id] == nil { settings.prefs.apps[id] = AppConfig() }
        search = ""
        selection = id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        settings.prefs.apps[id] = nil
    }
}

private struct AppDetail: View {
    let id: String
    let recorded: Int
    @ObservedObject private var settings = Settings.shared
    @State private var confirmDelete = false

    var body: some View {
        GlassPage(showsHeader: false) {
            GlassSection {
                HStack(spacing: 14) {
                    Image(nsImage: AppInfo.icon(id)).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppInfo.name(id)).font(.title2.bold())
                        Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }

            GlassSection(L("Completions", "Completamenti")) {
                tri(L("Enable completions", "Attiva i completamenti"), nil, \.enabled, global: settings.prefs.enabledByDefault)
                tri(L("Suggest inside existing text", "Suggerisci dentro il testo esistente"), L("Also suggest when there is text after the cursor.", "Suggerisce anche quando c'è testo dopo il cursore."),
                    \.insideText, global: settings.prefs.completeInsideText)
                tri(L("Spelling checks", "Controllo ortografico"), L("Holds suggestions on typos and offers corrections.", "Sospende i suggerimenti sugli errori e propone correzioni."),
                    \.autocorrect, global: settings.prefs.suppressOnTypo)
                tri(L("Leave Tab alone", "Lascia Tab com'è"), L("Tab keeps its normal behavior in this app. Accept with your other shortcut.", "In questa app Tab mantiene il suo comportamento normale. Accetta con l'altra scorciatoia."),
                    \.disableTab, global: false)
            }

            GlassSection(L("Troubleshooting", "Risoluzione problemi")) {
                ToggleRow(L("Compatibility mode", "Modalità compatibilità"),
                          L("Inserts text by pasting instead of typing. Slower, but works in apps that drop typed text.", "Inserisce il testo incollandolo invece di digitarlo. Più lento, ma funziona nelle app che perdono il testo digitato."),
                          isOn: binding(\.compatibility))
            }

            GlassSection(L("Custom Instructions", "Istruzioni personalizzate")) {
                Text(L("Added to your general instructions, only in this app.", "Aggiunte alle istruzioni generali, solo in questa app."))
                    .font(.callout).foregroundStyle(.secondary)
                GlassTextEditor(text: binding(\.instructions), minHeight: 100)
            }

            GlassSection(L("Typing History", "Cronologia di scrittura")) {
                tri(L("Record your writing", "Registra la tua scrittura"), nil, \.record, global: settings.prefs.recordWriting)
                SettingRow(L("Recorded texts", "Testi registrati"), detail: "\(recorded)") {
                    Button(L("Delete…", "Elimina…")) { confirmDelete = true }.disabled(recorded == 0)
                }
            }
        }
        .alert(L("Delete recorded texts for \(AppInfo.name(id))?", "Eliminare i testi registrati di \(AppInfo.name(id))?"), isPresented: $confirmDelete) {
            Button(L("Delete", "Elimina"), role: .destructive) { History.shared.delete(app: id) }
            Button(L("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(recorded == 1
                 ? L("This permanently removes 1 recorded text.", "Rimuove definitivamente 1 testo registrato.")
                 : L("This permanently removes \(recorded) recorded texts.", "Rimuove definitivamente \(recorded) testi registrati."))
        }
    }

    private func binding<T>(_ kp: WritableKeyPath<AppConfig, T>) -> Binding<T> {
        Binding(get: { settings.config(id)[keyPath: kp] },
                set: { v in settings.updateConfig(id) { $0[keyPath: kp] = v } })
    }

    private func tri(_ title: String, _ description: String?, _ kp: WritableKeyPath<AppConfig, TriState>,
                     global: Bool) -> some View {
        SettingRow(title, description) {
            GlassMenuPicker(selection: binding(kp),
                            options: [(TriState.default, L("Default (\(global ? "on" : "off"))", "Predefinito (\(global ? "sì" : "no"))")), (.on, L("On", "Sì")), (.off, L("Off", "No"))])
        }
    }
}
