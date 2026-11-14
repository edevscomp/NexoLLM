import Foundation

// MARK: - Hardware

/// What this computer can run comfortably. Unified memory decides it: the model, its context and every
/// other app share the same RAM.
struct HardwareProfile {
    let chip: String
    let memoryGB: Int

    static let current: HardwareProfile = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let chip = String(cString: buf).trimmingCharacters(in: .whitespaces)
        let gb = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        return HardwareProfile(chip: chip.isEmpty ? "CPU" : chip, memoryGB: gb)
    }()

    var summary: String { "\(chip) · \(memoryGB) GB " + L("memory", "di memoria") }

    /// Best model for each power state on this computer.
    var recommended: (pluggedIn: CatalogModel, battery: CatalogModel) {
        switch memoryGB {
        case ..<12: return (.gemmaE2B, .llama3B)
        default: return (.gemmaE4B, .gemmaE2B)
        }
    }

    func fits(_ m: CatalogModel) -> Bool { memoryGB >= m.minMemoryGB }
}

// MARK: - Catalog

/// Base (non-chat) models: they continue text instead of answering it, which is what autocomplete needs.
/// Files come from Hugging Face and are verified against their SHA-256 after downloading.
struct CatalogModel: Identifiable, Hashable {
    let id: String           // file name
    let name: String
    let detail: String
    let repo: String
    let bytes: Int64
    let sha256: String
    let minMemoryGB: Int

    var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/main/\(id)")! }
    var page: URL { URL(string: "https://huggingface.co/\(repo)")! }

    /// `detail` in the app language.
    var localizedDetail: String {
        switch id {
        case "gemma-4-E4B.i1-Q4_K_M.gguf": return L("Google · best quality", "Google · massima qualità")
        case "gemma-4-E2B.i1-Q4_K_M.gguf": return L("Google · fast, good on battery", "Google · veloce, buono a batteria")
        case "Llama-3.2-3B.i1-Q4_K_M.gguf": return L("Meta · lightest, English first", "Meta · il più leggero, soprattutto inglese")
        case "Qwen2.5-7B.i1-Q4_K_M.gguf": return L("Alibaba · strong in many languages", "Alibaba · forte in molte lingue")
        case "Mistral-7B-v0.3.i1-Q4_K_M.gguf": return L("Mistral AI · natural prose", "Mistral AI · prosa naturale")
        case "Qwen2.5-3B.i1-Q4_K_M.gguf": return L("Alibaba · fast, many languages", "Alibaba · veloce, molte lingue")
        case "SmolLM2-1.7B.i1-Q4_K_M.gguf": return L("Hugging Face · very light, English", "Hugging Face · molto leggero, inglese")
        case "Llama-3.2-1B.i1-Q4_K_M.gguf": return L("Meta · smallest, English", "Meta · il più piccolo, inglese")
        default: return detail
        }
    }

