import SwiftUI

struct EmojiPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        GlassPage {
            GlassSection {
                ToggleRow(L("Emoji picker", "Selettore emoji"),
                          L("Type a colon and a word to see matching emoji. Press a number to insert one.",
                            "Scrivi i due punti e una parola per vedere le emoji corrispondenti. Premi un numero per inserirne una."),
                          isOn: $settings.prefs.emojiEnabled)
                ToggleRow(L("Emoticons to emoji", "Emoticon in emoji"),
                          L("Offers the emoji for text emoticons.", "Propone l'emoji al posto delle emoticon di testo."),
                          indent: true, isOn: $settings.prefs.emoticonsEnabled)
                    .disabled(!settings.prefs.emojiEnabled)
            }
        }
    }
}

struct WordToolsPane: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        GlassPage {
            GlassSection {
                EnumPickerRow(L("Alternatives", "Alternative"),
                              L("Other words for the one you're typing, or other ways to continue the sentence. Press a number to insert one.",
                                "Altre parole per quella che stai scrivendo, o altri modi di continuare la frase. Premi un numero per inserirne una."),
                              selection: $settings.prefs.alternatives) { $0.label }
                SettingRow(L("Show first", "Mostra prima"),
                           L("The list \(settings.prefs.alternativesShortcut.display) opens with. Press it again to switch.",
                             "L'elenco che si apre con \(settings.prefs.alternativesShortcut.display). Premilo di nuovo per cambiare."), indent: true) {
                    GlassSegmentedPicker($settings.prefs.alternativesScope) { $0.label }
                }
                .disabled(settings.prefs.alternatives == .off)
                EnumPickerRow(L("Synonyms", "Sinonimi"),
                              L("Synonyms for the selected word that fit the sentence. Press a number to replace the selection.",
                                "Sinonimi della parola selezionata adatti alla frase. Premi un numero per sostituire la selezione."),
                              selection: $settings.prefs.synonyms) { $0.label }
            }
        }
    }
}

struct AboutPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var net = NetworkMonitor.shared
    private var modals: ModalCenter { .shared }

    var body: some View {
        GlassPage(showsHeader: false) {
            VStack(spacing: 10) {
                BrandOrb(size: 76)
                    .shadow(color: Theme.accent.opacity(0.25), radius: 14, y: 6)
                Text(Brand.name).font(.system(size: 28, weight: .semibold))
                Text(L("Version", "Versione") + " \(Brand.version) (\(Brand.build))")
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                Text(L("On-device AI writing assistant.",
                       "Assistente di scrittura IA sul dispositivo."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "leaf")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Early-stage release", "Progetto nelle fasi iniziali"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L("NexoLLM is in active development. It is designed for reliable everyday writing, but occasional rough edges or imprecise suggestions may still occur. Your feedback helps refine every update.",
                           "NexoLLM è in attivo sviluppo. È pensato per la scrittura di tutti i giorni, ma potrebbero ancora presentarsi piccole imperfezioni o suggerimenti imprecisi. I tuoi feedback aiutano a perfezionare ogni aggiornamento."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            GlassSection {
                SettingRow(L("Updates", "Aggiornamenti"), detail: updateStatus) {
                    if let r = updater.available {
                        Button(updater.downloading ? L("Downloading…", "Download in corso…") : L("Download \(r.version)", "Scarica \(r.version)")) { updater.download() }
                            .disabled(updater.downloading || !net.isOnline)
                    } else {
                        Button(updater.checking ? L("Checking…", "Controllo…") : L("Check for Updates", "Cerca aggiornamenti")) { updater.check() }
                            .disabled(updater.checking || !net.isOnline)
                    }
                }
                ToggleRow(L("Check automatically", "Controlla automaticamente"),
                          L("Looks for a new version on GitHub once a day. Nothing else is sent.", "Cerca una nuova versione su GitHub una volta al giorno. Non viene inviato nient'altro."),
                          isOn: $settings.prefs.autoCheckUpdates)
                    .disabled(!net.isOnline)
                    .opacity(net.isOnline ? 1 : 0.5)
            }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    LinkButton(title: L("What's New", "Novità"), action: { modals.current = .whatsNew }) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .medium))
                    }
                    LinkButton(title: L("Privacy & License", "Privacy e licenza"), action: { modals.current = .privacy }) {
                        Image(systemName: "lock.shield").font(.system(size: 12, weight: .medium))
                    }
                    LinkButton(title: L("Report a Bug", "Segnala un bug"), action: { modals.current = .bugReport }) {
                        Image(systemName: "ladybug").font(.system(size: 12, weight: .medium))
                    }
                    LinkButton(title: "GitHub", action: { NSWorkspace.shared.open(Brand.website) }) {
                        GitHubMark().frame(width: 14, height: 14)
                    }
                }

                LinkButton(title: L("Support the project · Buy Me a Coffee", "Supporta il progetto · Offrimi un caffè"),
                           action: { NSWorkspace.shared.open(Brand.coffee) }) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text(L("Made by \(Brand.author). Free and open source (GNU GPL v3).", "Creato da \(Brand.author). Gratuito e open source (GNU GPL v3)."))
                Button(L("Third-party notices", "Avvisi di terze parti")) {
                    if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private var updateStatus: String {
        if !net.isOnline { return L("Offline · requires Wi-Fi", "Offline · richiede Wi-Fi") }
        if let r = updater.available { return L("Version \(r.version) is available", "La versione \(r.version) è disponibile") }
        return updater.message ?? L("Version", "Versione") + " \(Brand.version)"
    }
}

/// Pill-shaped button with an icon (same hover/focus feedback as every other button).
private struct LinkButton<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder var icon: Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                icon
                Text(title)
            }
        }
        .buttonStyle(GlassButtonStyle(capsule: true))
    }
}
