import AppKit
import CryptoKit

/// Checks GitHub Releases for a newer version and downloads its DMG; installing stays manual
/// (drag to Applications), so macOS keeps the app's permissions under control of the user.
///
/// Nothing downloaded is opened unless it carries a valid Ed25519 signature made with NexoLLM's release key,
/// whose public half is compiled into the app. The signature covers the version and the file's SHA-256, so a
/// tampered file, a file served by someone in the middle of the connection, or an older release passed off as
/// new is rejected and deleted — even if the GitHub account itself were compromised.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable { let version: String; let dmg: URL; let signature: URL? }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var downloading = false
    /// Result of the last check or download, for the About pane.
    @Published private(set) var message: String?

    private static let api = URL(string: "https://api.github.com/repos/edevscomp/NexoLLM/releases/latest")!
    private static let lastCheckKey = "updates.lastCheck"
    /// Public half of the release signing key (Ed25519, raw 32 bytes, base64). The private half never leaves
    /// the maintainer's Keychain: see scripts/release-signing.swift.
    static let publicKeyBase64 = "AUq3fVygMR4hxBPj8avt5+pd3BYGUCdFQVA4QhTfBIo="
    private var timer: Timer?
    private lazy var session = SecureNet.session(timeout: 30) { SecureNet.isAllowed($0, hosts: SecureNet.githubHosts) }

    /// Automatic check: shortly after launch, then once a day (if allowed in Settings).
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard Settings.shared.prefs.autoCheckUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= 86_400 { check() }
    }

    func check() {
        guard !checking else { return }
        checking = true; message = nil
        var req = URLRequest(url: Self.api, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        session.dataTask(with: req) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let release = ok ? data.flatMap(Self.parse) : nil
            DispatchQueue.main.async {
                self.checking = false
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                guard let release else { self.message = L("Couldn't reach GitHub", "Impossibile raggiungere GitHub"); return }
                let newer = Self.isNewer(release.version, than: Brand.version)
                self.available = newer ? release : nil
                self.message = newer ? nil : L("You're up to date", "Sei aggiornato")
                if newer { Log.info("updates: \(release.version) available") }
            }
        }.resume()
    }

    /// Downloads the DMG and its signature, verifies both, and only then saves the DMG to Downloads and opens it.
    func download() {
        guard let r = available, !downloading else { return }
        guard let sigURL = r.signature else {
            message = L("This release isn't signed, so it won't be installed automatically. Download it from GitHub only if you trust it.",
                        "Questa versione non è firmata, quindi non verrà installata automaticamente. Scaricala da GitHub solo se ti fidi.")
            return
        }
        downloading = true; message = nil
        session.dataTask(with: sigURL) { [weak self] sigData, sigResponse, _ in
            guard let self else { return }
            guard (sigResponse as? HTTPURLResponse)?.statusCode == 200, let sigData,
                  let sig = Data(base64Encoded: String(decoding: sigData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else {
                self.finish(nil, error: L("Couldn't download the update's signature", "Impossibile scaricare la firma dell'aggiornamento"))
                return
            }
            self.session.downloadTask(with: r.dmg) { tmp, response, error in
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.finish(nil, error: error?.localizedDescription ?? L("Download failed", "Download non riuscito"))
                    return
                }
                let verdict = Self.verify(file: tmp, signature: sig, version: r.version, installed: Brand.version)
                guard verdict == .valid else {
                    try? FileManager.default.removeItem(at: tmp)
                    Log.info("updates: rejected \(r.version): \(verdict)")
                    self.finish(nil, error: L("Security check failed: the downloaded update is not an authentic NexoLLM release and was deleted.",
                                              "Controllo di sicurezza fallito: l'aggiornamento scaricato non è una versione autentica di NexoLLM ed è stato eliminato."))
                    return
                }
                let dest = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("\(Brand.name)-\(r.version).dmg")
                try? FileManager.default.removeItem(at: dest)
                let saved = (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil ? dest : nil
                self.finish(saved, error: saved == nil ? L("Download failed", "Download non riuscito") : nil)
            }.resume()
        }.resume()
    }

    private func finish(_ saved: URL?, error: String?) {
        DispatchQueue.main.async {
            self.downloading = false
            guard let saved else { self.message = error; return }
            Log.info("updates: verified and saved \(saved.lastPathComponent)")
            NSWorkspace.shared.open(saved)
            self.message = L("Signature verified. Quit \(Brand.name), then drag the new version to Applications",
                             "Firma verificata. Esci da \(Brand.name), poi trascina la nuova versione in Applicazioni")
        }
    }

    // MARK: Pure helpers (unit-tested)

    enum Verdict: Equatable { case valid, badSignature, notNewer, malformed }

    /// The exact bytes the release key signs.
    static func signedMessage(version: String, sha256: String) -> Data {
        Data("NexoLLM-release-v1:\(version):\(sha256.lowercased())".utf8)
    }

    static func sha256Hex(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Valid only if `signature` signs this file's SHA-256 *and* `version`, with the embedded key (or `publicKey`
    /// in tests), and `version` is newer than the installed one (no downgrades).
    static func verify(file: URL, signature: Data, version: String, installed: String,
                       publicKey: String = publicKeyBase64) -> Verdict {
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              signature.count == 64, let sha = sha256Hex(of: file) else { return .malformed }
        guard isNewer(version, than: installed) else { return .notNewer }
        return key.isValidSignature(signature, for: signedMessage(version: version, sha256: sha)) ? .valid : .badSignature
    }

    static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { a -> (String, URL)? in
            guard let name = a["name"] as? String,
                  let url = (a["browser_download_url"] as? String).flatMap(URL.init(string:)),
                  isTrustedDownload(url) else { return nil }
            return (name, url)
        }
        let dmgs = assets.filter { $0.0.hasSuffix(".dmg") }
        guard let dmg = dmgs.first(where: { $0.0 == "\(Brand.name).dmg" }) ?? dmgs.first else { return nil }
        let sig = assets.first { $0.0 == dmg.0 + ".sig" }?.1
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), dmg: dmg.1, signature: sig)
    }

    /// Updates are downloaded only over HTTPS from GitHub's own release hosts.
    static func isTrustedDownload(_ url: URL) -> Bool {
        SecureNet.isAllowed(url, hosts: SecureNet.githubHosts.subtracting(["api.github.com"]))
    }

    /// "0.10.0" > "0.9.2". Non-numeric versions ("dev") are never older than anything.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        guard !pb.isEmpty else { return false }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Release notes for the running version, from the CHANGELOG.md bundled in the app (works offline).
enum WhatsNew {
    static var notes: String? {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return section(Brand.version, in: text)
    }

    /// The body of `## [version]` up to the next release heading.
    static func section(_ version: String, in text: String) -> String? {
        guard let r = text.range(of: "## [\(version)]") else { return nil }
        let body = text[r.upperBound...].drop { $0 != "\n" }
        let end = body.range(of: "\n## [")?.lowerBound ?? body.endIndex
        return String(body[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True once, on the first launch after an update (not after a fresh install).
    static func consumeLaunchFlag() -> Bool {
        let d = UserDefaults.standard
        guard Brand.version != "dev" else { return false }
        let last = d.string(forKey: "whatsNew.lastSeen")
        d.set(Brand.version, forKey: "whatsNew.lastSeen")
        return last.map { $0 != Brand.version } ?? (d.data(forKey: "prefs.v2") != nil)
    }
}
