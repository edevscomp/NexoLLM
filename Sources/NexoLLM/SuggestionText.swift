import Foundation

/// Pure text logic (no AppKit), unit-tested in Tests/NexoLLMTests.
enum SuggestionText {
    /// Prompt sent to the model plus whether the user's text ended in whitespace.
    struct Prompt: Equatable {
        let text: String
        let userEndedWithSpace: Bool
    }

    /// Horizontal whitespace excluding newline (ASCII space, tab, NBSP, narrow NBSP, figure space).
    static func isSpace(_ ch: Character) -> Bool {
        ch == " " || ch == "\u{00A0}" || ch == "\u{202F}" || ch == "\u{2007}"
    }

    static func isHorizontalSpace(_ ch: Character) -> Bool {
        ch == "\t" || isSpace(ch)
    }

    /// Normalizes WebKit / rich-editor non-breaking spaces to standard ASCII spaces while preserving tabs/newlines.
    static func normalizeSpaces(_ s: String) -> String {
        guard s.contains(where: { $0 == "\u{00A0}" || $0 == "\u{202F}" || $0 == "\u{2007}" }) else { return s }
        return String(s.map { isSpace($0) ? " " : $0 })
    }

    /// Reconciles a suggestion with characters typed after `basePrefix` (e.g. 1-keystroke AX lag)
    /// and guarantees no extra leading space is inserted if `livePrefix` already ends in whitespace.
    static func reconcile(suggestion: String, basePrefix: String?, livePrefix: String?) -> String {
        var out = suggestion
        let normLive = livePrefix.map(normalizeSpaces)
        if let base = basePrefix, let normLive {
            let normBase = normalizeSpaces(base)
            var delta: Substring?
            if normLive.hasPrefix(normBase) {
                delta = normLive.dropFirst(normBase.count)
            } else if normBase.count >= 64 {
                for drop in 1...min(32, normBase.count - 48) {
                    let tail = normBase.dropFirst(drop)
                    if normLive.hasPrefix(tail) {
                        delta = normLive.dropFirst(tail.count)
                        break
                    }
                }
            }
            if let delta, !delta.isEmpty {
                let normOut = normalizeSpaces(out)
                if normOut.hasPrefix(delta) {
                    out = String(out.dropFirst(delta.count))
                } else if delta.hasPrefix(normOut) {
                    return ""
                }
            }
        }
        if let normLive, let last = normLive.last, isHorizontalSpace(last) {
            while let first = out.first, isHorizontalSpace(first) {
                out.removeFirst()
            }
        }
        return out
    }

    /// Builds the prompt from the text before the caret.
    /// The window start is aligned to 512-unit blocks so it stays put while typing, letting the
    /// engine reuse its KV cache instead of re-reading the whole context on every keystroke.
    static func prompt(prefix: String, prefixStart: Int, caretLocation: Int, window: Int = 1500, header: String = "") -> Prompt {
        let ns = prefix as NSString
        var absStart = max(0, caretLocation - window)
        absStart = (absStart / 512) * 512
        absStart = max(absStart, prefixStart)
        let offset = min(max(0, absStart - prefixStart), ns.length)
        var text = ns.substring(from: offset)
        if absStart > 0, let ws = text.firstIndex(where: { $0.isWhitespace }) {
            text = String(text[text.index(after: ws)...])   // don't start mid-word
        }
        text = normalizeSpaces(normalizeLinks(text))
        // SentencePiece tokens carry their leading space ("▁word"), so a prompt ending in a space
        // confuses the model. Strip it and expect the completion to begin with a space instead.
        let endedWithSpace = text.last.map(isHorizontalSpace) ?? false
        while let last = text.last, isHorizontalSpace(last) { text.removeLast() }
        return Prompt(text: header + text, userEndedWithSpace: endedWithSpace)
    }

