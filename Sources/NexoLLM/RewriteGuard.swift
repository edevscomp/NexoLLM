import Foundation

/// Last check before a writing-tool answer replaces the user's text. Small local models (1B–3B) sometimes
/// ignore a very short input ("cao") and echo one of the prompt's examples, or ramble far past the original.
/// Both are rejected here, so the text in the field is only ever replaced by a rewrite *of that text*.
enum RewriteGuard {
    /// Lower-cased words (letters and digits only).
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    private static func ngrams(_ w: [String], _ n: Int) -> Set<String> {
        guard w.count >= n else { return [] }
        return Set((0...(w.count - n)).map { w[$0..<($0 + n)].joined(separator: " ") })
    }

    /// Most words a rewrite of `original` may have. A translation can grow a little more than a rewrite;
    /// a shorter version can't grow at all.
    static func maxWords(original: String, instruction: String) -> Int {
        let n = max(1, words(original).count)
        let l = instruction.lowercased()
        if l.contains("concise") || l.contains("shorter") { return n + 2 }
        if l.contains("translate") { return max(n * 2 + 4, 6) }
        return max(n * 2 + 3, 6)
    }

    /// True when the answer is largely copied from the prompt's own instructions or examples: two or more
    /// four-word runs the user never wrote, or most of the answer. A single common phrase ("I'll send it")
    /// shared by chance is not a leak.
    static func leaksPrompt(output: String, prompt: String, original: String) -> Bool {
        var scaffold = prompt
        if let r = scaffold.range(of: original, options: .backwards) { scaffold.removeSubrange(r) }
        let fromPrompt = ngrams(words(scaffold), 4)
        let own = ngrams(words(output), 4).subtracting(ngrams(words(original), 4))
        guard !own.isEmpty else { return false }
        let copied = own.intersection(fromPrompt).count
        return copied >= 2 || Double(copied) / Double(own.count) >= 0.5
    }

    /// The answer can safely replace `original` (never echoed scaffold, runaway rambling, or catastrophic truncation).
    static func accepts(output: String, original: String, prompt: String, instruction: String) -> Bool {
        let w = words(output)
        guard !w.isEmpty else { return false }
        let origWords = words(original).count
        if origWords >= 16, w.count * 4 < origWords { return false }
        if w.count > maxWords(original: original, instruction: instruction) { return false }
        return !leaksPrompt(output: output, prompt: prompt, original: original)
    }

    /// One or two words: there is nothing to restyle, only to correct. Improve, Fix Grammar and Shorter answer
    /// with the spelling-corrected text instead of asking the model ("cao" → "Ciao", never a made-up sentence).
    static func isTooShortToRewrite(_ text: String, instruction: String) -> Bool {
        let l = instruction.lowercased()
        guard !l.contains("translate"), !l.contains("formal") else { return false }
        return words(text).count <= 2
    }
}
