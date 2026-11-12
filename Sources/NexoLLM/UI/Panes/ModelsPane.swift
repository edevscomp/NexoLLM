import SwiftUI

/// The models that write suggestions on this computer: installed, downloadable, importable.
struct ModelsPane: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var models = ModelManager.shared
    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var net = NetworkMonitor.shared
    @State private var pendingDelete: ModelManager.Installed?
    @State private var picked = HardwareProfile.current.recommended.pluggedIn

    private let hardware = HardwareProfile.current

    var body: some View {
        GlassPage {
            if !net.isOnline {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash").foregroundStyle(Theme.amber)
                    Text(L("No connection — installed models keep working normally. New downloads are unavailable until the connection returns.",
                           "Nessuna connessione — i modelli installati continuano a funzionare normalmente. I nuovi download non sono disponibili finché non torna la connessione."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(tint: Theme.amber)
            }

            HardwareCard(hardware: hardware, models: models)

            GlassSection(L("Engine", "Motore")) {
                SettingRow(L("Runs on this computer", "Gira su questo computer"),
                           L("Suggestions and writing tools are computed by the model below on this computer's GPU. No text is ever sent to an AI service.",
                             "Suggerimenti e strumenti di scrittura sono calcolati dal modello qui sotto, sulla GPU di questo computer. Nessun testo viene mai inviato a un servizio di IA."),
                           detail: Fmt.status(status.engine)) {
                    Image(systemName: "cpu").foregroundStyle(Theme.accent)
                }
            }

            if let error = models.error {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                    Text(error).font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(L("Dismiss", "Chiudi")) { models.error = nil }
                }
                .padding(12)
                .glassCard(tint: Theme.amber)
            }

            GlassSection(L("Installed", "Installati")) {
                if models.installed.isEmpty {
                    SettingRow(L("No models yet", "Ancora nessun modello"),
                               detail: L("Download one below or import a GGUF file.", "Scaricane uno qui sotto o importa un file GGUF."))
                }
                ForEach(models.installed) { item in
                    InstalledRow(item: item, onDelete: { pendingDelete = item })
                }
                EnumPickerRow(L("Switching", "Cambio modello"),
                              L("Automatic uses the battery model when unplugged and switches back when you plug in. Only one model is in memory at a time.",
                                "Automatico usa il modello a batteria quando scolleghi l'alimentatore e torna indietro quando lo ricolleghi. In memoria c'è un solo modello alla volta."),
                              selection: $settings.prefs.modelMode) { $0.label }
            }

            GlassSection(L("Download", "Scarica")) {
                // Downloads in progress stay visible; the rest is one box to pick from.
                ForEach(CatalogModel.all.filter { models.downloads[$0.id] != nil && $0 != picked }) { m in
                    CatalogRow(model: m, hardware: hardware, models: models)
                }
                SettingRow(L("Model", "Modello")) {
                    GlassMenuPicker(selection: $picked, options: CatalogModel.all.map { m -> (CatalogModel, String) in
                        let rec = m == hardware.recommended.pluggedIn || m == hardware.recommended.battery
                        return (m, "\(m.name) · \(Fmt.bytes(m.bytes))\(rec ? " ★" : "")")
                    })
                }
                CatalogRow(model: picked, hardware: hardware, models: models)
                HStack(spacing: 8) {
                    Button(L("Import GGUF…", "Importa GGUF…")) {
                        if let path = SettingsUI.chooseGGUF(), let imported = models.importModel(at: path) {
                            models.use(imported, battery: false)
                        }
                    }
                    Button(L("Show Models Folder", "Mostra cartella modelli")) { NSWorkspace.shared.activateFileViewerSelecting([Settings.modelsFolder]) }
                    Spacer()
                    Button { NSWorkspace.shared.open(CatalogModel.browseURL) } label: {
                        Label(L("Browse Hugging Face", "Sfoglia Hugging Face"), systemImage: "arrow.up.right")
                    }
                    .disabled(!net.isOnline)
                    .opacity(net.isOnline ? 1 : 0.45)
                }
            }
        }
        .onAppear { models.refresh() }
        .alert(L("Delete \(pendingDelete?.name ?? "model")?", "Eliminare \(pendingDelete?.name ?? "il modello")?"),
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(L("Delete", "Elimina"), role: .destructive) { if let p = pendingDelete { models.delete(p) }; pendingDelete = nil }
            Button(L("Cancel", "Annulla"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L("This frees \(Fmt.bytes(pendingDelete?.bytes ?? 0)) of disk space. You can download it again later.",
                   "Libera \(Fmt.bytes(pendingDelete?.bytes ?? 0)) di spazio su disco. Potrai scaricarlo di nuovo in seguito."))
        }
    }
}

// MARK: - Hardware

private struct HardwareCard: View {
    let hardware: HardwareProfile
    @ObservedObject var models: ModelManager
    @ObservedObject private var settings = Settings.shared

    private var rec: (pluggedIn: CatalogModel, battery: CatalogModel) { hardware.recommended }
    private var applied: Bool {
        guard let a = models.installed(rec.pluggedIn), let b = models.installed(rec.battery) else { return false }
        return settings.prefs.modelPath == a.path
            && (settings.prefs.batteryModelPath == b.path || a.path == b.path)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cpu")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(hardware.summary).font(.system(size: 14, weight: .semibold))
                Text(L("Recommended: \(rec.pluggedIn.name) plugged in, \(rec.battery.name) on battery.",
                       "Consigliati: \(rec.pluggedIn.name) con alimentatore, \(rec.battery.name) a batteria."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if applied {
                StatusPill(text: L("In use", "In uso"), symbol: "checkmark.circle.fill", color: Theme.mint)
            } else {
                Button(L("Use Recommended", "Usa consigliati")) { models.applyRecommended() }
                    .disabled(!models.downloads.isEmpty)
            }
        }
        .padding(16)
        .glassCard()
    }
}

// MARK: - Rows

private struct InstalledRow: View {
    let item: ModelManager.Installed
    let onDelete: () -> Void
    @ObservedObject private var settings = Settings.shared

    private var roles: [String] {
        var r: [String] = []
        if settings.prefs.modelPath == item.path { r.append(L("plugged in", "con alimentatore")) }
        let battery = settings.prefs.batteryModelPath.isEmpty ? settings.prefs.modelPath : settings.prefs.batteryModelPath
        if battery == item.path { r.append(L("on battery", "a batteria")) }
        return r
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: roles.isEmpty ? "shippingbox" : "shippingbox.fill")
                .foregroundStyle(roles.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13, weight: .medium))
                Text([Fmt.bytes(item.bytes),
                      roles.isEmpty ? nil : L("In use ", "In uso ") + roles.joined(separator: L(" and ", " e "))].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            GlassActionMenu(L("Use", "Usa"), items: [
                (L("When plugged in", "Con alimentatore"), true, { ModelManager.shared.use(item.path, battery: false) }),
                (L("On battery", "A batteria"), true, { ModelManager.shared.use(item.path, battery: true) }),
            ])
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(L("Delete this model from disk", "Elimina questo modello dal disco"))
        }
    }
}