    private static let urlPattern = try! NSRegularExpression(pattern: #"(?i)\b(?:https?://|www\.)\S+"#)

    /// Finished links become their host ("youtube.com") and link attachments (U+FFFC) the word "link": a long
    /// query string at the end of the prompt makes the model continue the URL instead of the sentence.
    static func normalizeLinks(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\u{FFFC}", with: "link")
        for m in urlPattern.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed() {
            let raw = (out as NSString).substring(with: m.range)
            let trailing = String(raw.reversed().prefix(while: { ",.;:!?)".contains($0) }).reversed())
            let core = String(raw.dropLast(trailing.count))
            let host = URL(string: core.lowercased().hasPrefix("www.") ? "https://" + core : core)?.host ?? "link"
            let short = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            out = (out as NSString).replacingCharacters(in: m.range, with: short + trailing)
        }
        return out
    }

    /// The caret sits at the end of a link still being typed or pasted (no space after it yet).
    static func isInsideURL(_ prefix: String) -> Bool {
        guard let last = prefix.last, !last.isWhitespace,
              let token = prefix.split(whereSeparator: { $0.isWhitespace }).last?.lowercased() else { return false }
        return token.hasPrefix("http://") || token.hasPrefix("https://") || token.hasPrefix("www.")
    }

    /// Token healing: splits the half-typed word off the end of the prompt, with the space before it
    /// ("…è un idiom" → stem "…è un", heal " idiom"). The tokenizer would otherwise freeze " idiom" as a
    /// finished token and make the single token " idioma" unreachable, so the model could only append rare
    /// suffixes ("atismi"). nil when the prompt doesn't end inside a word.
    static func healSplit(_ text: String) -> (stem: String, heal: String)? {
        var start = text.endIndex
        var letters = 0
        while start > text.startIndex {
            let p = text.index(before: start)
            guard text[p].isLetter else { break }
            start = p
            letters += 1
            if letters > 24 { return nil }
        }
        guard letters >= 1, start > text.startIndex else { return nil }
        let before = text.index(before: start)
        if text[before].isNumber || "_./:=?&@#".contains(text[before]) { return nil }   // "3pm", identifiers, links
        let cut = isSpace(text[before]) ? before : start
        let stem = normalizeSpaces(String(text[..<cut]))
        guard stem.contains(where: { !$0.isWhitespace }) else { return nil }
        return (stem, normalizeSpaces(String(text[cut...])))
    }

    /// The whole word a candidate continuation produces: the half-typed `partial` plus the letters the model
    /// added to it, or (with no partial) the first word of the continuation. nil when the candidate leaves
    /// the typed word as it is or starts with something that isn't a word.
    static func firstWord(partial: String, continuation: String) -> String? {
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c == "'" || c == "’" || c == "-" }
        if !partial.isEmpty {
            let rest = continuation.prefix(while: isWordChar)
            guard !rest.isEmpty else { return nil }
            return partial + rest.trimmingCharacters(in: CharacterSet(charactersIn: "-'’"))
        }
        let body = continuation.drop(while: { $0.isWhitespace })
        let word = String(body.prefix(while: isWordChar)).trimmingCharacters(in: CharacterSet(charactersIn: "-'’"))
        return word.contains(where: { $0.isLetter }) ? word : nil
    }

    /// Context block placed before the user's text. Kept stable while typing in one field.
    /// Ordered from most to least stable, so a change only invalidates the tail of the model's prompt cache.
    /// The other fields of the same window (subject, recipients…) come last, right before the draft:
    /// they're the most relevant facts for what is being written and the model copies them reliably from there.
    static func header(appName: String, instructions: String, appInstructions: String,
                       screen: String?, clipboard: String?, examples: [String], memory: String? = nil,
                       style: String? = nil, fields: String? = nil, audio: String? = nil, screenBudget: Int = 1400) -> String {
        var parts: [String] = []
        let notes = [instructions, appInstructions]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !notes.isEmpty { parts.append("[Author profile & style]\n" + notes.joined(separator: "\n")) }
        if let style, !style.isEmpty { parts.append(String(style.prefix(480))) }
        if !examples.isEmpty {
            let ex = examples.prefix(3).map { "- " + String($0.replacingOccurrences(of: "\n", with: " ").suffix(220)) }
            parts.append("[Recent writing samples by the same author]\n" + ex.joined(separator: "\n"))
        }
        if let clipboard, !clipboard.isEmpty {
            parts.append("[Clipboard]\n" + String(clipboard.prefix(360)))
        }
        if let screen, !screen.isEmpty {
            parts.append("[Visible context on screen — use exact names, dates, facts and concepts from here]\n" + String(screen.suffix(screenBudget)))
        }
        if let fields, !fields.isEmpty {
            parts.append("[Other fields of this window — keep facts like dates, numbers, titles and names consistent]\n" + String(fields.prefix(520)))
        }
        if let memory, !memory.isEmpty {
            parts.append("[Earlier, the author wrote (background — mention only if relevant)]\n" + String(memory.prefix(520)))
        }
        if let audio, !audio.isEmpty {
            parts.append("[Live audio & call transcript — continue with the concepts, names and topics mentioned here]\n"
                         + String(audio.suffix(600))
                         + "\n[Continue using the exact names, topics and facts just spoken]")
        }
        guard !parts.isEmpty else { return "" }
        let app = appName.isEmpty ? "" : " (\(appName))"
        return parts.joined(separator: "\n\n") + "\n\n[Draft\(app)]\n"
    }

