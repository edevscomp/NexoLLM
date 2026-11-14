import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

// MARK: - Audio Context plugin (experimental, optional, on-device)
//
// Speech-to-text for room audio (a lecture, a meeting) and call audio (Zoom, Meet, browser video), used as
// context for suggestions. Everything runs on this computer: whisper.cpp on the GPU, no speech service, no
// network. The speech model is not part of the app: it is downloaded only after the user reads the legal
// notice and agrees to it, and can be removed at any time. Audio is never written to disk; the transcript
// lives in memory only and is cleared when listening stops.

private final class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private let onSample: (CMSampleBuffer) -> Void
    init(onSample: @escaping (CMSampleBuffer) -> Void) { self.onSample = onSample }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, CMSampleBufferIsValid(sampleBuffer) else { return }
        onSample(sampleBuffer)
    }
}

/// Automatic gain control for a far-field microphone: brings quiet, distant voices (a teacher across the room,
/// someone at the other end of the table) up to a level speech recognition understands, without boosting
/// background hiss during silence and without hard clipping on loud, close speech.
/// Before the gain, a ~120 Hz high-pass removes the low room boom that masks speech in small echoey rooms,
/// and a light pre-emphasis lifts the consonants that make distant speech intelligible.
final class AmbientGain: @unchecked Sendable {
    /// RMS the recognizer likes (≈ −14 dBFS).
    static let targetRMS: Float = 0.20
    /// Below this the input is treated as room noise: gain is held, never raised (≈ −72 dBFS).
    static let noiseFloor: Float = 0.00025
    static let maxGain: Float = 45      // +33 dB
    static let minGain: Float = 1
    static let highPassHz: Double = 120
    static let preEmphasis: Float = 0.55
    private(set) var gain: Float = 10
    private var hpPrevIn: [Float] = []
    private var hpPrevOut: [Float] = []
    private var emphPrev: [Float] = []

    /// Next gain from the measured block RMS: rises quickly on a voice, falls slowly in pauses and echo tails,
    /// but drops fast when the boosted signal would clip (loud, close speech).
    static func nextGain(current: Float, rms: Float) -> Float {
        guard rms > noiseFloor else { return current }
        let desired = min(maxGain, max(minGain, targetRMS / rms))
        let rate: Float
        if desired > current { rate = 0.22 }
        else { rate = rms * current > 0.6 ? 0.5 : 0.08 }
        return current + (desired - current) * rate
    }

    /// Perceived level (0…1, dB scale) of a signal with RMS `rms`: −48 dBFS → 0, −6 dBFS → 1.
    static func meterLevel(rms: Float) -> Float {
        let db = 20 * log10(max(rms, 0.000_01))
        return min(1, max(0, (db + 48) / 42))
    }

    func process(_ buffer: AVAudioPCMBuffer) -> (buffer: AVAudioPCMBuffer, rms: Float) {
        guard let src = buffer.floatChannelData,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity),
              let dst = copy.floatChannelData else { return (buffer, 0) }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        copy.frameLength = buffer.frameLength
        if hpPrevIn.count != channels {
            hpPrevIn = Array(repeating: 0, count: channels)
            hpPrevOut = Array(repeating: 0, count: channels)
            emphPrev = Array(repeating: 0, count: channels)
        }
        let sr = buffer.format.sampleRate > 0 ? buffer.format.sampleRate : 48_000
        let rc = 1 / (2 * Double.pi * Self.highPassHz)
        let alpha = Float(rc / (rc + 1 / sr))
        // 1. High-pass + pre-emphasis into `dst` (still unamplified).
        for ch in 0..<channels {
            var pIn = hpPrevIn[ch], pOut = hpPrevOut[ch], pE = emphPrev[ch]
            for i in 0..<frames {
                let x = src[ch][i]
                let hp = alpha * (pOut + x - pIn)
                pIn = x; pOut = hp
                dst[ch][i] = hp - Self.preEmphasis * pE
                pE = hp
            }
            hpPrevIn[ch] = pIn; hpPrevOut[ch] = pOut; emphPrev[ch] = pE
        }
        // 2. Level of the cleaned signal drives the gain.
        var sum: Float = 0
        for i in 0..<frames { let v = dst[0][i]; sum += v * v }
        let rms = frames > 0 ? sqrt(sum / Float(frames)) : 0
        gain = Self.nextGain(current: gain, rms: rms)
        // 3. Gain with a soft limiter: only peaks are shaped.
        for ch in 0..<channels {
            for i in 0..<frames { dst[ch][i] = tanhf(dst[ch][i] * gain) }
        }
        return (copy, Self.meterLevel(rms: min(1, rms * gain)))
    }
}

