import Accelerate
import Foundation
import llama

/// Monotonic request counter. Bumping it cancels any in-flight generation.
final class Generation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    @discardableResult func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    var current: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Local llama.cpp engine (Metal). All llama calls run on one serial queue.
/// Keeps the KV cache between requests so only the newly typed tokens are evaluated.
final class LLMEngine: @unchecked Sendable {
    /// `unloaded`: model freed to save memory; reloads on demand. `noModel`: nothing installed or chosen yet
    /// (a fresh install before the first download) — a normal state, not an error.
    enum State: Equatable { case idle, loading, noModel, ready(String), unloaded(String), failed(String) }

    /// Cancels normal requests (bumped on every keystroke).
    let generation = Generation()
    /// Cancels speculative look-ahead requests independently, so accepting a word doesn't kill them.
    let specGeneration = Generation()
    /// Cancels explicit user tasks (writing tools, web lookup summaries) only. Typing, focus or app switches
    /// bump `generation`, never this: closing the lookup bar must not kill the answer being written.
    let taskGeneration = Generation()
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle {
        didSet { let s = state; DispatchQueue.main.async { self.onStateChange?(s) } }
    }
    /// Path of the model currently loaded (or last loaded before being unloaded).
    private(set) var modelPath = ""

    private let queue = DispatchQueue(label: "nexollm.llm", qos: .userInitiated)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var nVocab = 0
    private var cached: [llama_token] = []
    /// Prompts are ≤ ~1000 tokens (1500 chars of text + context header), so 2048 is plenty
    /// and keeps the KV cache a third smaller than 3072.
    private let nCtx = 2048
    /// Smaller micro-batch = smaller Metal compute buffer. Prompts are mostly reused from the KV cache.
    private let nBatch = 256
    /// Context parameters of the loaded model, kept to recreate the context after an idle release.
    private var contextParams = llama_context_default_params()
    /// Which counter cancels the job currently running on `queue`.
    private var activeGen: Generation?
    private static var backendReady = false

    /// Per-token flags computed once per model, so sampling never re-decodes token text.
    private struct Flag {
        static let wordStart: UInt8 = 1    // " word": leading space + a visible character, no newline
        static let badStart: UInt8 = 2     // empty, control/unused, or contains a line break
        static let content: UInt8 = 4      // ≥ 3 letters, no punctuation (gets the repetition penalty)
        static let eog: UInt8 = 8
        static let digit: UInt8 = 16       // digits (and spaces) only: facts like dates may repeat freely
    }
    private var flags: [UInt8] = []
    /// Text of every token, flattened (`pieceOffsets[i]..<pieceOffsets[i+1]` in `pieceData`), for token healing.
    private var pieceData: [UInt8] = []
    private var pieceOffsets: [Int32] = []
    /// Scratch buffer for the softmax of the top token (allocated once per model).
    private var probs: [Float] = []
    /// Token length of the last context header (memoized: the header is stable while typing in a field).
    private var headerMemo: (text: String, tokens: Int) = ("", 0)
    /// Penalties only look at tokens from here on: the draft. The context header (screen, other fields,
    /// clipboard…) holds facts the model *should* copy — never penalize repeating them.
    private var penaltyFrom = 0
    /// A word whose first token has a probability below this is not suggested (the suggestion ends
    /// before it): a wrong guess is worse than a shorter suggestion.
    private let uncertainWord: Float = 0.06

    // MARK: Loading

