import Foundation
import whisper

/// whisper.cpp on this computer's GPU (Metal): speech to text without any network. One serial queue owns the
/// context; it is created when listening starts and freed when it stops.
final class WhisperEngine: @unchecked Sendable {
    struct Result { let text: String; let language: String }

    private let queue = DispatchQueue(label: "nexollm.whisper", qos: .userInitiated)
    private var ctx: OpaquePointer?
    private(set) var modelPath = ""
    private static var logSilenced = false

    /// Loads the model (on the engine's queue). Calls back on the main queue with success.
    func load(path: String, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            // Same as LLMEngine: no Metal residency keep-alive loop (idle CPU and wakeups).
            setenv("GGML_METAL_NO_RESIDENCY", "1", 0)
            if !Self.logSilenced {
                whisper_log_set({ level, text, _ in
                    guard level.rawValue == 4, let text else { return }   // GGML_LOG_LEVEL_ERROR
                    fputs(String(cString: text), stderr)
                }, nil)
                Self.logSilenced = true
            }
            if ctx != nil, modelPath == path { DispatchQueue.main.async { completion(true) }; return }
            freeLocked()
            var cp = whisper_context_default_params()
            cp.use_gpu = true
            cp.flash_attn = true
            ctx = whisper_init_from_file_with_params(path, cp)
            modelPath = ctx == nil ? "" : path
            let ok = ctx != nil
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func unload() { queue.async { [self] in freeLocked() } }

    /// Frees the model synchronously. Call before the process exits, or ggml-metal asserts.
    func shutdown() { queue.sync { freeLocked() } }

    private func freeLocked() {
        if let ctx { whisper_free(ctx) }
        ctx = nil
        modelPath = ""
    }

    /// Supported speech recognition ISO codes: English, Italian, Spanish, French, German, Portuguese.
    static let supportedLanguages = ["en", "it", "es", "fr", "de", "pt"]

    /// Transcribes 16 kHz mono samples. `language`: ISO code ("en", "it", "es", "fr", "de", "pt") or nil for automatic (limited to `allowed`).
    func transcribe(_ samples: [Float], language: String?, allowed: [String] = WhisperEngine.supportedLanguages,
                    completion: @escaping (Result?) -> Void) {
        queue.async { [self] in
            let r = transcribeLocked(samples, language: language, allowed: allowed)
            DispatchQueue.main.async { completion(r) }
        }
    }

    private func transcribeLocked(_ samples: [Float], language: String?, allowed: [String]) -> Result? {
        guard let ctx, samples.count >= 16_000 / 4 else { return nil }
        func run(_ lang: String) -> Bool {
            var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            let cores = ProcessInfo.processInfo.activeProcessorCount
            p.n_threads = Int32(max(1, min(4, cores - 2)))
            p.translate = false
            p.no_context = true
            p.no_timestamps = true
            p.single_segment = false
            p.print_special = false
            p.print_progress = false
            p.print_realtime = false
            p.print_timestamps = false
            p.suppress_blank = true
            p.suppress_nst = true
            p.temperature = 0
            p.no_speech_thold = 0.6
            return lang.withCString { cLang -> Bool in
                p.language = cLang
                p.detect_language = false
                return samples.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, p, buf.baseAddress, Int32(buf.count)) == 0
                }
            }
        }
        guard run(language ?? "auto") else { return nil }
        var detected = String(cString: whisper_lang_str(whisper_full_lang_id(ctx)))
        let segCount = whisper_full_n_segments(ctx)
        let hasSpeech = (0..<segCount).contains { whisper_full_get_segment_no_speech_prob(ctx, $0) < 0.55 }
        guard hasSpeech else { return nil }   // skip second GPU pass on silence/room noise
        // Automatic, but the speaker isn't in one of the expected languages (or detection was unsure on a very
        // short phrase): transcribe again in the most recent expected one.
        if language == nil, !allowed.contains(detected), let fallback = allowed.first {
            guard run(fallback) else { return nil }
            detected = fallback
        }
        var parts: [String] = []
        for i in 0..<whisper_full_n_segments(ctx) {
            guard whisper_full_get_segment_no_speech_prob(ctx, i) < 0.6, let c = whisper_full_get_segment_text(ctx, i) else { continue }
            parts.append(String(cString: c))
        }
        let text = Self.clean(parts.joined(separator: " "))
        return text.isEmpty ? nil : Result(text: text, language: detected)
    }

    /// Whisper's known "silence" hallucinations and non-speech tags never reach the transcript.
    static func clean(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\\[[^\\]]*\\]|\\([^)]*\\)|♪+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
        let hallucinations = [
            "thank you for watching", "thanks for watching", "grazie per la visione", "grazie a tutti per la visione",
            "sottotitoli creati dalla comunità amara.org", "sottotitoli a cura di qtss", "subtitles by the amara.org community",
            "please subscribe", "iscriviti al canale", "you", "grazie", "thank you", "...", "sottotitoli e revisione a cura di qtss",
            "gracias por ver", "gracias por ver el video", "subtítulos realizados por la comunidad de amara.org",
            "suscríbete al canal", "gracias", "merci d'avoir regardé", "merci d'avoir regarde",
            "sous-titres réalisés par la communauté d'amara.org", "abonnez-vous", "merci",
            "vielen dank fürs zuschauen", "untertitel der amara.org-community", "untertitel im auftrag des zdf",
            "danke fürs zuschauen", "obrigado por assistir", "legendas pela comunidade amara.org", "inscreva-se no canal"
        ]
        if hallucinations.contains(lower) || lower.contains("amara.org") || lower.contains("qtss") { return "" }
        guard t.contains(where: { $0.isLetter }) else { return "" }
        return t
    }
}