    static let gemmaE4B = CatalogModel(
        id: "gemma-4-E4B.i1-Q4_K_M.gguf", name: "Gemma 4 E4B", detail: "Google · best quality",
        repo: "mradermacher/gemma-4-E4B-i1-GGUF", bytes: 5_335_274_240,
        sha256: "687f4cce47eac6ccfc595fd9517215fb964e5e5be17d4774b25b8add401d6d3c", minMemoryGB: 16)
    static let gemmaE2B = CatalogModel(
        id: "gemma-4-E2B.i1-Q4_K_M.gguf", name: "Gemma 4 E2B", detail: "Google · fast, good on battery",
        repo: "mradermacher/gemma-4-E2B-i1-GGUF", bytes: 3_427_862_240,
        sha256: "3cc0e9c2b4bbffea7f3f6cfe1ffd1591f4dafe02c43f78952f1142a24172df65", minMemoryGB: 8)
    static let llama3B = CatalogModel(
        id: "Llama-3.2-3B.i1-Q4_K_M.gguf", name: "Llama 3.2 3B", detail: "Meta · lightest, English first",
        repo: "mradermacher/Llama-3.2-3B-i1-GGUF", bytes: 2_019_374_176,
        sha256: "b146275f11611442b9154fb552ccc12aeb9ca068f5c81e68962b710c59d21fb1", minMemoryGB: 8)
    static let qwen7B = CatalogModel(
        id: "Qwen2.5-7B.i1-Q4_K_M.gguf", name: "Qwen 2.5 7B", detail: "Alibaba · strong in many languages",
        repo: "mradermacher/Qwen2.5-7B-i1-GGUF", bytes: 4_683_074_208,
        sha256: "14b58251e24136547ecdcd7d454ad10147cb6415176103202fb99df844de9188", minMemoryGB: 16)
    static let mistral7B = CatalogModel(
        id: "Mistral-7B-v0.3.i1-Q4_K_M.gguf", name: "Mistral 7B v0.3", detail: "Mistral AI · natural prose",
        repo: "mradermacher/Mistral-7B-v0.3-i1-GGUF", bytes: 4_372_811_936,
        sha256: "2719cfd0fbf93e69f8bce7879bde7b831f32d71f0b0c73505a5dbd7667ae2952", minMemoryGB: 16)
    static let qwen3B = CatalogModel(
        id: "Qwen2.5-3B.i1-Q4_K_M.gguf", name: "Qwen 2.5 3B", detail: "Alibaba · fast, many languages",
        repo: "mradermacher/Qwen2.5-3B-i1-GGUF", bytes: 1_929_903_264,
        sha256: "1b5d87d195ec4b31566180ec775516a36300350ba536b63450c4e7a7f74e9e61", minMemoryGB: 8)
    static let smolLM2 = CatalogModel(
        id: "SmolLM2-1.7B.i1-Q4_K_M.gguf", name: "SmolLM2 1.7B", detail: "Hugging Face · very light, English",
        repo: "mradermacher/SmolLM2-1.7B-i1-GGUF", bytes: 1_055_609_632,
        sha256: "765f6d5446cb32e21df03b38fbd0c3c7bb623351e0046bef19a9b79649e46114", minMemoryGB: 8)
    static let llama1B = CatalogModel(
        id: "Llama-3.2-1B.i1-Q4_K_M.gguf", name: "Llama 3.2 1B", detail: "Meta · smallest, English",
        repo: "mradermacher/Llama-3.2-1B-i1-GGUF", bytes: 807_690_912,
        sha256: "88e40c698c7d97013defc16cc36d2b3b7a2feb28bc16992f6be403eaddddac7c", minMemoryGB: 8)

    static let all: [CatalogModel] = [gemmaE4B, qwen7B, mistral7B, gemmaE2B, qwen3B, llama3B, smolLM2, llama1B]

    static let browseURL = URL(string: "https://huggingface.co/models?library=gguf&sort=trending")!

    /// "gemma-4-E2B-i1-Q4_K_M.gguf" and "gemma-4-E2B.i1-Q4_K_M.gguf" are the same model.
    static func normalized(_ file: String) -> String {
        file.lowercased().replacingOccurrences(of: ".gguf", with: "").filter { $0.isLetter || $0.isNumber }
    }

    static func match(_ file: String) -> CatalogModel? {
        let n = normalized(file)
        return all.first { normalized($0.id) == n }
    }
}

// MARK: - Manager

