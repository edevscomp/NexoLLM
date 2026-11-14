import AppKit
import Carbon.HIToolbox
import XCTest
@testable import NexoLLM

final class WritingQualityTests: XCTestCase {
    // MARK: Token healing

    func testHealSplitTakesTheHalfTypedWordWithItsSpace() {
        let r = SuggestionText.healSplit("Questo è un idiom")
        XCTAssertEqual(r?.stem, "Questo è un")
        XCTAssertEqual(r?.heal, " idiom")
    }

    func testHealSplitAtLineStartKeepsNoSpace() {
        let r = SuggestionText.healSplit("[Draft]\nidiom")
        XCTAssertEqual(r?.stem, "[Draft]\n")
        XCTAssertEqual(r?.heal, "idiom")
    }

    func testNoHealingOutsideAWord() {
        XCTAssertNil(SuggestionText.healSplit("Hello there "))
        XCTAssertNil(SuggestionText.healSplit("Hello there,"))
        XCTAssertNil(SuggestionText.healSplit("meet at 3pm"))
        XCTAssertNil(SuggestionText.healSplit("word"))   // nothing before it to condition on
    }

    // MARK: Word alternatives

    func testFirstWordCompletesTheTypedWord() {
        XCTAssertEqual(SuggestionText.firstWord(partial: "idiom", continuation: "a del posto"), "idioma")
        XCTAssertNil(SuggestionText.firstWord(partial: "idiom", continuation: " del posto"))   // unchanged
        XCTAssertEqual(SuggestionText.firstWord(partial: "", continuation: " tomorrow morning"), "tomorrow")
        XCTAssertEqual(SuggestionText.firstWord(partial: "", continuation: " l'altro giorno"), "l'altro")
        XCTAssertNil(SuggestionText.firstWord(partial: "", continuation: " 42 days"))
    }

    // MARK: Spelling

    func testNearMissRules() {
        XCTAssertTrue(Spelling.isNearMiss("recieve", "receive"))      // transposition
        XCTAssertTrue(Spelling.isNearMiss("perche", "perché"))        // accent only
        XCTAssertTrue(Spelling.isNearMiss("teh", "the"))
        XCTAssertFalse(Spelling.isNearMiss("cat", "bat"))             // different first letter
        XCTAssertFalse(Spelling.isNearMiss("house", "horseman"))      // too far
    }

    func testEditDistance() {
        XCTAssertEqual(Spelling.editDistance(Array("ab"), Array("ba")), 1)
        XCTAssertEqual(Spelling.editDistance(Array("kitten"), Array("sitting")), 3)
    }

    // MARK: Secrets never reach the disk

    func testScrubberCatchesSecrets() {
        for s in ["my key is sk-proj-abcdefghijklmnop1234", "token ghp_abcdefghijklmnopqrstuvwx12",
                  "AKIAIOSFODNN7EXAMPLE is the id", "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9abcdef",
                  "password: hunter22", "Password = abc", "la password è Gatto2024!",
                  "card 4111 1111 1111 1111 exp 12/29", "IBAN IT60X0542811101000000123456",
                  "-----BEGIN OPENSSH PRIVATE KEY-----"] {
            XCTAssertTrue(SecretScrubber.containsSecret(s), s)
        }
    }

    func testLogRedactsQuotedText() {
        XCTAssertEqual(Log.redact("complete: 85ms Notes shown=\" tonight\""), "complete: 85ms Notes shown=<8 chars>")
        XCTAssertEqual(Log.redact("fields: \"a \\\"b\\\"\" and \"c\""), "fields: <7 chars> and <1 chars>")
        XCTAssertEqual(Log.redact("engine: ready"), "engine: ready")
    }

    // MARK: Context labels never reach the user

    func testContextLabelsAreFiltered() {
        XCTAssertTrue(SuggestionText.isContextLabel("WhatsApp Draft", appName: "WhatsApp", draft: "ci vediamo domani"))
        XCTAssertFalse(SuggestionText.isContextLabel("WhatsApp", appName: "WhatsApp", draft: "scrivimi su whatsapp"))
        XCTAssertTrue(SuggestionText.isContextLabel("[Draft (Notes)]", appName: "Notes", draft: "hello"))
        XCTAssertTrue(SuggestionText.isContextLabel("Visible context on screen", appName: "Mail", draft: "hello"))
        XCTAssertFalse(SuggestionText.isContextLabel("tonight", appName: "Mail", draft: "I'll send it"))
        XCTAssertFalse(SuggestionText.isContextLabel("draft", appName: "Mail", draft: "the first"))
    }

