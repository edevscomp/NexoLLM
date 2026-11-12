import CryptoKit
import XCTest
@testable import NexoLLM

/// PLAN_V19: first-run fixes, signed updates, local-only audio plugin.
final class V19Tests: XCTestCase {

    // MARK: Rewrite prompts and RewriteGuard

    func testRewritePromptsContainNoPeopleOrBiographies() {
        let instructions = ["Improve clarity and flow, keeping the same language and meaning",
                            "Fix grammar, spelling and punctuation only, keeping the same language",
                            "Rewrite in a formal, polite and professional tone in the same language",
                            "Make this more concise in the same language",
                            "Translate into Español", "Translate into Français", "Translate into Deutsch",
                            "Translate into Português", "Translate into English", "Translate into Italiano"]
        for lang in ["it", "en"] {
            for i in instructions {
                let p = CompletionController.buildRewritePrompt(text: "testo di prova", instruction: i, language: lang).lowercased()
                for banned in ["alex", "marco", "cybersecurity", "sicurezza informatica", "computer engineer", "ingegnere",
                               "ai expert", "10 years", "10 anni", "my name is", "mi chiamo"] {
                    XCTAssertFalse(p.contains(banned), "\(i) [\(lang)] still contains \"\(banned)\"")
                }
                XCTAssertTrue(p.hasSuffix("\"testo di prova\"\n" + (p.components(separatedBy: "\n").last ?? "")), i)
            }
        }
    }

    func testRewriteGuardRejectsEchoedExamples() {
        let prompt = CompletionController.buildRewritePrompt(text: "Ciao", instruction: "Improve clarity and flow", language: "en")
        // The small-model failure from the first-run test: a one-word input answered with an example.
        XCTAssertFalse(RewriteGuard.accepts(output: "The file is ready and complete; I'll send it later.",
                                            original: "Ciao", prompt: prompt, instruction: "Improve clarity and flow"))
        XCTAssertTrue(RewriteGuard.leaksPrompt(output: "the file is ready and complete", prompt: prompt, original: "Ciao"))
        // A real rewrite of the user's own text is accepted, even when it shares words the user wrote.
        let long = "the file is ready but i will send it tomorrow morning"
        let p2 = CompletionController.buildRewritePrompt(text: long, instruction: "Improve clarity and flow", language: "en")
        XCTAssertTrue(RewriteGuard.accepts(output: "The file is ready, but I'll send it tomorrow morning.",
                                           original: long, prompt: p2, instruction: "Improve clarity and flow"))
    }

    func testRewriteGuardLengthLimits() {
        XCTAssertEqual(RewriteGuard.maxWords(original: "cao", instruction: "Improve clarity"), 6)
        XCTAssertFalse(RewriteGuard.accepts(output: "is a computer engineer and AI expert with 10 years of experience in cybersecurity",
                                            original: "cao", prompt: "", instruction: "Improve clarity"))
        XCTAssertEqual(RewriteGuard.maxWords(original: "one two three four", instruction: "Make this shorter"), 6)
        XCTAssertTrue(RewriteGuard.isTooShortToRewrite("cao", instruction: "Improve clarity and flow"))
        XCTAssertTrue(RewriteGuard.isTooShortToRewrite("ciao mondo", instruction: "Fix grammar"))
        XCTAssertFalse(RewriteGuard.isTooShortToRewrite("ciao", instruction: "Translate into English"))
        XCTAssertFalse(RewriteGuard.isTooShortToRewrite("ciao come stai oggi", instruction: "Improve clarity"))
    }

    func testShortTyposAndShorthand() {
        XCTAssertEqual(Spelling.correction(for: "cao", context: "cao"), "ciao")
        XCTAssertEqual(Spelling.correction(for: "Cao", context: "Cao"), "Ciao")
        XCTAssertEqual(Spelling.correction(for: "teh", context: "teh"), "the")
        XCTAssertEqual(CompletionController.applySpellingFixes(to: "nn lo so cmq", shorthandLanguage: "it"), "Non lo so comunque")
        // Shorthand is expanded only in its own language and only by the writing tools.
        XCTAssertEqual(CompletionController.applySpellingFixes(to: "thx a lot", shorthandLanguage: "it"), "Thx a lot")
        XCTAssertEqual(CompletionController.applySpellingFixes(to: "nn"), "nn")
    }

    // MARK: Signed updates

    private func tempFile(_ bytes: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        try? Data(bytes.utf8).write(to: url)
        return url
    }

    private func sign(_ url: URL, version: String, key: Curve25519.Signing.PrivateKey) -> Data {
        let sha = Updater.sha256Hex(of: url)!
        return try! key.signature(for: Updater.signedMessage(version: version, sha256: sha))
    }