/// Installed models, downloads and deletion. Everything lives in the app's Models folder.
@MainActor
final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()

    struct Installed: Identifiable, Hashable {
        let path: String
        let bytes: Int64
        var id: String { path }
        var file: String { (path as NSString).lastPathComponent }
        var catalog: CatalogModel? { CatalogModel.match(file) }
        var name: String { catalog?.name ?? file.replacingOccurrences(of: ".gguf", with: "") }
    }

    struct Download: Equatable {
        var received: Int64 = 0
        var total: Int64
        var bytesPerSecond: Double = 0
        var verifying = false
        var fraction: Double { total > 0 ? min(1, Double(received) / Double(total)) : 0 }
    }

    @Published private(set) var installed: [Installed] = []
    @Published private(set) var downloads: [String: Download] = [:]
    @Published var error: String?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var models: [Int: CatalogModel] = [:]   // task identifier -> model
    private var speedMark: [String: (Date, Int64)] = [:]
    private var lastUIUpdate: [String: Date] = [:]
    private lazy var session = URLSession(configuration: SecureNet.configuration(timeout: 60), delegate: self, delegateQueue: .main)

    private var folder: URL { Settings.modelsFolder }
    private var settings: Settings { Settings.shared }

    override private init() {
        super.init()
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        installed = files.filter { $0.pathExtension == "gguf" }.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return Installed(path: url.path, bytes: size)
        }.sorted { $0.bytes > $1.bytes }
        // A model chosen elsewhere on disk (imported) is listed too.
        for path in [settings.prefs.modelPath, settings.prefs.batteryModelPath]
        where !path.isEmpty && !installed.contains(where: { $0.path == path }) && fm.fileExists(atPath: path) {
            let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
            installed.append(Installed(path: path, bytes: size))
        }
    }

    func installed(_ m: CatalogModel) -> Installed? { installed.first { $0.catalog == m } }

    var totalBytes: Int64 { installed.reduce(0) { $0 + $1.bytes } }

    // MARK: Choosing

    func use(_ path: String, battery: Bool) {
        if battery { settings.prefs.batteryModelPath = path } else { settings.prefs.modelPath = path }
    }

    /// Uses the recommended models, downloading what's missing.
    func applyRecommended() {
        let rec = HardwareProfile.current.recommended
        for (m, battery) in [(rec.pluggedIn, false), (rec.battery, true)] {
            if let i = installed(m) { use(i.path, battery: battery) } else { download(m, thenUseFor: battery) }
        }
    }

    // MARK: Deleting

    /// Deletes the file for good (the Trash wouldn't free the space). If it was in use, switches to
    /// another installed model.
    func delete(_ item: Installed) {
        do {
            try FileManager.default.removeItem(atPath: item.path)
        } catch {
            self.error = L("Couldn't delete \(item.name): ", "Impossibile eliminare \(item.name): ") + error.localizedDescription
            return
        }
        refresh()
        let fallback = installed.first?.path ?? ""
        if settings.prefs.batteryModelPath == item.path { settings.prefs.batteryModelPath = "" }
        if settings.prefs.modelPath == item.path { settings.prefs.modelPath = fallback }
        Log.info("models: deleted \(item.file) (\(Fmt.bytes(item.bytes)))")
    }

    // MARK: Importing

    /// Brings a GGUF from elsewhere into the Models folder (APFS clone: instant, no extra space).
    func importModel(at path: String) -> String? {
        let target = folder.appendingPathComponent((path as NSString).lastPathComponent)
        if path != target.path, !FileManager.default.fileExists(atPath: target.path) {
            do { try FileManager.default.copyItem(atPath: path, toPath: target.path) } catch {
                self.error = L("Couldn't import the model: ", "Impossibile importare il modello: ") + error.localizedDescription
                return nil
            }
        }
        refresh()
        return target.path
    }

    // MARK: Downloading

    private var useAfterDownload: [String: Bool] = [:]

    func download(_ m: CatalogModel, thenUseFor battery: Bool? = nil) {
        guard tasks[m.id] == nil else { return }
        if let battery { useAfterDownload[m.id] = battery }
        let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? Int64.max
        if free < m.bytes + 1_000_000_000 {
            error = L("Not enough disk space for \(m.name): it needs \(Fmt.bytes(m.bytes)) plus 1 GB free.", "Spazio su disco insufficiente per \(m.name): servono \(Fmt.bytes(m.bytes)) più 1 GB libero.")
            return
        }
        error = nil
        let task = session.downloadTask(with: m.url)
        tasks[m.id] = task
        models[task.taskIdentifier] = m
        downloads[m.id] = Download(total: m.bytes)
        speedMark[m.id] = (Date(), 0)
        task.resume()
        Log.info("models: downloading \(m.id)")
    }

    func cancel(_ m: CatalogModel) {
        tasks[m.id]?.cancel()
        tasks[m.id] = nil
        downloads[m.id] = nil
        useAfterDownload[m.id] = nil
    }

    private func finished(_ m: CatalogModel, file: URL) {
        downloads[m.id]?.verifying = true
        let target = folder.appendingPathComponent(m.id)
        Task.detached(priority: .utility) {
            let ok = SecureFile.sha256(of: file) == m.sha256
            await MainActor.run {
                let mgr = ModelManager.shared
                mgr.tasks[m.id] = nil
                mgr.downloads[m.id] = nil
                mgr.lastUIUpdate[m.id] = nil
                guard ok else {
                    try? FileManager.default.removeItem(at: file)
                    mgr.error = L("\(m.name) didn't match its checksum and was discarded. Try again.", "\(m.name) non corrisponde al checksum ed è stato scartato. Riprova.")
                    return
                }
                try? FileManager.default.removeItem(at: target)
                do { try FileManager.default.moveItem(at: file, to: target) } catch {
                    mgr.error = L("Couldn't save \(m.name): ", "Impossibile salvare \(m.name): ") + error.localizedDescription
                    return
                }
                SecureFile.restrict(target)
                mgr.refresh()
                Log.info("models: installed \(m.id)")
                if let battery = mgr.useAfterDownload.removeValue(forKey: m.id) { mgr.use(target.path, battery: battery) }
                else if Settings.shared.prefs.modelPath.isEmpty || !FileManager.default.fileExists(atPath: Settings.shared.prefs.modelPath) {
                    mgr.use(target.path, battery: false)
                }
            }
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    /// Model downloads may only be redirected to Hugging Face's own HTTPS hosts (the SHA-256 check after the
    /// download is the real guarantee; this keeps the request itself from wandering off).
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              SecureNet.isHuggingFaceHost(host) else {
            Log.info("models: blocked a redirect to \(request.url?.host ?? "?")")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            guard let m = models[downloadTask.taskIdentifier], var d = downloads[m.id] else { return }
            let now = Date()
            if let last = lastUIUpdate[m.id], now.timeIntervalSince(last) < 0.1,
               totalBytesExpectedToWrite <= 0 || totalBytesWritten < totalBytesExpectedToWrite {
                return
            }
            lastUIUpdate[m.id] = now
            d.received = totalBytesWritten
            if totalBytesExpectedToWrite > 0 { d.total = totalBytesExpectedToWrite }
            if let (t, b) = speedMark[m.id], now.timeIntervalSince(t) >= 1 {
                d.bytesPerSecond = Double(totalBytesWritten - b) / now.timeIntervalSince(t)
                speedMark[m.id] = (now, totalBytesWritten)
            }
            downloads[m.id] = d
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file disappears when this returns: move it next to the models first.
        let keep = Settings.modelsFolder.appendingPathComponent(UUID().uuidString + ".part")
        let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        MainActor.assumeIsolated {
            guard let m = models.removeValue(forKey: downloadTask.taskIdentifier) else { return }
            guard moved, status == 200 else {
                try? FileManager.default.removeItem(at: keep)
                tasks[m.id] = nil; downloads[m.id] = nil
                error = L("Download of \(m.name) failed (HTTP \(status)).", "Download di \(m.name) non riuscito (HTTP \(status)).")
                return
            }
            finished(m, file: keep)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        MainActor.assumeIsolated {
            guard let m = models.removeValue(forKey: task.taskIdentifier) else { return }
            tasks[m.id] = nil; downloads[m.id] = nil
            self.error = L("Download of \(m.name) stopped: ", "Download di \(m.name) interrotto: ") + error.localizedDescription
        }
    }
}