    func testCleanCutsCopiedContextBlock() {
        XCTAssertEqual(SuggestionText.clean(" tonight [Draft (Mail)] hello", userEndedWithSpace: false, truncated: false), " tonight")
        XCTAssertEqual(SuggestionText.clean(" see you\n[Visible context on screen]", userEndedWithSpace: false, truncated: false), " see you")
        XCTAssertEqual(SuggestionText.clean(" - [ ] buy milk", userEndedWithSpace: false, truncated: false), " - [ ] buy milk")
    }

    // MARK: Empty fields

    func testPlaceholderIsNotText() {
        XCTAssertEqual(AX.withoutPlaceholder(prefix: "", after: "Search or enter website name", placeholder: "Search or enter website name").prefix, "")
        XCTAssertEqual(AX.withoutPlaceholder(prefix: "Search or enter website name", after: "", placeholder: "Search or enter website name").after, "")
        XCTAssertEqual(AX.withoutPlaceholder(prefix: "Search", after: "", placeholder: "Search or enter website name").prefix, "Search")
        XCTAssertEqual(AX.withoutPlaceholder(prefix: "ciao", after: "", placeholder: nil).prefix, "ciao")
    }

    func testAutomaticSuggestionsNeedTwoCharacters() {
        XCTAssertFalse(SuggestionText.hasEnoughText("C"))
        XCTAssertFalse(SuggestionText.hasEnoughText("  \n"))
        XCTAssertTrue(SuggestionText.hasEnoughText("Ci"))
    }

