#if DEBUG || NEXO_DEV
import Foundation

/// Headless engine check: loads the model and times completions, header prompts, alternatives and synonyms.
enum SelfTest {
    static func run(modelPath: String) {
        let engine = LLMEngine()
        let loaded = DispatchSemaphore(value: 0)
        var failure: String?
        engine.onStateChange = { state in
            switch state {
            case .ready: loaded.signal()
            case .failed(let m): failure = m; loaded.signal()
            case .noModel: failure = "model file not found"; loaded.signal()
            default: break
            }
        }
        let t0 = Date()
        engine.load(path: modelPath)
        pump(loaded)
        if let failure { print("LOAD FAILED: \(failure)"); return }
        print(String(format: "Model loaded in %.2fs", Date().timeIntervalSince(t0)))

        // Token healing: the same half-typed word, without and with healing, plus word alternatives.
        print("\n— Token healing: plain ⟨…⟩  healed ⟨…⟩  words […]")
        for text in ["In Italia ogni regione ha il suo dialetto, ma l'italiano resta il nostro idiom",
                     "Scusa il ritardo, ti rispondo appena posso perché oggi sono molto impegn",
                     "Thanks for the quick reply, I really apprec",
                     "Let's move the meeting to next Wednes"] {
            let p = SuggestionText.prompt(prefix: text, prefixStart: 0, caretLocation: (text as NSString).length)
            func run(_ prompt: String, heal: String) -> String {
                let done = DispatchSemaphore(value: 0)
                var out: LLMEngine.Completion?
                engine.complete(prompt: prompt, heal: heal, maxTokens: 6, id: engine.generation.next()) { r in out = r; done.signal() }
                pump(done)
                return SuggestionText.clean(out?.text ?? "", userEndedWithSpace: false, truncated: out?.truncated ?? false, prefix: text)
            }
            let plain = run(p.text, heal: "")
            guard let split = SuggestionText.healSplit(p.text) else { continue }
            let healed = run(split.stem, heal: split.heal)
            let partial = split.heal.trimmingCharacters(in: .whitespaces)
            let done = DispatchSemaphore(value: 0)
            var words: [String] = []
            engine.alternatives(prompt: split.stem, heal: split.heal, count: 6, maxTokens: 3, id: engine.generation.next()) { r in
                var seen = Set<String>()
                words = r.compactMap { SuggestionText.firstWord(partial: partial, continuation: $0.text) }
                    .filter { Spelling.isWord($0, context: text) && seen.insert($0.lowercased()).inserted }
                done.signal()
            }
            pump(done)
            print("…\(text.suffix(28))⟨\(plain)⟩  ⟨\(healed)⟩  \(words)")
        }
        print("")

        let header = SuggestionText.header(appName: "WhatsApp", instructions: Prefs.defaultInstructions,
                                           appInstructions: "", screen: nil, clipboard: nil, examples: [])
        let cases = [
            "Ciao Marco, grazie per la tua email. Ti scrivo per ",
            "Continuando col discorso di prima, la mia idea è che la gente non si rende conto di quanto sia importante la privacy, ",
            "Oggi sono andato a ",
            "Ho comprato un ",
            "Domani non riesco a venire alla riunione perché",
            "Dear Sarah, I hope this message finds you",
            "La riunione di domani è stata spostata alle ore",
        ]
        for (label, h) in [("plain ", ""), ("header", header)] {
            for text in cases {
                let p = SuggestionText.prompt(prefix: text, prefixStart: 0, caretLocation: (text as NSString).length, header: h)
                let done = DispatchSemaphore(value: 0)
                var out: LLMEngine.Completion?
                let t = Date()
                engine.complete(prompt: p.text, mustStartWithSpace: p.userEndedWithSpace, maxTokens: 10, id: engine.generation.next()) { r in out = r; done.signal() }
                pump(done)
                let shown = SuggestionText.clean(out?.text ?? "", userEndedWithSpace: p.userEndedWithSpace, truncated: out?.truncated ?? false, prefix: text)
                print(String(format: "[%@ %4.0f ms] %@⟨%@⟩", label, Date().timeIntervalSince(t) * 1000, text, shown))
            }
        }

        // Tab chain: accept every suggestion (plus trailing space) and ask for the next one, like a user
        // holding down Tab. Each step must produce something, including right after a period.
        for start in ["Ciao Marco, grazie per la tua email. ", "Domani non riesco a venire alla riunione perché"] {
            var text = start
            var empty = 0
            let tc = Date()
            for _ in 0..<10 {
                let p = SuggestionText.prompt(prefix: text, prefixStart: 0, caretLocation: (text as NSString).length, header: header)
                let done = DispatchSemaphore(value: 0)
                var out: LLMEngine.Completion?
                engine.complete(prompt: p.text, mustStartWithSpace: p.userEndedWithSpace, maxTokens: 8, id: engine.generation.next()) { r in out = r; done.signal() }
                pump(done)
                let shown = SuggestionText.clean(out?.text ?? "", userEndedWithSpace: p.userEndedWithSpace, truncated: out?.truncated ?? false, prefix: text)
                if shown.isEmpty { empty += 1; text += " "; continue }
                text += shown + " "
            }
            print(String(format: "[chain %4.0f ms/step, %d empty] %@", Date().timeIntervalSince(tc) * 100, empty, text))
        }

        // Alternatives
        let alt = "Ciao Marco, ci vediamo"
        let ap = SuggestionText.prompt(prefix: alt, prefixStart: 0, caretLocation: (alt as NSString).length, header: header)
        let ad = DispatchSemaphore(value: 0)
        var alts: [LLMEngine.Completion] = []
        let ta = Date()
        engine.alternatives(prompt: ap.text, count: 4, maxTokens: 8, id: engine.generation.next()) { r in alts = r; ad.signal() }
        pump(ad)
        print(String(format: "[alts %4.0f ms] %@ → %@", Date().timeIntervalSince(ta) * 1000, alt,
                     alts.map { SuggestionText.clean($0.text, userEndedWithSpace: false, truncated: $0.truncated) }.description))

        // Synonyms
        for word in ["felice", "importante", "quickly"] {
            let it = word != "quickly"
            let prompt = it
                ? "Sinonimi di \"felice\": contento, lieto, gioioso, sereno\nSinonimi di \"veloce\": rapido, svelto, celere, lesto\nSinonimi di \"\(word)\":"
                : "Synonyms of \"happy\": glad, joyful, cheerful, content\nSynonyms of \"fast\": quick, rapid, swift, speedy\nSynonyms of \"\(word)\":"
            let sd = DispatchSemaphore(value: 0)
            var so: LLMEngine.Completion?
            engine.complete(prompt: prompt, maxTokens: 24, id: engine.generation.next()) { r in so = r; sd.signal() }
            pump(sd)
            print("[syn] \(word) → \(so?.text ?? "nil")")
        }

        // Memory: the same draft with and without a recalled topic from yesterday.
        let mem = Memory(url: nil)
        mem.ingest([.init(app: "net.whatsapp.WhatsApp", appName: "WhatsApp",
                          text: "Oggi mi sono tagliato il dito con una lattina aprendo i pelati, fa malissimo.", screen: nil)],
                   now: Date().addingTimeInterval(-20 * 3600), sync: true)
        for draft in ["Ciao Marco, il dito ", "Il dito va un po' meglio, ma "] {
            let recall = mem.recall(query: draft, draft: draft, app: "net.whatsapp.WhatsApp")
            for (label, block) in [("no-mem", nil as String?), ("memory", recall?.block)] {
                let h = SuggestionText.header(appName: "WhatsApp", instructions: Prefs.defaultInstructions, appInstructions: "",
                                              screen: nil, clipboard: nil, examples: [], memory: block)
                let p = SuggestionText.prompt(prefix: draft, prefixStart: 0, caretLocation: (draft as NSString).length, header: h)
                let d = DispatchSemaphore(value: 0)
                var out: LLMEngine.Completion?
                engine.complete(prompt: p.text, mustStartWithSpace: p.userEndedWithSpace, maxTokens: 12, id: engine.generation.next()) { out = $0; d.signal() }
                pump(d)
                print("[\(label)] \(draft)⟨\(SuggestionText.clean(out?.text ?? "", userEndedWithSpace: p.userEndedWithSpace, truncated: out?.truncated ?? false, prefix: draft))⟩")
            }
        }

        // Idle release: memory before/after, then the cost of the first suggestion after waking.
        let long = SuggestionText.prompt(prefix: cases[1], prefixStart: 0, caretLocation: (cases[1] as NSString).length, header: header)
        func run(_ p: SuggestionText.Prompt) -> Double {
            let d = DispatchSemaphore(value: 0)
            let t = Date()
            engine.complete(prompt: p.text, mustStartWithSpace: p.userEndedWithSpace, maxTokens: 8, id: engine.generation.next()) { _ in d.signal() }
            pump(d)
            return Date().timeIntervalSince(t) * 1000
        }
        _ = run(long)
        let warm = run(long)
        let before = footprintMB()
        engine.releaseContext()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))   // the engine queue is idle: release runs now
        let after = footprintMB()
        let cold = run(long)
        print(String(format: "[idle] footprint %.0f MB → %.0f MB asleep (−%.0f MB) · suggestion %.0f ms warm, %.0f ms after wake",
                     before, after, before - after, warm, cold))
        engine.shutdown()
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private static func pump(_ s: DispatchSemaphore) {
        while s.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
}
#endif