/// Cuts a continuous 16 kHz stream into utterances for Whisper: a phrase is sent when the speaker pauses
/// (`final`), long monologues are cut every `maxSeconds`, and while someone keeps talking a `partial` of the
/// phrase so far is offered every `partialEvery` seconds so words appear without waiting for the pause.
/// Silence is never sent (Whisper invents text on silence).
struct SpeechSegmenter {
    enum Event: Equatable { case none, partial([Float]), final([Float]) }

    static let rate = 16_000
    var threshold: Float
    var pauseSeconds = 0.7
    var maxSeconds = 12.0
    var partialEvery = 2.5
    var minSpeechSeconds = 0.3

    private(set) var buffer: [Float] = []
    private var speechSamples = 0
    private var silenceRun = 0
    private var sinceEmit = 0
    private var preRoll: [Float] = []
    /// Running estimate of the background level: a voice must stand clearly above it, so a steady hum
    /// (fans, projector, room noise lifted by the gain control) never counts as speech.
    private(set) var noiseLevel: Float

    init(threshold: Float) { self.threshold = threshold; noiseLevel = threshold / 3 }

    /// Feeds new samples; returns what should be transcribed now, if anything.
    mutating func append(_ samples: [Float]) -> Event {
        let frame = Self.rate / 50   // 20 ms
        var i = 0
        var event = Event.none
        while i < samples.count {
            let chunk = Array(samples[i..<min(samples.count, i + frame)])
            i += frame
            var sum: Float = 0
            for v in chunk { sum += v * v }
            let rms = sqrt(sum / Float(max(1, chunk.count)))
            noiseLevel = rms < noiseLevel ? noiseLevel * 0.9 + rms * 0.1 : noiseLevel * 0.998 + rms * 0.002
            let speech = rms > max(threshold, noiseLevel * 3)
            if buffer.isEmpty {
                if speech {
                    buffer = preRoll + chunk
                    speechSamples = chunk.count; silenceRun = 0; sinceEmit = buffer.count
                } else {
                    let cap = Self.rate * 3 / 10   // 0.3 s before the first word
                    preRoll.append(contentsOf: chunk)
                    if preRoll.count > cap { preRoll.removeFirst(preRoll.count - cap) }
                }
                continue
            }
            buffer += chunk
            sinceEmit += chunk.count
            if speech { speechSamples += chunk.count; silenceRun = 0 } else { silenceRun += chunk.count }
            let paused = Double(silenceRun) >= pauseSeconds * Double(Self.rate)
            let tooLong = Double(buffer.count) >= maxSeconds * Double(Self.rate)
            if paused || tooLong {
                let enough = Double(speechSamples) >= minSpeechSeconds * Double(Self.rate)
                let out = buffer
                reset()
                if enough { event = .final(out) }
            } else if Double(sinceEmit) >= partialEvery * Double(Self.rate) {
                sinceEmit = 0
                if case .final = event {} else { event = .partial(buffer) }
            }
        }
        return event
    }

    /// Overwrites the audio held in memory with zeros, then drops it.
    mutating func reset() {
        for k in buffer.indices { buffer[k] = 0 }
        for k in preRoll.indices { preRoll[k] = 0 }
        buffer = []; preRoll = []
        speechSamples = 0; silenceRun = 0; sinceEmit = 0
    }
}

/// The downloadable part of the plugin: the speech model, the user's consent, install and removal.
@MainActor
final class AudioPlugin: NSObject, ObservableObject {
    static let shared = AudioPlugin()