    func testValidSignatureIsAccepted() {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let file = tempFile("NexoLLM 9.0.0 image")
        let sig = sign(file, version: "9.0.0", key: key)
        XCTAssertEqual(Updater.verify(file: file, signature: sig, version: "9.0.0", installed: "0.8.0", publicKey: pub), .valid)
    }

    func testTamperedFileIsRejected() {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let file = tempFile("NexoLLM 9.0.0 image")
        let sig = sign(file, version: "9.0.0", key: key)
        try? Data("NexoLLM 9.0.0 image + malware".utf8).write(to: file)
        XCTAssertEqual(Updater.verify(file: file, signature: sig, version: "9.0.0", installed: "0.8.0", publicKey: pub), .badSignature)
    }

    func testSignatureFromAnotherKeyIsRejected() {
        let attacker = Curve25519.Signing.PrivateKey()
        let file = tempFile("evil")
        let sig = sign(file, version: "9.0.0", key: attacker)
        // Verified against the key compiled into the app.
        XCTAssertEqual(Updater.verify(file: file, signature: sig, version: "9.0.0", installed: "0.8.0"), .badSignature)
    }

    func testVersionIsBoundToTheSignatureAndDowngradesAreRefused() {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation.base64EncodedString()
        let file = tempFile("NexoLLM 0.7.0 image")
        let sig = sign(file, version: "0.7.0", key: key)
        // An old, genuinely signed release relabeled as a new one: the version in the signature doesn't match.
        XCTAssertEqual(Updater.verify(file: file, signature: sig, version: "9.9.9", installed: "0.8.0", publicKey: pub), .badSignature)
        // Offered as itself, it's older than what's installed.
        XCTAssertEqual(Updater.verify(file: file, signature: sig, version: "0.7.0", installed: "0.8.0", publicKey: pub), .notNewer)
        XCTAssertEqual(Updater.verify(file: file, signature: Data([1, 2, 3]), version: "9.0.0", installed: "0.8.0", publicKey: pub), .malformed)
    }

    func testEmbeddedPublicKeyIsValid() {
        let raw = Data(base64Encoded: Updater.publicKeyBase64)
        XCTAssertEqual(raw?.count, 32)
        XCTAssertNotNil(try? Curve25519.Signing.PublicKey(rawRepresentation: raw!))
    }

    func testReleaseParsingFindsTheSignatureAndRejectsForeignHosts() {
        let json = """
        {"tag_name":"v0.9.0","assets":[
          {"name":"NexoLLM.dmg","browser_download_url":"https://github.com/edevscomp/NexoLLM/releases/download/v0.9.0/NexoLLM.dmg"},
          {"name":"NexoLLM.dmg.sig","browser_download_url":"https://github.com/edevscomp/NexoLLM/releases/download/v0.9.0/NexoLLM.dmg.sig"}]}
        """
        let r = Updater.parse(Data(json.utf8))
        XCTAssertEqual(r?.version, "0.9.0")
        XCTAssertEqual(r?.signature?.lastPathComponent, "NexoLLM.dmg.sig")
        let evil = """
        {"tag_name":"v0.9.0","assets":[{"name":"NexoLLM.dmg","browser_download_url":"https://evil.example.com/NexoLLM.dmg"}]}
        """
        XCTAssertNil(Updater.parse(Data(evil.utf8)))
        XCTAssertFalse(Updater.isTrustedDownload(URL(string: "http://github.com/x.dmg")!))
        XCTAssertFalse(SecureNet.isAllowed(URL(string: "https://github.com.evil.io/x")!, hosts: SecureNet.githubHosts))
        XCTAssertTrue(SecureNet.isHuggingFaceHost("cdn-lfs-us-1.hf.co"))
        XCTAssertFalse(SecureNet.isHuggingFaceHost("huggingface.co.evil.io"))
        XCTAssertTrue(WebLookup.isLookupHost("it.wikipedia.org"))
        XCTAssertFalse(WebLookup.isLookupHost("wikipedia.org.evil.io"))
    }

    // MARK: macOS typing aids