    func load(path: String, completion: (() -> Void)? = nil) {
        state = .loading
        modelPath = path
        queue.async { [self] in
            defer { if let completion { DispatchQueue.main.async(execute: completion) } }
            unloadLocked()
            if !Self.backendReady {
                // Disable ggml-metal's 200 Hz residency-set keep-alive loop (~1% idle CPU + ~100 wakeups/s).
                setenv("GGML_METAL_NO_RESIDENCY", "1", 0)
                llama_log_set({ level, text, _ in
                    guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
                    fputs(String(cString: text), stderr)
                }, nil)
                llama_backend_init()
                Self.backendReady = true
            }
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                if !path.isEmpty { Log.info("engine: model file missing: \((path as NSString).lastPathComponent)") }
                state = .noModel; return
            }
            var mp = llama_model_default_params()
            mp.n_gpu_layers = 999
            // Default load mode memory-maps the weights: fast reloads straight from the page cache.
            guard let m = llama_model_load_from_file(path, mp) else {
                state = .failed("Could not load model (unsupported or corrupted GGUF)"); return
            }
            var cp = llama_context_default_params()
            cp.n_ctx = UInt32(nCtx)
            cp.n_batch = UInt32(nBatch)
            cp.n_ubatch = UInt32(nBatch)
            cp.n_seq_max = 1
            cp.swa_full = true          // needed to roll the cache back to an arbitrary prefix
            cp.no_perf = true
            // The GPU does the heavy lifting: 2 CPU threads for token-by-token decoding, up to 4 for prompts.
            let cores = ProcessInfo.processInfo.activeProcessorCount
            cp.n_threads = Int32(max(1, min(2, cores - 2)))
            cp.n_threads_batch = Int32(max(1, min(4, cores - 2)))
            // Flash attention + 8-bit KV cache: half the KV memory and bandwidth (less heat).
            cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
            cp.type_k = GGML_TYPE_Q8_0
            cp.type_v = GGML_TYPE_Q8_0
            var c = llama_init_from_model(m, cp)
            if c == nil {   // fallback for models/backends without FA support
                cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
                cp.type_k = GGML_TYPE_F16
                cp.type_v = GGML_TYPE_F16
                c = llama_init_from_model(m, cp)
            }
            guard let c else {
                llama_model_free(m)
                state = .failed("Could not create inference context"); return
            }
            model = m
            ctx = c
            contextParams = cp
            vocab = llama_model_get_vocab(m)
            nVocab = Int(llama_vocab_n_tokens(vocab))
            buildFlagsLocked()
            cached = []
            // Warm up so the first real suggestion is fast.
            _ = generateLocked(prompt: "Hello", maxTokens: 1, id: nil)
            state = .ready((path as NSString).lastPathComponent)
        }
    }

    private func buildFlagsLocked() {
        guard let vocab else { return }
        var out = [UInt8](repeating: 0, count: nVocab)
        var buf = [CChar](repeating: 0, count: 128)
        var data: [UInt8] = []
        data.reserveCapacity(nVocab * 7)
        var offsets = [Int32](repeating: 0, count: nVocab + 1)
        defer { pieceData = data; pieceOffsets = offsets }
        for i in 0..<nVocab {
            defer { offsets[i + 1] = Int32(data.count) }
            let t = llama_token(i)
            if llama_vocab_is_eog(vocab, t) { out[i] = Flag.eog | Flag.badStart; continue }
            let n = Int(llama_token_to_piece(vocab, t, &buf, Int32(buf.count), 0, false))
            guard n > 0 else { out[i] = Flag.badStart; continue }
            for j in 0..<n { data.append(UInt8(bitPattern: buf[j])) }
            var f: UInt8 = 0
            var letters = 0, visible = false, newline = false, punct = false, digits = 0, other = 0
            for j in 0..<n {
                let b = UInt8(bitPattern: buf[j])
                if b == 10 || b == 13 { newline = true }
                if b > 32 { visible = true }
                if (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b >= 128 { letters += 1 }
                if b == 46 || b == 44 || b == 59 || b == 58 || b == 33 || b == 63 { punct = true }
                if b >= 48 && b <= 57 { digits += 1 } else if b != 32 { other += 1 }
            }
            if newline { f |= Flag.badStart }
            // " ." / " )" lead with a space but aren't a word: after a typed space (e.g. right after a link) they'd
            // be picked first and then rejected by `SuggestionText.clean`, leaving no suggestion at all.
            let firstVisible = (0..<n).lazy.map { UInt8(bitPattern: buf[$0]) }.first { $0 != 32 }
            let closing = firstVisible.map { [44, 46, 59, 58, 33, 63, 41].contains($0) } ?? false
            if UInt8(bitPattern: buf[0]) == 32, visible, !newline, !closing { f |= Flag.wordStart }
            if letters >= 3, !punct, !newline { f |= Flag.content }
            if digits > 0, other == 0 { f |= Flag.digit }
            out[i] = f
        }
        flags = out
    }

    /// Frees the model's memory (weights + KV cache) while keeping the path for a quick reload.
    func unload() {
        guard case .ready(let name) = state else { return }
        generation.next(); specGeneration.next()
        queue.async { [self] in
            unloadLocked()
            state = .unloaded(name)
        }
    }

    /// Frees the model synchronously. Call before the process exits, or ggml-metal asserts.
    func shutdown() {
        generation.next(); specGeneration.next()
        queue.sync { unloadLocked() }
    }

    // MARK: Idle context release

    /// Idle: frees the KV cache and the Metal compute buffers but keeps the memory-mapped weights,
    /// so waking up costs only the context allocation plus re-reading the prompt (no model reload).
    func releaseContext() {
        queue.async { [self] in
            guard let c = ctx else { return }
            llama_free(c)
            ctx = nil
            cached = []
            Log.write("engine: context released (idle)")
        }
    }

    /// Recreates the context ahead of the first request after idle (overlaps the debounce delay).
    func wakeContext() {
        queue.async { [self] in _ = ensureContextLocked() }
    }

    private func ensureContextLocked() -> Bool {
        if ctx != nil { return true }
        guard let model else { return false }
        let started = Date()
        guard let c = llama_init_from_model(model, contextParams) else {
            failureLock.lock(); failureCount += 1; failureLock.unlock()
            Log.info("engine: could not recreate context (\(failureCount) in a row)")
            return false
        }
        ctx = c
        cached = []
        Log.write(String(format: "engine: context recreated in %.0fms", Date().timeIntervalSince(started) * 1000))
        return true
    }

    private func unloadLocked() {
        failureLock.lock(); failureCount = 0; failureLock.unlock()
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        ctx = nil; model = nil; vocab = nil; cached = []; flags = []; nVocab = 0; probs = []; headerMemo = ("", 0)
        pieceData = []; pieceOffsets = []
    }

    // MARK: Completion

    struct Completion {
        let text: String
        /// Generation stopped because it hit `maxTokens` (last word may be cut).
        let truncated: Bool
    }

    /// Continues `prompt`. Calls back on the main queue with nil if cancelled or failed.
    /// `speculative` requests are cancelled only via `specGeneration`.
    /// `header` is the context part at the start of `prompt`: repetition penalties never apply to it.
    /// `heal`: the half-typed word removed from the end of `prompt` (with its leading space). The output is
    /// forced to begin with it, so whole-word tokens stay reachable ("idiom" → "idioma", one token), and the
    /// returned text starts right after it.
    /// `instruction`: rewrites, translations and lookup summaries (cancelled via `taskGeneration`). The whole
    /// prompt (which contains the user's original text) is protected from repetition/DRY penalties — the model
    /// *must* be free to reuse the user's words — and generation runs to the end of the line, never cut on an
    /// uncertain word and never pushed past the end of the sentence. Quotes inside the answer (`L'espressione
    /// "…" significa`) don't stop it: the closing quote is removed afterwards (`CompletionController.rewriteResult`).
    func complete(prompt: String, header: String = "", mustStartWithSpace: Bool = false, heal: String = "",
                  maxTokens: Int, id: Int, speculative: Bool = false, instruction: Bool = false,
                  completion: @escaping (Completion?) -> Void) {
        queue.async { [self] in
            activeGen = speculative ? specGeneration : (instruction ? taskGeneration : generation)
            let result = generateLocked(prompt: prompt, header: header, mustStartWithSpace: mustStartWithSpace,
                                        heal: Array(heal.utf8), maxTokens: maxTokens, id: id, instruction: instruction)
            activeGen = nil
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func cancelled(_ id: Int?) -> Bool {
        guard let id else { return false }
        return (activeGen ?? generation).current != id
    }

    private func generateLocked(prompt: String, header: String = "", mustStartWithSpace: Bool = false, heal: [UInt8] = [],
                                maxTokens: Int, id: Int?, instruction: Bool = false) -> Completion? {
        let budget = maxTokens + (heal.isEmpty ? 0 : 4)
        guard !cancelled(id), let n = prefillLocked(prompt: prompt, reserve: budget, id: id, header: header) else { return nil }
        if instruction { penaltyFrom = n }   // penalize only repetitions inside the output itself
        return greedyLocked(first: nil, mustStartWithSpace: mustStartWithSpace, heal: heal, maxTokens: budget, id: id,
                            instruction: instruction)
    }

    // MARK: Token healing

    /// Token `i` is compatible with the bytes still owed (`need`): it covers them and maybe more, or it is
    /// a piece of them.
    private func compatible(_ i: Int, _ need: ArraySlice<UInt8>) -> Bool {
        let a = Int(pieceOffsets[i]), b = Int(pieceOffsets[i + 1])
        let len = b - a
        guard len > 0, let first = need.first, pieceData[a] == first else { return false }
        let n = min(len, need.count)
        var k = 1
        var j = need.startIndex + 1
        while k < n { if pieceData[a + k] != need[j] { return false }; k += 1; j += 1 }
        return true
    }

    /// Best tokens compatible with `need`, highest logit first.
    private func healCandidatesLocked(_ logits: UnsafeMutablePointer<Float>, need: ArraySlice<UInt8>, limit: Int) -> [llama_token] {
        guard pieceOffsets.count == nVocab + 1 else { return [] }
        var top: [(Float, Int)] = []
        for i in 0..<nVocab where flags[i] & (Flag.eog | Flag.badStart) == 0 {
            let l = logits[i]
            if top.count == limit, l <= top[limit - 1].0 { continue }
            guard compatible(i, need) else { continue }
            top.append((l, i)); top.sort { $0.0 > $1.0 }
            if top.count > limit { top.removeLast() }
        }
        return top.map { llama_token($0.1) }
    }

    /// Tokens of `header` (minus one: the boundary token may merge with the draft). Memoized.
    private func headerTokensLocked(_ header: String) -> Int {
        guard !header.isEmpty else { return 0 }
        if headerMemo.text == header { return headerMemo.tokens }
        let n = max(0, tokenize(header).count - 1)
        headerMemo = (header, n)
        return n
    }

    /// Evaluates `prompt` into the KV cache without generating anything. Used during typing pauses after
    /// the context header changed, so the next keystroke only pays for its own new tokens. Runs in small
    /// chunks: any keystroke (which bumps `generation`) cancels it within a few milliseconds.
    func warm(prompt: String, reserve: Int, id: Int) {
        queue.async { [self] in
            activeGen = generation
            let started = Date()
            if let n = prefillLocked(prompt: prompt, reserve: reserve, id: id, chunk: 64) {
                Log.write(String(format: "engine: warmed %d tokens in %.0fms", n, Date().timeIntervalSince(started) * 1000))
            }
            activeGen = nil
        }
    }

    /// Evaluates `prompt`, reusing the KV cache for the shared prefix. Returns the prompt length in tokens.
    private func prefillLocked(prompt: String, reserve: Int, id: Int?, chunk chunkSize: Int? = nil, header: String = "") -> Int? {
        guard ensureContextLocked(), let ctx else { return nil }
        var tokens = tokenize(prompt)
        guard !tokens.isEmpty else { return nil }
        var protected = headerTokensLocked(header)
        let budget = nCtx - reserve - 8
        if tokens.count > budget {
            protected = max(0, protected - (tokens.count - budget))
            tokens = [tokens[0]] + tokens.suffix(budget - 1)   // keep BOS
        }
        penaltyFrom = min(protected, tokens.count)
        var n = zip(cached, tokens).prefix(while: { $0 == $1 }).count
        if n == tokens.count { n -= 1 }   // must evaluate at least one token to get logits
        let mem = llama_get_memory(ctx)
        if !llama_memory_seq_rm(mem, 0, Int32(n), -1) {
            llama_memory_clear(mem, true)
            n = 0
        }
        cached = Array(tokens[0..<n])
        var pending = Array(tokens[n...])
        while !pending.isEmpty {
            if cancelled(id) { return nil }
            let chunk = Array(pending.prefix(min(nBatch, chunkSize ?? nBatch)))
            pending.removeFirst(chunk.count)
            guard decode(chunk, ctx: ctx) else {
                llama_memory_clear(mem, true); cached = []; return nil
            }
            cached += chunk
        }
        return tokens.count
    }

    /// Repetition penalty on recent content words + n-gram DRY loop blocking, in place on `logits`.
    /// Punctuation and short function words ("di", "a", "un", ".") are never penalized individually.
    /// Only the draft counts (from `penaltyFrom`): copying a date or a name from the context is the point,
    /// not a loop. Digits are exempt from DRY too, so "dal 19 al 23" can be written again.
    private func applyPenaltiesLocked(logits: UnsafeMutablePointer<Float>) {
        let n = cached.count
        guard n > 1, flags.count == nVocab else { return }
        let floor = min(penaltyFrom, n - 1)
        var counts: [llama_token: Int] = [:]
        counts.reserveCapacity(48)
        for i in max(floor, n - 64)..<n {
            let tok = cached[i]
            if Int(tok) < nVocab, flags[Int(tok)] & Flag.content != 0 { counts[tok, default: 0] += 1 }
        }
        for (tok, c) in counts {
            let idx = Int(tok)
            let v = logits[idx]
            logits[idx] = (v > 0 ? v / 1.16 : v * 1.16) - Float(c) * 0.10 - 0.06
        }
        // DRY: block continuing any 3+ token sequence already present in the recent draft.
        let dryStart = max(floor, n - 160)
        guard dryStart < n - 1 else { return }
        let lastTok = cached[n - 1]
        for i in dryStart..<(n - 1) where cached[i] == lastTok {
            let idx = Int(cached[i + 1])
            guard idx >= 0, idx < nVocab, flags[idx] & Flag.digit == 0 else { continue }
            var matchLen = 1
            while matchLen < 8, i - matchLen >= dryStart, cached[i - matchLen] == cached[n - 1 - matchLen] {
                matchLen += 1
            }
            if matchLen >= 3 { logits[idx] -= 50 } else if matchLen == 2 { logits[idx] -= 5 }
        }
    }

    /// Vectorized argmax over the vocabulary (no 262k-entry candidate array per token).
    private func argmax(_ logits: UnsafeMutablePointer<Float>) -> Int {
        var value: Float = 0
        var index: vDSP_Length = 0
        vDSP_maxvi(logits, 1, &value, &index, vDSP_Length(nVocab))
        return Int(index)
    }

    /// Picks the next token. On step 0 it never starts with a line break, and after a typed space
    /// it must start a new word. Later, returns nil (= end the suggestion here) when the next *word*
    /// would be a low-confidence guess and the suggestion already has something useful.
    /// After a sentence/clause ends (`continuePastEnd`), an end-of-message or line break is replaced by the
    /// most likely next word, so the suggestion flows on until the user decides to stop.
    private func sampleTokenLocked(step: Int, mustStartWithSpace: Bool, stopIfUncertain: Bool = false,
                                   continuePastEnd: Bool = false) -> llama_token? {
        guard let ctx, nVocab > 0, flags.count == nVocab, let logits = llama_get_logits_ith(ctx, -1) else { return nil }
        applyPenaltiesLocked(logits: logits)
        let top = argmax(logits)
        let needsWord = step > 0 || mustStartWithSpace
        if step > 0 {
            let ends = flags[top] & (Flag.badStart | Flag.eog) != 0
            if !(ends && continuePastEnd) {
                if stopIfUncertain, flags[top] & Flag.wordStart != 0, topProbability(logits, top: top) < uncertainWord {
                    return nil
                }
                return llama_token(top)
            }
        }

        func allowed(_ i: Int) -> Bool {
            let f = flags[i]
            return f & (Flag.badStart | Flag.eog) == 0 && (!needsWord || f & Flag.wordStart != 0)
        }
        if allowed(top) { return llama_token(top) }
        var best = -1
        var bestLogit = -Float.infinity
        for i in 0..<nVocab where logits[i] > bestLogit && allowed(i) {
            bestLogit = logits[i]; best = i
        }
        // Even when the model would rather end here (end of message / new line), offer the best way to go
        // on: the user decides when the text is over, not the model.
        guard best >= 0 else { return nil }
        return llama_token(best)
    }

    /// True right after a punctuation mark: the start of the next clause/sentence is naturally uncertain,
    /// and stopping there is exactly the "suggestions die after a period" behavior we don't want.
    private func afterPunctuation(_ bytes: [UInt8]) -> Bool {
        guard let last = bytes.last(where: { $0 != 32 }) else { return false }
        return [46, 44, 59, 58, 33, 63].contains(last)   // . , ; : ! ?
    }

    /// Last visible character ends a sentence (". ! ?").
    private func afterSentenceEnd(_ bytes: [UInt8]) -> Bool {
        guard let last = bytes.last(where: { $0 != 32 }) else { return false }
        return last == 46 || last == 33 || last == 63
    }

    /// Softmax probability of `top` (vectorized: one pass of exp over the vocabulary, ~0.2 ms).
    private func topProbability(_ logits: UnsafeMutablePointer<Float>, top: Int) -> Float {
        if probs.count != nVocab { probs = [Float](repeating: 0, count: nVocab) }
        var negMax = -logits[top]
        var count = Int32(nVocab)
        var sum: Float = 0
        probs.withUnsafeMutableBufferPointer { buf in
            guard let p = buf.baseAddress else { return }
            vDSP_vsadd(logits, 1, &negMax, p, 1, vDSP_Length(nVocab))
            vvexpf(p, p, &count)
            vDSP_sve(p, 1, &sum, vDSP_Length(nVocab))
        }
        return sum > 0 ? 1 / sum : 1
    }

    /// Greedy decoding from the current logits (optionally forcing the first token).
    private func greedyLocked(first: llama_token?, mustStartWithSpace: Bool = false, heal: [UInt8] = [],
                              maxTokens: Int, id: Int?, instruction: Bool = false) -> Completion? {
        guard let ctx, let vocab else { return nil }
        var bytes: [UInt8] = []
        var truncated = true
        var forced = first
        var hasWord = false
        var healStep = 0
        for step in 0..<maxTokens {
            if cancelled(id) { return nil }
            let t: llama_token
            let owed = bytes.count < heal.count
            if let f = forced {
                t = f; forced = nil
            } else if owed {
                // Still writing the half-typed word: only tokens that agree with it, case included.
                guard let logits = llama_get_logits_ith(ctx, -1) else { return nil }
                applyPenaltiesLocked(logits: logits)
                guard let best = healCandidatesLocked(logits, need: heal[bytes.count...], limit: 1).first else { return nil }
                t = best
            } else if let sampled = sampleTokenLocked(step: heal.isEmpty ? step : max(1, step - healStep),
                                                      mustStartWithSpace: heal.isEmpty && mustStartWithSpace,
                                                      stopIfUncertain: !instruction && hasWord && !afterPunctuation(bytes),
                                                      continuePastEnd: !instruction && afterSentenceEnd(bytes)) {
                t = sampled
            } else {
                truncated = false; break
            }
            if llama_vocab_is_eog(vocab, t) { truncated = false; break }
            let piece = pieceBytes(t)
            if let nl = piece.firstIndex(of: 10) {   // stop at end of line
                bytes += piece[..<nl]; truncated = false; break
            }
            bytes += piece
            if owed { healStep = step + 1 }
            if !hasWord { hasWord = bytes.contains { ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 >= 128 } }
            guard decode([t], ctx: ctx) else { break }
            cached.append(t)
        }
        if !heal.isEmpty {
            guard bytes.count >= heal.count, Array(bytes.prefix(heal.count)) == heal else { return nil }
            bytes.removeFirst(heal.count)
        }
        var text = String(decoding: bytes, as: UTF8.self)
        while text.hasSuffix("\u{FFFD}") { text.removeLast() }   // cut partial UTF-8
        return Completion(text: text, truncated: truncated)
    }

    /// Up to `count` different continuations, one per most-likely first token. With `heal` (the half-typed
    /// word, see `complete`) every candidate agrees with what's already typed.
    func alternatives(prompt: String, header: String = "", mustStartWithSpace: Bool = false, heal: String = "",
                      count: Int, maxTokens: Int, id: Int, completion: @escaping ([Completion]) -> Void) {
        queue.async { [self] in
            activeGen = generation
            var results: [Completion] = []
            defer { activeGen = nil; let r = results; DispatchQueue.main.async { completion(r) } }
            let healBytes = Array(heal.utf8)
            let budget = maxTokens + (healBytes.isEmpty ? 0 : 4)
            guard ensureContextLocked(), let ctx, flags.count == nVocab,
                  let promptLen = prefillLocked(prompt: prompt, reserve: budget, id: id, header: header),
                  let logits = llama_get_logits_ith(ctx, -1) else { return }
            applyPenaltiesLocked(logits: logits)
            let limit = count * 5
            var top: [llama_token] = []
            if !healBytes.isEmpty {
                top = healCandidatesLocked(logits, need: healBytes[...], limit: limit)
            } else {
                // Top candidates by logit (skip end-of-text, line breaks and, after a space, word pieces).
                var scored: [(Float, llama_token)] = []
                for i in 0..<nVocab {
                    let l = logits[i]
                    guard scored.count < limit || l > scored.last!.0 else { continue }
                    let f = flags[i]
                    if f & (Flag.badStart | Flag.eog) != 0 { continue }
                    if mustStartWithSpace, f & Flag.wordStart == 0 { continue }
                    scored.append((l, llama_token(i))); scored.sort { $0.0 > $1.0 }
                    if scored.count > limit { scored.removeLast() }
                }
                top = scored.map { $0.1 }
            }
            let mem = llama_get_memory(ctx)
            var seen = Set<String>()
            for t in top where results.count < count {
                if cancelled(id) { return }
                let key = String(decoding: pieceBytes(t), as: UTF8.self).trimmingCharacters(in: .whitespaces).lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                _ = llama_memory_seq_rm(mem, 0, Int32(promptLen), -1)
                cached = Array(cached.prefix(promptLen))
                if let c = greedyLocked(first: t, mustStartWithSpace: mustStartWithSpace, heal: healBytes, maxTokens: budget, id: id),
                   !c.text.isEmpty || !healBytes.isEmpty {
                    results.append(c)
                }
            }
        }
    }

    private func decode(_ toks: [llama_token], ctx: OpaquePointer) -> Bool {
        var toks = toks
        let ok = toks.withUnsafeMutableBufferPointer { buf in
            llama_decode(ctx, llama_batch_get_one(buf.baseAddress, Int32(buf.count))) == 0
        }
        if ok {
            if failureCount != 0 { failureLock.lock(); failureCount = 0; failureLock.unlock() }
        } else {
            failureLock.lock(); failureCount += 1; failureLock.unlock()
            Log.info("engine: decode failed (\(failureCount) in a row)")
        }
        return ok
    }

    /// Consecutive GPU decode failures (e.g. Metal state lost after sleep). The app reloads the model when it grows.
    private var failureCount = 0
    private let failureLock = NSLock()
    var consecutiveFailures: Int { failureLock.lock(); defer { failureLock.unlock() }; return failureCount }

    private func tokenize(_ text: String) -> [llama_token] {
        guard let vocab else { return [] }
        let utf8Count = text.utf8.count
        var out = [llama_token](repeating: 0, count: utf8Count + 8)
        var n = llama_tokenize(vocab, text, Int32(utf8Count), &out, Int32(out.count), true, false)
        if n < 0 {
            out = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, Int32(utf8Count), &out, Int32(out.count), true, false)
        }
        var toks = n > 0 ? Array(out.prefix(Int(n))) : []
        // Always ensure <bos> is at index 0 (Gemma 4 attention sink; some GGUFs omit add_bos_token).
        let bos = llama_vocab_bos(vocab)
        if bos >= 0, toks.first != bos { toks.insert(bos, at: 0) }
        return toks
    }

    private func pieceBytes(_ t: llama_token) -> [UInt8] {
        var buf = [CChar](repeating: 0, count: 64)
        var n = llama_token_to_piece(vocab, t, &buf, Int32(buf.count), 0, false)
        if n < 0 {
            buf = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, t, &buf, Int32(buf.count), 0, false)
        }
        return n > 0 ? buf.prefix(Int(n)).map { UInt8(bitPattern: $0) } : []
    }
}