    struct Model: Identifiable, Hashable {
        let id: String       // file name
        let name: String
        let bytes: Int64
        let sha256: String
        var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(id)")! }
        /// In the app language (computed, so it follows a language change).
        var detail: String {
            id.contains("turbo")
                ? L("Best accuracy: distant voices, echoey rooms, 6 languages", "Massima precisione: voci lontane, stanze con eco, 6 lingue")
                : L("Lighter and faster, for computers with 8 GB of memory", "Più leggero e veloce, per computer con 8 GB di memoria")
        }
    }

    static let turbo = Model(id: "ggml-large-v3-turbo-q5_0.bin", name: "Whisper Large v3 Turbo",
                             bytes: 574_041_195, sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2")
    static let small = Model(id: "ggml-small-q5_1.bin", name: "Whisper Small",
                             bytes: 190_085_487, sha256: "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb")
    static let models = [turbo, small]

    /// Bumped when the notice changes in substance: everyone is asked to read and agree again.
    static let consentVersion = 2
    private static let consentKey = "audioPlugin.consentVersion"

    static var folder: URL { AppPaths.support.appendingPathComponent("Plugins/AudioContext", isDirectory: true) }

    @Published private(set) var installed: Model?
    @Published private(set) var progress: Double?
    @Published private(set) var verifying = false
    @Published var error: String?

    private var task: URLSessionDownloadTask?
    private var pending: Model?
    private lazy var session = URLSession(configuration: SecureNet.configuration(timeout: 60), delegate: self, delegateQueue: .main)

    override private init() {
        super.init()
        refresh()
    }

    var hasConsent: Bool { UserDefaults.standard.integer(forKey: Self.consentKey) >= Self.consentVersion }
    var isReady: Bool { installed != nil && hasConsent }
    var modelPath: String? { installed.map { Self.folder.appendingPathComponent($0.id).path } }

    func refresh() {
        let fm = FileManager.default
        installed = Self.models.first { fm.fileExists(atPath: Self.folder.appendingPathComponent($0.id).path) }
    }

    func recordConsent() {
        UserDefaults.standard.set(Self.consentVersion, forKey: Self.consentKey)
        UserDefaults.standard.set(Date(), forKey: "audioPlugin.consentDate")
        Log.info("audio plugin: legal notice accepted (v\(Self.consentVersion))")
    }

    func install(_ m: Model) {
        guard task == nil, hasConsent else { return }
        let free = (try? AppPaths.support.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? Int64.max
        guard free > m.bytes + 500_000_000 else {
            error = L("Not enough disk space: \(m.name) needs \(Fmt.bytes(m.bytes)) plus 500 MB free.",
                      "Spazio insufficiente: \(m.name) richiede \(Fmt.bytes(m.bytes)) più 500 MB liberi.")
            return
        }
        error = nil
        pending = m
        progress = 0
        let t = session.downloadTask(with: m.url)
        task = t
        t.resume()
        Log.info("audio plugin: downloading \(m.id)")
    }

    func cancel() { task?.cancel(); task = nil; pending = nil; progress = nil }

    /// Removes the speech model and the consent: the feature is back to "not installed".
    func uninstall() {
        Settings.shared.prefs.micContextEnabled = false
        cancel()
        try? FileManager.default.removeItem(at: Self.folder)
        UserDefaults.standard.removeObject(forKey: Self.consentKey)
        UserDefaults.standard.removeObject(forKey: "audioPlugin.consentDate")
        refresh()
        Log.info("audio plugin: removed")
    }

    fileprivate func finished(file: URL) {
        guard let m = pending else { try? FileManager.default.removeItem(at: file); return }
        verifying = true
        Task.detached(priority: .utility) {
            let ok = SecureFile.sha256(of: file) == m.sha256
            await MainActor.run {
                let me = AudioPlugin.shared
                me.verifying = false; me.progress = nil; me.task = nil; me.pending = nil
                guard ok else {
                    try? FileManager.default.removeItem(at: file)
                    me.error = L("The download didn't match its checksum and was deleted. Try again.",
                                 "Il download non corrisponde al checksum ed è stato eliminato. Riprova.")
                    return
                }
                let fm = FileManager.default
                try? fm.createDirectory(at: AudioPlugin.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                // One model at a time.
                for other in AudioPlugin.models { try? fm.removeItem(at: AudioPlugin.folder.appendingPathComponent(other.id)) }
                let target = AudioPlugin.folder.appendingPathComponent(m.id)
                do { try fm.moveItem(at: file, to: target) } catch {
                    me.error = error.localizedDescription; return
                }
                SecureFile.restrict(target)
                me.refresh()
                Log.info("audio plugin: installed \(m.id)")
            }
        }
    }
}

extension AudioPlugin: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                                newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              SecureNet.isHuggingFaceHost(host) else { completionHandler(nil); return }
        completionHandler(request)
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        MainActor.assumeIsolated {
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (pending?.bytes ?? 1)
            let p = min(1, Double(totalBytesWritten) / Double(total))
            if progress == nil || abs(p - (progress ?? 0)) >= 0.01 || p >= 1 { progress = p }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let keep = AppPaths.support.appendingPathComponent(UUID().uuidString + ".part")
        let moved = (try? FileManager.default.moveItem(at: location, to: keep)) != nil
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        MainActor.assumeIsolated {
            guard moved, status == 200 else {
                try? FileManager.default.removeItem(at: keep)
                task = nil; pending = nil; progress = nil
                error = L("Download failed (HTTP \(status)).", "Download non riuscito (HTTP \(status)).")
                return
            }
            finished(file: keep)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        MainActor.assumeIsolated {
            self.task = nil; pending = nil; progress = nil
            self.error = L("Download stopped: ", "Download interrotto: ") + error.localizedDescription
        }
    }
}

/// Thread-safe 16 kHz sample queue between an audio thread and the main thread.
private final class SampleQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    func push(_ s: [Float]) { lock.lock(); samples += s; if samples.count > 16_000 * 30 { samples.removeFirst(samples.count - 16_000 * 30) }; lock.unlock() }
    func drain() -> [Float] { lock.lock(); defer { lock.unlock() }; let s = samples; samples = []; return s }
    func wipe() { lock.lock(); for i in samples.indices { samples[i] = 0 }; samples = []; lock.unlock() }
}

/// Live transcription of the room microphone (with `AmbientGain`) and of call/system audio, on this computer.
final class AudioContext: ObservableObject {
    static let shared = AudioContext()
    @Published private(set) var isListening = false
    @Published private(set) var statusText = ""
    @Published private(set) var transcript = ""
    @Published private(set) var inputLevel: Float = 0
    @Published private(set) var packetCount: Int = 0
    /// "Auto · it" / "en" for the badge.
    @Published private(set) var recognizerLocale: String = ""
    @Published private(set) var lastHeardAt: Date? = nil
    @Published private(set) var lastError: String? = nil
    @Published private(set) var capturesSystemAudio: Bool = false
    /// Language chosen by the user ("it-IT" / "en-US"), or nil for automatic (Italian ⇄ English).
    @Published var overrideLocale: String? = nil {
        didSet { if oldValue != overrideLocale { updateLocaleBadge() } }
    }

    /// Every interested party (prompt builder, menu bar icon) gets notified; nobody overwrites anybody.
    private var listeners: [() -> Void] = []
    func addListener(_ f: @escaping () -> Void) { listeners.append(f) }
    private func notify() { listeners.forEach { $0() } }

    private let whisper = WhisperEngine()
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let micQueue = SampleQueue()
    private let sysQueueSamples = SampleQueue()
    private var micSeg = SpeechSegmenter(threshold: 0.02)
    private var sysSeg = SpeechSegmenter(threshold: 0.008)
    private var sysStream: SCStream?
    private var sysOutput: SystemAudioStreamOutput?
    private let sysQueue = DispatchQueue(label: "nexollm.audio.system", qos: .userInitiated)
    private var session = 0
    private var committed = ""
    private var micPartial = ""
    private var sysPartial = ""
    private var pumpTimer: Timer?
    private var busy = false
    private var finals: [(samples: [Float], call: Bool)] = []
    /// Language Whisper heard last (automatic mode keeps transcribing in it when a phrase is ambiguous).
    private var lastLanguage = "it"
    private let gainControl = AmbientGain()
    private var lastUserActivity = Date()

    static let maxTranscript = 700
    /// Listening stops by itself after 10 idle minutes without any typing (frees ~750 MB of Whisper GPU memory).
    static let idleStop: TimeInterval = 10 * 60

    private var wanted: Bool { Settings.shared.prefs.micContextEnabled }

    /// Stops listening and frees the speech model synchronously (app quitting).
    func shutdown() {
        stop()
        whisper.shutdown()
    }

    /// The user typed something (throttled by the caller): resets the idle auto-stop.
    func noteUserActivity() { lastUserActivity = Date() }

    func setEnabled(_ on: Bool) {
        guard on else {
            stop()
            statusText = ""
            return
        }
        guard !isListening else { return }
        let ready = MainActor.assumeIsolated { AudioPlugin.shared.isReady }
        guard ready else {
            Settings.shared.prefs.micContextEnabled = false
            statusText = L("Install the Audio Context plugin first (Settings › Awareness).",
                           "Installa prima il plugin Contesto audio (Impostazioni › Contesto).")
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { micOK in
            DispatchQueue.main.async {
                guard self.wanted else { return }
                guard micOK else {
                    self.statusText = L("Allow the Microphone for NexoLLM in System Settings › Privacy & Security",
                                        "Consenti il Microfono a NexoLLM in Impostazioni di Sistema › Privacy e sicurezza")
                    Settings.shared.prefs.micContextEnabled = false
                    return
                }
                self.begin()
            }
        }
    }

    func restartSession() {
        guard wanted else { return }
        begin()
    }

    /// Drops the transcript (and any audio still waiting to be transcribed).
    func clear() {
        committed = ""
        micPartial = ""
        sysPartial = ""
        transcript = ""
        lastHeardAt = nil
        lastError = nil
        notify()
    }

    /// Committed text + the two live partials, newest last, bounded.
    static func combine(committed: String, sys: String, mic: String, limit: Int = maxTranscript) -> String {
        let joined = [committed, sys, mic]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard joined.count > limit else { return joined }
        // Cut at a word boundary so the prompt never starts with half a word.
        let tail = joined.suffix(limit)
        if let space = tail.firstIndex(of: " ") { return String(tail[tail.index(after: space)...]) }
        return String(tail)
    }

    /// Selectable speech languages in Context and the Quick Menu (same 6 languages as the interface).
    static let speechLocales: [(locale: String, iso: String, flag: String, label: String)] =
        ExampleLanguage.allCases.map { ($0.localeIdentifier.replacingOccurrences(of: "_", with: "-"), $0.iso, $0.flag, $0.label) }

    /// Default language for automatic mode before anything was heard, across all 6 supported languages.
    static func preferredAutoLanguage(appLanguage: ExampleLanguage = Settings.shared.prefs.exampleLanguage,
                                      preferred: [String] = Locale.preferredLanguages,
                                      region: String? = Locale.current.region?.identifier) -> String {
        if appLanguage != .english { return appLanguage.iso }
        for p in preferred {
            let prefix = String(p.prefix(2)).lowercased()
            if WhisperEngine.supportedLanguages.contains(prefix) && prefix != "en" { return prefix }
        }
        let regionMap = ["IT": "it", "ES": "es", "MX": "es", "AR": "es", "FR": "fr", "DE": "de", "AT": "de", "CH": "de", "PT": "pt", "BR": "pt"]
        if let r = region, let iso = regionMap[r] { return iso }
        return "en"
    }

    /// Ordered candidate languages for Whisper automatic mode, putting the most recent heard language first.
    static func allowedLanguages(startingWith primary: String) -> [String] {
        let p = String(primary.prefix(2)).lowercased()
        let head = WhisperEngine.supportedLanguages.contains(p) ? p : "en"
        return [head] + WhisperEngine.supportedLanguages.filter { $0 != head }
    }

    /// "IT" / "EN" / "ES" / "FR" / "DE" / "PT" for badges.
    var activeLanguageShort: String {
        (overrideLocale.map { String($0.prefix(2)) } ?? lastLanguage).uppercased()
    }

    private func updateLocaleBadge() {
        if let loc = overrideLocale {
            recognizerLocale = Self.speechLocales.first { $0.locale == loc || $0.iso == String(loc.prefix(2)).lowercased() }?.label ?? loc
        } else {
            recognizerLocale = "Auto · \(lastLanguage.uppercased())"
        }
    }

    private func updateTranscript() {
        let t = Self.combine(committed: committed, sys: sysPartial, mic: micPartial)
        guard t != transcript else { return }
        transcript = t
        lastHeardAt = Date()
        notify()
    }

    private func commit(_ text: String) {
        let p = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        committed = String((committed.isEmpty ? p : committed + " " + p).suffix(Self.maxTranscript * 2))
    }

    private func begin() {
        stop()
        guard let path = MainActor.assumeIsolated({ AudioPlugin.shared.modelPath }) else { return }
        session += 1
        let mySession = session
        lastLanguage = Self.preferredAutoLanguage()
        updateLocaleBadge()
        lastUserActivity = Date()
        statusText = L("Loading the speech model…", "Caricamento del modello vocale…")
        whisper.load(path: path) { [weak self] ok in
            guard let self, mySession == self.session, self.wanted else { return }
            guard ok else {
                self.statusText = L("The speech model couldn't be loaded. Remove and reinstall the plugin.",
                                    "Impossibile caricare il modello vocale. Rimuovi e reinstalla il plugin.")
                Settings.shared.prefs.micContextEnabled = false
                return
            }
            self.startMicrophone()
        }
    }

    private func startMicrophone() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: format, to: target) else {
            statusText = L("No microphone found", "Nessun microfono trovato")
            Settings.shared.prefs.micContextEnabled = false
            return
        }
        converter = conv
        let queue = micQueue, agc = gainControl
        var lastMicMeter: TimeInterval = 0
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            let (boosted, level) = agc.process(buffer)
            if let s = Self.resample(boosted, with: conv, to: target) { queue.push(s) }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastMicMeter >= 0.08 {
                lastMicMeter = now
                self?.publishLevel(level)
            }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            statusText = error.localizedDescription
            lastError = error.localizedDescription
            Settings.shared.prefs.micContextEnabled = false
            return
        }
        audioEngine = engine
        isListening = true
        startSystemAudioCapture()
        statusText = L("Listening (transcribed on this computer)…", "In ascolto (trascritto su questo computer)…")
        pumpTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.pump() }
        notify()
    }

    /// 16 kHz mono floats from any input format.
    private static func resample(_ buffer: AVAudioPCMBuffer, with conv: AVAudioConverter, to target: AVAudioFormat) -> [Float]? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        guard err == nil, let ch = out.floatChannelData, out.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// Moves new audio through the segmenters and keeps Whisper busy: finished phrases first, then a live
    /// partial of the phrase in progress when there's time.
    private func pump() {
        guard isListening else { return }
        if Date().timeIntervalSince(lastUserActivity) > Self.idleStop {
            Log.info("audio: stopped after \(Int(Self.idleStop / 60)) minutes without typing")
            Settings.shared.prefs.micContextEnabled = false
            return
        }
        var partial: (samples: [Float], call: Bool)?
        switch micSeg.append(micQueue.drain()) {
        case .final(let s): finals.append((s, false))
        case .partial(let s): partial = (s, false)
        case .none: break
        }
        switch sysSeg.append(sysQueueSamples.drain()) {
        case .final(let s): finals.append((s, true))
        case .partial(let s): if partial == nil { partial = (s, true) }
        case .none: break
        }
        guard !busy else { return }
        if !finals.isEmpty {
            let job = finals.removeFirst()
            transcribe(job.samples, call: job.call, final: true)
        } else if let p = partial {
            transcribe(p.samples, call: p.call, final: false)
        }
    }

    private func transcribe(_ samples: [Float], call: Bool, final: Bool) {
        busy = true
        let mySession = session
        let forced = overrideLocale.map { String($0.prefix(2)).lowercased() }
        let allowed = Self.allowedLanguages(startingWith: lastLanguage)
        whisper.transcribe(samples, language: forced, allowed: allowed) { [weak self] result in
            guard let self, mySession == self.session else { return }
            self.busy = false
            if let result {
                if forced == nil, result.language != self.lastLanguage {
                    Log.info("audio: language → \(result.language)")
                    self.lastLanguage = result.language
                }
                self.updateLocaleBadge()
                if final {
                    if call { self.sysPartial = "" } else { self.micPartial = "" }
                    self.commit(result.text)
                } else if call { self.sysPartial = result.text } else { self.micPartial = result.text }
                self.updateTranscript()
            } else if final {
                if call { self.sysPartial = "" } else { self.micPartial = "" }
                self.updateTranscript()
            }
        }
    }

    fileprivate func publishLevel(_ level: Float) {
        DispatchQueue.main.async {
            guard NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            self.packetCount += 1
            self.inputLevel = max(self.inputLevel * 0.45, level)
        }
    }

    /// System / online call audio (Zoom, Meet, Teams, browser video) when Screen Recording is granted.
    private func startSystemAudioCapture() {
        guard CGPreflightScreenCaptureAccess() else { capturesSystemAudio = false; return }
        let mySession = session
        let queue = sysQueueSamples
        Task.detached(priority: .utility) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true),
                  let display = content.displays.first else { return }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let filter = SCContentFilter(display: display,
                                         excludingApplications: content.applications.filter { $0.processID == ownPID },
                                         exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 16000
            cfg.channelCount = 1
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            await MainActor.run {
                let me = AudioContext.shared   // singleton: no capture of `self` across the detached task
                guard mySession == me.session, me.isListening else { return }
                var lastSysMeter: TimeInterval = 0
                let output = SystemAudioStreamOutput { sample in
                    let (s, lvl) = AudioContext.floatsAndLevel(sample)
                    if !s.isEmpty { queue.push(s) }
                    let now = ProcessInfo.processInfo.systemUptime
                    if lvl > 0.04, now - lastSysMeter >= 0.08 {
                        lastSysMeter = now
                        AudioContext.shared.publishLevel(lvl)
                    }
                }
                let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
                do {
                    try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: me.sysQueue)
                    me.sysOutput = output
                    me.sysStream = stream
                    stream.startCapture { err in
                        DispatchQueue.main.async {
                            let me = AudioContext.shared
                            guard mySession == me.session else { return }
                            me.capturesSystemAudio = err == nil
                            if err != nil { me.sysStream = nil }
                        }
                    }
                } catch {
                    me.capturesSystemAudio = false
                }
            }
        }
    }

    /// Extracts 16 kHz mono float samples and perceived dB meter level in a single pass.
    static func floatsAndLevel(_ sampleBuffer: CMSampleBuffer) -> ([Float], Float) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return ([], 0) }
        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let ptr = dataPointer, length >= 4 else { return ([], 0) }
        let count = length / MemoryLayout<Float>.size
        return ptr.withMemoryRebound(to: Float.self, capacity: count) { raw in
            var out = [Float](repeating: 0, count: count)
            var sum: Float = 0
            let step = max(1, count / 64)
            var sampled = 0
            for i in 0..<count {
                let v = raw[i].isFinite ? raw[i] : 0
                out[i] = v
                if i % step == 0 { sum += v * v; sampled += 1 }
            }
            guard sampled > 0 else { return (out, 0) }
            let db = 20 * log10(max(sqrt(sum / Float(sampled)), 0.000_01))
            return (out, min(1, max(0, (db + 52) / 40)))
        }
    }

    static func floats(_ sampleBuffer: CMSampleBuffer) -> [Float] { floatsAndLevel(sampleBuffer).0 }

    /// Stops everything, overwrites the audio still in memory with zeros, frees the speech model and drops
    /// the transcript: nothing heard survives a stop.
    private func stop() {
        session += 1
        pumpTimer?.invalidate(); pumpTimer = nil
        sysStream?.stopCapture { _ in }
        sysStream = nil
        sysOutput = nil
        capturesSystemAudio = false
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        converter = nil
        micQueue.wipe(); sysQueueSamples.wipe()
        micSeg.reset(); sysSeg.reset()
        for i in finals.indices { for k in finals[i].samples.indices { finals[i].samples[k] = 0 } }
        finals = []
        busy = false
        whisper.unload()
        inputLevel = 0
        let hadText = !transcript.isEmpty
        committed = ""; micPartial = ""; sysPartial = ""; transcript = ""; lastHeardAt = nil
        if isListening || hadText { isListening = false; notify() }
    }
}