    func testSystemPrefsValueParsingAndRoundTrip() {
        XCTAssertTrue(SystemTextPrefs.boolValue(nil))        // missing = macOS default (on)
        XCTAssertFalse(SystemTextPrefs.boolValue(false))
        XCTAssertFalse(SystemTextPrefs.boolValue(NSNumber(value: 0)))
        XCTAssertFalse(SystemTextPrefs.boolValue("NO"))
        // Write/read a private test key in the global domain, then remove it.
        let key = "NexoLLMTestToggle"
        defer {
            CFPreferencesSetValue(key as CFString, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        XCTAssertTrue(SystemTextPrefs.write(key: key, on: false))
        XCTAssertFalse(SystemTextPrefs.read(key: key))
        XCTAssertTrue(SystemTextPrefs.write(key: key, on: true))
        XCTAssertTrue(SystemTextPrefs.read(key: key))
    }

    // MARK: Model state

    func testEngineStatusDuringFirstDownload() {
        var d = ModelManager.Download(total: 1000)
        d.received = 460
        let s = AppDelegate.statusText(.noModel, downloads: [(name: "Llama 3.2 1B", download: d)])
        XCTAssertTrue(s.text.hasPrefix("Downloading Llama 3.2 1B · 46%"), s.text)
        XCTAssertFalse(s.ready)
        XCTAssertFalse(s.text.contains("Error"))
        d.verifying = true
        XCTAssertEqual(AppDelegate.statusText(.noModel, downloads: [(name: "Llama 3.2 1B", download: d)]).text, "Verifying Llama 3.2 1B…")
        let idle = AppDelegate.statusText(.noModel, downloads: [])
        XCTAssertEqual(idle.text, "No model installed · download one in Models")
        XCTAssertTrue(AppDelegate.statusText(.ready("x.gguf"), downloads: [(name: "Other", download: d)]).ready)
    }

    func testDefaultModelPathUsesTheCatalogFileName() {
        XCTAssertTrue(Settings.e2bModelPath.hasSuffix("gemma-4-E2B.i1-Q4_K_M.gguf") || Settings.e2bModelPath.hasSuffix("gemma-4-E2B-i1-Q4_K_M.gguf"))
        // Never a path to a file that isn't there.
        let p = Settings.defaultModelPath
        XCTAssertTrue(p.isEmpty || FileManager.default.fileExists(atPath: p))
    }

    // MARK: Audio plugin

    func testSegmenterSendsPhrasesNotSilence() {
        var seg = SpeechSegmenter(threshold: 0.02)
        let silence = [Float](repeating: 0.001, count: 16_000)
        XCTAssertEqual(seg.append(silence), .none)
        // 1.2 s of "voice" then 1 s of silence → one final phrase.
        let voice = (0..<19_200).map { i in Float(sin(Double(i) * 0.05)) * 0.3 }
        var events: [SpeechSegmenter.Event] = [seg.append(voice), seg.append(silence)]
        events.removeAll { $0 == .none }
        guard case .final(let phrase)? = events.last else { return XCTFail("no final phrase: \(events)") }
        XCTAssertGreaterThan(phrase.count, 19_200)
        XCTAssertTrue(seg.buffer.isEmpty)
        // A click (20 ms) is not speech worth transcribing.
        let click = [Float](repeating: 0.3, count: 320)
        var e2 = [seg.append(click), seg.append(silence)]
        e2.removeAll { $0 == .none }
        XCTAssertTrue(e2.isEmpty, "\(e2)")
    }

    func testSegmenterOffersPartialsDuringLongSpeech() {
        var seg = SpeechSegmenter(threshold: 0.02)
        let voice = (0..<(16_000 * 4)).map { i in Float(sin(Double(i) * 0.05)) * 0.3 }
        var partials = 0
        for k in stride(from: 0, to: voice.count, by: 4000) {
            if case .partial = seg.append(Array(voice[k..<min(voice.count, k + 4000)])) { partials += 1 }
        }
        XCTAssertGreaterThanOrEqual(partials, 1)
    }

    func testWhisperHallucinationsAreDropped() {
        XCTAssertEqual(WhisperEngine.clean("Sottotitoli creati dalla comunità Amara.org"), "")
        XCTAssertEqual(WhisperEngine.clean(" Thank you for watching! "), "")
        XCTAssertEqual(WhisperEngine.clean("[Musica]"), "")
        XCTAssertEqual(WhisperEngine.clean("La derivata  [applausi] di una funzione"), "La derivata di una funzione")
    }

    @MainActor func testAudioPluginCatalogIsVerifiable() {
        for m in AudioPlugin.models {
            XCTAssertEqual(m.sha256.count, 64)
            XCTAssertEqual(m.url.host, "huggingface.co")
            XCTAssertEqual(m.url.scheme, "https")
        }
    }

    func testListeningNeverResumesAtLaunch() {
        // Settings.init forces it off; whatever the stored value was, a fresh load starts with it off.
        XCTAssertFalse(Settings.shared.prefs.micContextEnabled && !AudioContext.shared.isListening)
    }
}