    // MARK: Updates

    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("0.4.0", than: "0.3.0"))
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.2"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(Updater.isNewer("0.3.0", than: "0.3.0"))
        XCTAssertFalse(Updater.isNewer("0.3.0", than: "0.4.0"))
        XCTAssertFalse(Updater.isNewer("9.9.9", than: "dev"))
    }

    func testReleaseParsingPrefersStableDMG() {
        let json = #"{"tag_name":"v0.4.0","assets":[{"name":"NexoLLM-0.4.0.zip","browser_download_url":"https://github.com/x/a.zip"},{"name":"NexoLLM-0.4.0.dmg","browser_download_url":"https://github.com/x/v.dmg"},{"name":"NexoLLM.dmg","browser_download_url":"https://github.com/x/s.dmg"}]}"#
        let r = Updater.parse(Data(json.utf8))
        XCTAssertEqual(r?.version, "0.4.0")
        XCTAssertEqual(r?.dmg.absoluteString, "https://github.com/x/s.dmg")
        XCTAssertNil(Updater.parse(Data(#"{"tag_name":"v1.0.0","assets":[]}"#.utf8)))
        // Downloads only over HTTPS from GitHub.
        XCTAssertNil(Updater.parse(Data(#"{"tag_name":"v9.0.0","assets":[{"name":"NexoLLM.dmg","browser_download_url":"https://evil.example/s.dmg"}]}"#.utf8)))
        XCTAssertNil(Updater.parse(Data(#"{"tag_name":"v9.0.0","assets":[{"name":"NexoLLM.dmg","browser_download_url":"http://github.com/s.dmg"}]}"#.utf8)))
    }

    func testSecurityGuards() {
        // Result cards open only web pages.
        XCTAssertTrue(WebLookup.isWebLink(URL(string: "https://it.wikipedia.org/wiki/Palestina")!))
        XCTAssertFalse(WebLookup.isWebLink(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(WebLookup.isWebLink(URL(string: "javascript:alert(1)")!))
        XCTAssertFalse(WebLookup.isWebLink(URL(string: "x-apple.systempreferences:com.apple.preference.security")!))
        let rss = "<item><title>Evil - X</title><link>file:///Users/me/secret.txt</link></item><item><title>Ok - Y</title><link>https://example.com/a</link></item>"
        XCTAssertEqual(WebLookup.parseRSS(rss).map(\.url.absoluteString), ["https://example.com/a"])
        // Passwords copied from a password manager are never used.
        XCTAssertTrue(Pasteboards.isSensitive(types: [.string, Pasteboards.concealed]))
        XCTAssertTrue(Pasteboards.isSensitive(types: [.string, NSPasteboard.PasteboardType("com.agilebits.onepassword")]))
        XCTAssertFalse(Pasteboards.isSensitive(types: [.string, .rtf]))
        // A name is never "corrected" into a greeting.
        XCTAssertNil(Spelling.typoMap["caio"])
        XCTAssertGreaterThan(WebLookup.maxQueryLength, 50)
    }

    func testChangelogSection() {
        let md = "# Changelog\n\n## [0.4.0] - 2026-11-02\n\n### New\nArrow keys.\n\n## [0.3.0] - 2026-10-30\n\nOld."
        XCTAssertEqual(WhatsNew.section("0.4.0", in: md), "### New\nArrow keys.")
        XCTAssertEqual(WhatsNew.section("0.3.0", in: md), "Old.")
        XCTAssertNil(WhatsNew.section("0.5.0", in: md))
    }

    func testScrubberLeavesProseAlone() {
        for s in ["Ci vediamo domani alle 19 per parlare della password policy del team",
                  "Call me at 333 123 4567 tonight", "Order 1234567890123 shipped",
                  "The meeting moved to 2026-11-04, see you there", "Il mio token preferito è il gatto"] {
            XCTAssertFalse(SecretScrubber.containsSecret(s), s)
        }
    }

    // MARK: Overlays

    /// An overlay must never be on screen while transparent (Tab would accept a suggestion nobody sees).
    @MainActor
    func testFloatingPanelNeverGoesTransparent() {
        let panel = FloatingPanel(clickThrough: true)
        let f = NSRect(x: 100, y: 100, width: 120, height: 24)
        XCTAssertFalse(panel.canHide)
        panel.place(f)
        XCTAssertEqual(panel.alphaValue, 1)
        panel.hide()
        XCTAssertEqual(panel.alphaValue, 1)
        panel.place(f)
        panel.place(f.offsetBy(dx: 4, dy: 0))
        XCTAssertEqual(panel.alphaValue, 1)
        panel.hide()
    }

    /// ↑/↓ wrap around, and hiding always clears the list/menu so no later key is swallowed by a ghost.
    @MainActor
    func testListAndQuickMenuNavigateAndDismissCleanly() {
        let rect = CGRect(x: 200, y: 200, width: 0, height: 16)
        let list = ListOverlay()
        list.showLoading(header: "Alternatives", belowAX: rect, scope: .word)
        XCTAssertTrue(list.loading)
        list.show(header: "Alternatives", items: ["a", "b", "c"].map { ListItem(leading: "", title: $0) }, belowAX: rect)
        XCTAssertFalse(list.loading)
        list.moveSelection(-1)
        XCTAssertEqual(list.selectedIndex, 2)
        list.moveSelection(1)
        XCTAssertEqual(list.selectedIndex, 0)
        list.hide()
        XCTAssertFalse(list.isVisible)
        XCTAssertFalse(list.loading)
        XCTAssertTrue(list.items.isEmpty)

        let menu = QuickMenuOverlay()
        let items = ["One", "Two"].map { QuickMenuItem(symbol: "circle", title: $0) {} }
        menu.show(status: "Ready", statusColor: .green, words: 0, items: items, topLeft: NSPoint(x: 300, y: 600))
        menu.moveSelection(1)
        XCTAssertEqual(menu.selectedIndex, 1)
        menu.moveSelection(1)
        XCTAssertEqual(menu.selectedIndex, 0)
        menu.hide()
        XCTAssertFalse(menu.isVisible)
        XCTAssertTrue(menu.items.isEmpty)
    }

    func testScreenPreviewIsTheNewestNonEmptyCapture() {
        XCTAssertNil(ScreenContext.newest([]))
        let old = ScreenContext.Snapshot(text: "old", date: Date(timeIntervalSinceNow: -60), caret: 0, caretY: 0)
        let blank = ScreenContext.Snapshot(text: "", date: Date(), caret: 0, caretY: 0)
        XCTAssertEqual(ScreenContext.newest([old, blank])?.text, "old")
    }

    func testRewriteOutputStopsAtTheClosingQuote() {
        XCTAssertEqual(CompletionController.rewriteResult("Hello there.\" and more"), "Hello there.")
        XCTAssertEqual(CompletionController.rewriteResult("  Ciao  "), "Ciao")
        XCTAssertNil(CompletionController.rewriteResult("\""))
        XCTAssertNil(CompletionController.rewriteResult(nil))
    }

    func testKeyClickSoundIsTheBundledWAV() {
        let wav = KeyClickSound.wavData
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.subdata(in: 8..<12), encoding: .ascii), "WAVE")
        XCTAssertGreaterThan(wav.count, 1_500)
        XCTAssertTrue(wav.dropFirst(44).contains { $0 != 0 })
    }

    func testAcceptAllDefaultsToShiftTab() {
        XCTAssertEqual(Prefs().fullCompletionShortcut, Shortcut(kVK_Tab, .maskShift))
    }

    func testWalkthroughScriptedFlow() {
        let tour = WalkthroughState(lang: .english)
        tour.clicks = false
        tour.animated = false
        XCTAssertEqual(WalkthroughState.stepCount, 9)
        XCTAssertFalse(tour.handle(code: 48, flags: [], characters: "\t"))   // welcome slide: keys pass through

        // Slide 2 opens pre-filled: only ⇥ and ⇧⇥, no typing.
        tour.step = WalkthroughState.Slide.autocomplete.rawValue
        XCTAssertEqual(tour.typed, "Hi Alex,")
        XCTAssertEqual(tour.ghost, " just following up on the launch timeline for Friday at 3 PM.")
        XCTAssertFalse(tour.handle(code: 0, flags: [], characters: "a"))     // letters are not captured
        XCTAssertTrue(tour.handle(code: 48, flags: [], characters: "\t"))    // ⇥ accepts one word
        XCTAssertEqual(tour.typed, "Hi Alex, just")
        XCTAssertTrue(tour.hasAcceptedOnce)
        XCTAssertTrue(tour.handle(code: 48, flags: .maskShift, characters: "\t"))   // ⇧⇥ accepts the rest…
        XCTAssertEqual(tour.typed, TourExamples.english.target)
        XCTAssertEqual(tour.ghost, TourExamples.english.followUp)                  // …and the next sentence follows
        XCTAssertFalse(tour.handle(code: 36, flags: [], characters: "\r"))   // ↩ goes to the Next button
        tour.reset()
        XCTAssertEqual(tour.typed, "Hi Alex,")
        XCTAssertFalse(tour.hasAcceptedOnce)

        tour.setLanguage(.italian)
        XCTAssertEqual(tour.typed, "Ciao Marco,")
        XCTAssertEqual(tour.ghost, " ti scrivo per confermare che ci vediamo domani alle 15.")

        tour.next()
        XCTAssertEqual(tour.slide, .alternatives)
        XCTAssertTrue(tour.handle(code: 124, flags: [], characters: nil))   // →
        XCTAssertEqual(tour.scope, .phrase)
        tour.move(-1)
        tour.pick()
        XCTAssertEqual(tour.chosen, TourExamples.italian.altPhrases[3])
        XCTAssertTrue(tour.handle(code: 123, flags: [], characters: nil))   // ←
        XCTAssertTrue(tour.handle(code: 19, flags: [], characters: "2"))
        XCTAssertEqual(tour.chosen, "venerdì")

        tour.next()
        XCTAssertTrue(tour.handle(code: 48, flags: [], characters: "\t"))   // memory: ⇥ accepts
        XCTAssertTrue(tour.memoryAccepted)
        tour.next()
        XCTAssertTrue(tour.handle(code: 20, flags: [], characters: "3"))    // rewrite: 3
        XCTAssertEqual(tour.rewrite, 2)
        tour.next()
        XCTAssertEqual(tour.slide, .webLookup)
        tour.next()
        XCTAssertEqual(tour.slide, .moreFeatures)
        tour.next()
        XCTAssertEqual(tour.slide, .done)
        tour.back()
        XCTAssertFalse(tour.forward)
    }

    func testAppLanguageSwitchesTheInterface() {
        let saved = Settings.shared.prefs.exampleLanguage
        defer { Settings.shared.prefs.exampleLanguage = saved }
        Settings.shared.prefs.exampleLanguage = .italian
        XCTAssertEqual(L("Language", "Lingua"), "Lingua")
        XCTAssertEqual(SettingsPane.general.title, "Comportamento")
        XCTAssertEqual(Fmt.status("Ready · model.gguf"), "Pronto · model.gguf")
        Settings.shared.prefs.exampleLanguage = .english
        XCTAssertEqual(L("Language", "Lingua"), "Language")
        XCTAssertEqual(Fmt.status("Ready · model.gguf"), "Ready · model.gguf")

        // System autocorrect example uses the localized "hello/ciao" greeting in every supported language.
        let expectedGreetings: [ExampleLanguage: String] = [
            .english: "hello", .italian: "ciao", .spanish: "hola",
            .french: "salut", .german: "hallo", .portuguese: "olá",
        ]
        for (lang, greeting) in expectedGreetings {
            Settings.shared.prefs.exampleLanguage = lang
            let desc = L("The blue bubble that replaces a word as you type (\"helo\" → \"hello\"). NexoLLM suggests its own fixes, so you can turn this off too.",
                         "Il fumetto blu che sostituisce una parola mentre scrivi (\"cao\" → \"ciao\"). NexoLLM propone già le sue correzioni, quindi puoi disattivare anche questo.")
            XCTAssertTrue(desc.lowercased().contains(greeting), "Expected \(greeting) in \(lang): \(desc)")
        }

        // ModalCenter can open and cancel/close BugReport even without typing
        ModalCenter.shared.current = .bugReport
        XCTAssertEqual(ModalCenter.shared.current, .bugReport)
        ModalCenter.shared.current = nil
        XCTAssertNil(ModalCenter.shared.current)
    }

    func testMultilingualSpellingAndRewritePolish() {
        // Valid Spanish, Portuguese and English words must never be "corrected" by Italian accent/typo maps.
        XCTAssertNil(Spelling.correction(for: "pero", context: "Hola Lucía, quiero ir pero mañana"))
        XCTAssertNil(Spelling.correction(for: "sucesso", context: "Olá Sofia, o projeto foi um grande sucesso"))
        XCTAssertNil(Spelling.correction(for: "meta", context: "The project meta file is ready"))
        // Italian context still gets Italian accent/typo fixes.
        XCTAssertEqual(Spelling.correction(for: "perche", context: "Ciao Marco, ti scrivo perche domani"), "perché")

        // Multi-line rewrite prefix preservation.
        let bullet = CompletionController.splitLinePrefix("  - First action item")
        XCTAssertEqual(bullet.prefix, "  - ")
        XCTAssertEqual(bullet.body, "First action item")
        let numbered = CompletionController.splitLinePrefix("2) Second step")
        XCTAssertEqual(numbered.prefix, "2) ")
        XCTAssertEqual(numbered.body, "Second step")

        // Capitalization/punctuation polish preserves filenames, URLs and camelCase brands.
        let polished = CompletionController.polishCapitalizationAndPunctuation("please check config.json and iPhone settings")
        XCTAssertTrue(polished.hasPrefix("Please check config.json"))
        XCTAssertTrue(polished.contains("iPhone"))
        XCTAssertFalse(polished.contains("config. Json"))
    }

    func testLinksNeverBlockOrCorruptSuggestions() {
        XCTAssertNil(Spelling.currentWord("Check https://www.youtube.com/watch?v=B_KYRFKnELw"))
        XCTAssertNil(Spelling.currentWord("see example.com/pag"))
        XCTAssertEqual(Spelling.currentWord("Check this out, hel"), "hel")
        XCTAssertNil(Spelling.lastFinishedWord("Check https://github.com/example/project "))
        XCTAssertNil(SuggestionText.healSplit("visit https://example.com"))
        XCTAssertNil(SuggestionText.healSplit("visit https://youtu.be/abcdef"))
        XCTAssertFalse(SuggestionText.hasEnoughText("Look https://example.com"))   // still typing the link
        XCTAssertTrue(SuggestionText.hasEnoughText("Look https://example.com "))   // a space ends it
        let p = SuggestionText.prompt(prefix: "Guarda https://www.youtube.com/watch?v=B_KYRFKnELw ", prefixStart: 0, caretLocation: 51)
        XCTAssertEqual(p.text, "Guarda youtube.com")
        XCTAssertTrue(p.userEndedWithSpace)
        XCTAssertEqual(SuggestionText.normalizeLinks("read www.apple.com/mac, then"), "read apple.com, then")
        // A link before the caret, measured as one wide run, still places the caret at its end.
        let field = CGRect(x: 100, y: 100, width: 600, height: 300)
        let link = CGRect(x: 120, y: 120, width: 240, height: 18)
        XCTAssertEqual(CaretGeometry.choose(collapsed: nil, previous: link, previousIsSpace: false, field: field)?.minX, 360)
    }
}