private struct CatalogRow: View {
    let model: CatalogModel
    let hardware: HardwareProfile
    @ObservedObject var models: ModelManager

    private var recommended: Bool {
        let r = hardware.recommended
        return model == r.pluggedIn || model == r.battery
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name).font(.system(size: 13, weight: .medium))
                    if recommended {
                        Text(L("Recommended", "Consigliato"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    }
                }
                Text("\(model.localizedDetail) · \(Fmt.bytes(model.bytes))"
                     + (hardware.fits(model) ? "" : L(" · needs \(model.minMemoryGB) GB memory", " · servono \(model.minMemoryGB) GB di memoria")))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            if let d = models.downloads[model.id] {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: d.fraction).frame(width: 150)
                    Text(d.verifying ? L("Verifying…", "Verifica…") : progressText(d))
                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
                }
                if !d.verifying {
                    Button { models.cancel(model) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help(L("Cancel", "Annulla"))
                }
            } else if models.installed(model) != nil {
                Label(L("Installed", "Installato"), systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
            } else {
                Button(L("Download", "Scarica")) { models.download(model) }
                    .disabled(!NetworkMonitor.shared.isOnline)
                    .opacity(NetworkMonitor.shared.isOnline ? 1 : 0.45)
            }
            Button { NSWorkspace.shared.open(model.page) } label: { Image(systemName: "arrow.up.right.square") }
                .buttonStyle(.borderless).foregroundStyle(.secondary).help(L("Open on Hugging Face", "Apri su Hugging Face"))
        }
    }

    private func progressText(_ d: ModelManager.Download) -> String {
        let speed = d.bytesPerSecond > 0 ? " · \(Fmt.bytes(Int64(d.bytesPerSecond)))/s" : ""
        return "\(Fmt.bytes(d.received)) \(L("of", "di")) \(Fmt.bytes(d.total))\(speed)"
    }
}