    // MARK: Facts copied from the context

    /// When the end of the draft repeats a span of a context source ("dal 19 al" while the subject says
    /// "dal 19 al 23", or a phrase from a book on screen), returns how that span continues in the source.
    static func contextContinuation(prefix: String, sources: [String], strict: [String] = [],
                                    userEndedWithSpace: Bool, maxWords: Int = 6) -> String? {
        let tail = collapse(String(prefix.suffix(120)))
        guard tail.count >= 4 else { return nil }
        // Candidate starts at word boundaries, longest first (up to 8 words back).
        var starts: [String.Index] = []
        var i = tail.endIndex
        while i > tail.startIndex, starts.count < 8 {
            i = tail.index(before: i)
            if i == tail.startIndex || tail[tail.index(before: i)] == " " {
                if tail[i] != " " { starts.append(i) }
            }
        }
        for start in starts.reversed() {
            let needle = String(tail[start...]).trimmingCharacters(in: .whitespaces)
            let words = needle.split(separator: " ").count
            let hasDigit = needle.contains(where: { $0.isNumber })
            guard words >= 2, needle.count >= 6 else { continue }
            let genericFiller: Set<String> = ["grazie", "perché", "quindi", "questo", "questa", "essere", "ancora", "sempre"]
            let hasStudyTerm = needle.split(separator: " ").contains { w in
                let clean = w.trimmingCharacters(in: .punctuationCharacters).lowercased()
                return clean.count >= 6 && !genericFiller.contains(clean)
            }
            let strongForSources = (hasDigit && words >= 2) || (words >= 4 && needle.count >= 16) || (hasStudyTerm && words >= 2 && needle.count >= 10)
            let strongForStrict = (hasDigit && words >= 2) || (words >= 3 && needle.count >= 14)
            if strongForSources {
                for source in sources {
                    if let cont = continuation(of: needle, in: collapse(source),
                                               userEndedWithSpace: userEndedWithSpace, maxWords: maxWords) {
                        return cont
                    }
                }
            }
            if strongForStrict, words >= 4 {
                for source in strict {
                    if let cont = continuation(of: needle, in: collapse(source),
                                               userEndedWithSpace: userEndedWithSpace, maxWords: maxWords) {
                        return cont
                    }
                }
            }
        }
        return nil
    }

