import AppKit
import CryptoKit
import XCTest
@testable import NexoLLM

/// Guard rails against regressions introduced by quick, AI-assisted edits: these scan the real sources and
/// resources, so a risky change fails `swift test` (locally and in CI) instead of shipping.
final class SecurityAuditTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func text(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift source line, with its file name, comments stripped.
    private func sourceLines() throws -> [(file: String, line: String)] {
        let dir = Self.root.appendingPathComponent("Sources/NexoLLM")
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 20, "sources not found")
        return try files.flatMap { url in
            try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").compactMap { raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                return line.hasPrefix("//") ? nil : (url.lastPathComponent, line)
            }
        }
    }

    private func hits(_ pattern: String, allow: (String, String) -> Bool = { _, _ in false }) throws -> [String] {
        let re = try NSRegularExpression(pattern: pattern)
        return try sourceLines().filter { f, l in
            re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil && !allow(f, l)
        }.map { "\($0.file): \($0.line)" }
    }

    func testNoPlainHTTPOrTransportSecurityOptOut() throws {
        // The only "http://" allowed is the link detector in SuggestionText, which never opens anything.
        XCTAssertEqual(try hits(#""http://"#) { f, l in f == "SuggestionText.swift" && l.contains("hasPrefix(\"http://\")") }, [])
        XCTAssertFalse(try text("Resources/Info.plist").contains("NSAllowsArbitraryLoads"))
    }

    func testNoShellOrSubprocessExecution() throws {
        XCTAssertEqual(try hits(#"\bProcess\(|\bNSTask\b|/bin/(ba|z)?sh\b|\bpopen\(|(?<![.\w])system\(|NSAppleScript"#), [])
    }

    func testNoHardcodedSecrets() throws {
        let secret = #"\bsk-[A-Za-z0-9_-]{20,}|\bghp_[A-Za-z0-9]{30,}|\bAKIA[0-9A-Z]{16}\b|\bxox[bp]-[0-9A-Za-z-]{20,}|BEGIN [A-Z ]*PRIVATE KEY-----[A-Za-z0-9+/=\s]{40}"#
        XCTAssertEqual(try hits(secret), [])
    }

    func testEntitlementsStayMinimal() throws {
        let dangerous = ["get-task-allow", "allow-dyld-environment-variables", "allow-unsigned-executable-memory",
                         "allow-jit", "disable-executable-page-protection", "automation.apple-events"]
        for file in ["Resources/App.entitlements", "Resources/AdHoc.entitlements"] {
            let plist = try text(file)
            for key in dangerous { XCTAssertFalse(plist.contains(key), "\(file) gained \(key)") }
        }
        // Developer-signed builds: microphone only. Ad-hoc builds also need library validation off to load
        // their own (ad-hoc signed) frameworks — nothing else.
        XCTAssertFalse(try text("Resources/App.entitlements").contains("disable-library-validation"))
    }

    func testPasswordFieldsAreNeverRead() throws {
        let ax = try text("Sources/NexoLLM/Accessibility.swift")
        XCTAssertTrue(ax.contains("kAXSecureTextFieldSubrole") && ax.contains("return fail(\"password field\")"))
    }

    func testUpdatesRequireTheReleaseSignature() throws {
        XCTAssertEqual(Updater.publicKeyBase64, "AUq3fVygMR4hxBPj8avt5+pd3BYGUCdFQVA4QhTfBIo=")
        XCTAssertTrue(try text("Sources/NexoLLM/Updater.swift").contains("guard verdict == .valid"))
        // A file signed by any other key is rejected.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("audit-\(UUID().uuidString).dmg")
        try Data("not a release".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let forger = Curve25519.Signing.PrivateKey()
        let sha = try XCTUnwrap(Updater.sha256Hex(of: file))
        let forged = try forger.signature(for: Updater.signedMessage(version: "99.0.0", sha256: sha))
        XCTAssertEqual(Updater.verify(file: file, signature: forged, version: "99.0.0", installed: "0.9.2"), .badSignature)
        // Downloads only from NexoLLM's own releases or GitHub's release CDN.
        XCTAssertTrue(Updater.isTrustedDownload(URL(string: "https://github.com/edevscomp/NexoLLM/releases/download/v1/NexoLLM-macos.dmg")!))
        XCTAssertTrue(Updater.isTrustedDownload(URL(string: "https://release-assets.githubusercontent.com/x")!))
        XCTAssertFalse(Updater.isTrustedDownload(URL(string: "https://github.com/someone-else/NexoLLM/releases/download/v1/x.dmg")!))
        XCTAssertFalse(Updater.isTrustedDownload(URL(string: "https://api.github.com/repos/edevscomp/NexoLLM")!))
    }

    func testPrivateFilesAreOwnerOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.bin")
        SecureFile.write(Data("secret".utf8), to: file)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        let supportMode = try FileManager.default.attributesOfItem(atPath: AppPaths.support.path)[.posixPermissions] as? Int
        XCTAssertEqual(supportMode, 0o700)
    }

    func testSystemTypingAidsUseTheNamesAppKitListensTo() {
        // Verified in AppKit: these distributed names make running apps re-read the flags. The similarly named
        // NSSpellCheckerDidChange… notifications are in-process only and would silently do nothing.
        XCTAssertEqual(SystemTextPrefs.Kind.inlinePrediction.keys, ["NSAutomaticInlinePredictionEnabled", "NSAutomaticTextCompletionEnabled"])
        XCTAssertEqual(SystemTextPrefs.Kind.inlinePrediction.notifications,
                       ["NSAutomaticInlinePredictionEnabledChanged", "NSAutomaticTextCompletionEnabledChanged"])
        XCTAssertEqual(SystemTextPrefs.Kind.autocorrect.keys, ["NSAutomaticSpellingCorrectionEnabled", "WebAutomaticSpellingCorrectionEnabled"])
        XCTAssertEqual(SystemTextPrefs.Kind.autocorrect.notifications, ["NSAutomaticSpellingCorrectionEnabledChanged"])
    }
}