    private static func continuation(of needle: String, in source: String,
                                     userEndedWithSpace: Bool, maxWords: Int) -> String? {
        var searchFrom = source.startIndex
        while let r = source.range(of: needle, options: [.caseInsensitive], range: searchFrom..<source.endIndex) {
            searchFrom = r.upperBound
            // The match must start at a word boundary in the source too.
            if r.lowerBound > source.startIndex, source[source.index(before: r.lowerBound)].isLetter
                || (r.lowerBound > source.startIndex && source[source.index(before: r.lowerBound)].isNumber) { continue }
            var rest = Substring(source[r.upperBound...])
            if rest.isEmpty { continue }
            // After a typed space the source must start a new word there too; otherwise it may finish the
            // current word ("dal 19 al 2" → "3"), start the next one (" 23") or add punctuation.
            if userEndedWithSpace {
                guard rest.first == " " else { continue }
                rest = rest.drop(while: { $0 == " " })
            }
            // Up to the end of the clause, at most `maxWords` words.
            var out = ""
            var count = 0
            var inWord = false
            for ch in rest {
                if ch == "\n" { break }
                if ch == " " {
                    if inWord { count += 1; inWord = false }
                    if count >= maxWords { break }
                } else {
                    inWord = true
                }
                out.append(ch)
                if ".!?;".contains(ch) { break }
            }
            while let last = out.last, last == " " || last == "," || last == ":" || last == "-" { out.removeLast() }
            guard out.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            return out
        }
        return nil
    }

    private static func collapse(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var space = false
        for ch in s {
            if ch == "\n" || ch == "\r" { out.append("\n"); space = false; continue }
            if ch.isWhitespace { if !space { out.append(" ") }; space = true; continue }
            space = false
            out.append(ch)
        }
        return out
    }

    // MARK: Smart Tab

    /// True when Tab should keep its normal meaning (indent): the caret is at the start of a line,
    /// or right after a list marker ("- ", "* ", "1. ", "- [ ] ") in Markdown editors like Obsidian.
    static func isIndentPosition(_ prefix: String) -> Bool {
        let prefix = normalizeSpaces(prefix)
        let line = prefix.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? prefix
        guard !prefix.isEmpty else { return false }
        let t = line.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        // Only whitespace on the line so far: already indenting (a plain empty line keeps Tab = accept,
        // e.g. a new line in a chat box).
        if t.isEmpty { return !line.isEmpty }
        let markers: Set<String> = ["-", "*", "+", "•", "- [ ]", "- [x]", "- [X]", "* [ ]", "* [x]", ">"]
        if markers.contains(t), line.hasSuffix(" ") || line.hasSuffix("\t") { return true }
        // "1." / "12)" ordered list markers.
        if line.hasSuffix(" "), t.count <= 4, let last = t.last, last == "." || last == ")",
           t.dropLast().allSatisfy({ $0.isNumber }), !t.dropLast().isEmpty { return true }
        return false
    }

    /// Text about to be typed into another app: no control characters (tab and newline excepted) and no
    /// bidirectional overrides/isolates, which could make the inserted text display differently from what it is.
    static func safeForInsertion(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u.value {
            case 0x09, 0x0A: out.append(u)
            case 0xA0, 0x2007, 0x202F: out.append(" ")
            case 0x00..<0x20, 0x7F, 0x80..<0xA0, 0x202A...0x202E, 0x2066...0x2069: continue
            default: out.append(u)
            }
        }
        return String(out)
    }

    // MARK: Context labels

    /// Pieces of the context block or chat-template markers that a model copies into its output when it runs out of ideas.
    private static let contextMarkers = ["Draft (", "Visible context", "Author profile", "writing samples",
                                         "Other fields of this window", "Earlier, the author", "How the author writes",
                                         "Live lecture", "Live audio", "<|im_end|>", "<|im_start|>", "<|endoftext|>",
                                         "<end_of_turn>", "<start_of_turn>", "\nUser:", "\nAssistant:"]

    /// Cuts the output where it starts reproducing the context block ("[Draft (Mail)]", "Visible context…").
    static func cutAtContextLabel(_ s: String) -> String {
        var cuts = contextMarkers.compactMap { s.range(of: $0)?.lowerBound }
        var i = s.startIndex
        while let open = s[i...].firstIndex(of: "[") {   // "[" + capital letter: a block heading
            let next = s.index(after: open)
            if next < s.endIndex, s[next].isUppercase { cuts.append(open); break }
            i = next
        }
        guard let cut = cuts.min() else { return s }
        return String(s[..<cut])
    }

    /// A candidate that is a context label, or the app's name when the draft never mentions it.
    static func isContextLabel(_ s: String, appName: String, draft: String) -> Bool {
        if s.contains("[") || s.contains("]") || cutAtContextLabel(s) != s { return true }
        let app = appName.lowercased(), lower = s.lowercased()
        return !app.isEmpty && lower.contains(app) && !draft.lowercased().contains(app)
    }

    /// Cleans up raw model output into what we show as ghost text.
    static func clean(_ raw: String, userEndedWithSpace: Bool, truncated: Bool, prefix: String = "") -> String {
        var s = normalizeSpaces(cutAtContextLabel(raw))
        if userEndedWithSpace {
            // The user already typed the space; the model must start a new word.
            guard let first = s.first, isHorizontalSpace(first) else { return "" }
            while let first = s.first, isHorizontalSpace(first) { s.removeFirst() }
            // …never a punctuation mark: that would produce "parola ," / "parola ." in the document.
            if let f = s.first, closingPunctuation.contains(f) { return "" }
        } else if let f = s.first, isSpace(f), let second = s.dropFirst().first(where: { !isSpace($0) }),
                  closingPunctuation.contains(second) {
            // " , come stai" after "ciao": the comma attaches to the word.
            s = String(s.drop(while: isSpace))
        }
        // "ciao , come" -> "ciao, come" anywhere inside the suggestion (preserving emoticons & French spacing).
        let isFrench = prefix.contains("«") || prefix.contains("ç") || Spelling.markerLanguage(of: String(prefix.suffix(120))) == "fr"
        s = gluePunctuation(s, french: isFrench)
        // Drop a half-generated last word when we hit the token limit.
        if truncated, let lastSpace = s.lastIndex(where: { $0.isWhitespace }),
           s[s.index(after: lastSpace)...].count > 0,
           s[..<lastSpace].contains(where: { !$0.isWhitespace }) {
            s = String(s[..<lastSpace])
        }
        // No cut at commas or sentence ends: the suggestion flows on into the next clause/sentence and
        // *you* decide where to stop (keep typing, or Esc). Length is bounded by the completion length.
        // Strip any 3-word phrase that repeats the recent prefix or an earlier part of the suggestion.
        s = stripRepeatedPhrase(s, prefix: prefix)
        // A new sentence starts with a word: after ". " reject filler like "(10:00) (1) (2)" that base
        // models emit when the message is over. ("alle ore⟨ 15.00⟩" is fine: no period before it.)
        if let end = prefix.last(where: { !$0.isWhitespace }), ".!?".contains(end), !s.contains(where: { $0.isLetter }) {
            return ""
        }
        while let last = s.last, last.isWhitespace { s.removeLast() }
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return "" }
        return s
    }

    /// Cuts `s` right before any 3-word phrase that already appeared in `prefix.suffix(220)` or earlier in `s`.
    private static func stripRepeatedPhrase(_ s: String, prefix: String) -> String {
        let recent = normWords(String(prefix.suffix(220)))
        var seenTrigrams = Set<String>()
        if recent.count >= 3 {
            for i in 0...(recent.count - 3) {
                let tri = "\(recent[i]) \(recent[i + 1]) \(recent[i + 2])"
                if tri.count >= 10 { seenTrigrams.insert(tri) }
            }
        }
        // Tokenize `s` with character ranges so we can slice `s` cleanly if a repeated trigram starts.
        var spans: [(word: String, start: String.Index)] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            while idx < s.endIndex, s[idx].isWhitespace { idx = s.index(after: idx) }
            guard idx < s.endIndex else { break }
            let start = idx
            while idx < s.endIndex, !s[idx].isWhitespace { idx = s.index(after: idx) }
            let w = s[start..<idx].lowercased().trimmingCharacters(in: .punctuationCharacters)
            if !w.isEmpty { spans.append((w, start)) }
        }
        guard spans.count >= 3 else { return s }
        for i in 0...(spans.count - 3) {
            let tri = "\(spans[i].word) \(spans[i + 1].word) \(spans[i + 2].word)"
            guard tri.count >= 10 else { continue }
            if !seenTrigrams.insert(tri).inserted {
                var cut = spans[i].start
                // Also drop a dangling conjunction ("e", "o", "ma", "che") right before the repeated phrase.
                if i > 0, ["e", "ed", "o", "ma", "che"].contains(spans[i - 1].word) {
                    cut = spans[i - 1].start
                }
                var out = String(s[..<cut])
                while let last = out.last, last.isWhitespace || last == "," { out.removeLast() }
                return out
            }
        }
        return s
    }

    private static func normWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }

    /// Punctuation that closes a word/clause and must never follow a space.
    static let closingPunctuation: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "…"]

    /// "ciao , come" -> "ciao, come" (keeps "...", emoticons ":)", and French spacing before !?:;).
    private static func gluePunctuation(_ s: String, french: Bool = false) -> String {
        guard s.contains(" ") else { return s }
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(s.count)
        var pendingSpaces = ""
        for (idx, ch) in chars.enumerated() {
            if ch == " " { pendingSpaces.append(ch); continue }
            if !pendingSpaces.isEmpty {
                let next = idx + 1 < chars.count ? chars[idx + 1] : nil
                let isEmoticon = (ch == ":" || ch == ";") && (next == ")" || next == "(" || next == "D" || next == "P" || next == "-")
                let isFrenchTwoPart = french && (ch == "!" || ch == "?" || ch == ":" || ch == ";")
                if !(closingPunctuation.contains(ch) && !out.isEmpty && !isEmoticon && !isFrenchTwoPart) {
                    out += pendingSpaces
                }
                pendingSpaces = ""
            }
            out.append(ch)
        }
        return out + pendingSpaces
    }

    /// Splits the suggestion into the next word and the rest.
    /// Punctuation glued to a word is never inserted together with it: "ciao," takes two presses
    /// ("ciao", then ","), so a comma or period you don't want is simply not accepted — keep typing instead.
    static func splitNextWord(_ s: String, trailingSpace: Bool) -> (word: String, rest: String) {
        var i = s.startIndex
        while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
        let wordStart = i
        while i < s.endIndex, !s[i].isWhitespace { i = s.index(after: i) }
        // Back off trailing punctuation unless the "word" is only punctuation (then it's its own step).
        var j = i
        while j > wordStart, s[s.index(before: j)].isPunctuation, !"'’".contains(s[s.index(before: j)]),
              !isInnerPunctuation(s, j) { j = s.index(before: j) }
        if j > wordStart { i = j }
        var word = String(s[..<i])
        var rest = String(s[i...])
        if trailingSpace {
            if let first = rest.first, isSpace(first) { word += " "; rest.removeFirst() }
            else if rest.isEmpty { word += " " }
        }
        return (word, rest)
    }

    /// Punctuation that belongs to the word itself, not to the sentence: closing quotes/brackets that pair
    /// with an opening one inside the word ("(ok)", "\"ciao\"") stay attached.
    private static func isInnerPunctuation(_ s: String, _ end: String.Index) -> Bool {
        let ch = s[s.index(before: end)]
        let pairs: [Character: Character] = [")": "(", "\"": "\"", "»": "«", "”": "“", "]": "["]
        guard let open = pairs[ch] else { return false }
        var k = s.index(before: end)
        while k > s.startIndex {
            k = s.index(before: k)
            if s[k].isWhitespace { return false }
            if s[k] == open { return true }
        }
        return false
    }

    /// Mid-line suggestions stay short and must not repeat the text already after the caret.
    static func trimForMidLine(_ s: String, after: String) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: false)
        var out = words.prefix(5).joined(separator: " ")
        while let last = out.last, last.isWhitespace { out.removeLast() }
        let next = after.trimmingCharacters(in: .whitespaces).lowercased()
        let mine = out.trimmingCharacters(in: .whitespaces).lowercased()
        if mine.isEmpty || (!next.isEmpty && next.hasPrefix(mine)) || (next.count >= 3 && mine.hasPrefix(next)) { return "" }
        return out
    }

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Automatic suggestions start after two typed characters, so nothing is drawn over an empty field's placeholder,
    /// and wait while a link is still being typed (a space after it ends the link).
    static func hasEnoughText(_ prefix: String) -> Bool {
        !isInsideURL(prefix) && prefix.filter { !$0.isWhitespace }.count >= 2 && prefix.contains(where: { $0.isLetter })
    }
}
