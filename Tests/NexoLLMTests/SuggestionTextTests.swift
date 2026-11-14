import XCTest
@testable import NexoLLM

final class SuggestionTextTests: XCTestCase {
    func testTrailingSpaceIsStrippedFromPrompt() {
        let p = SuggestionText.prompt(prefix: "Ciao come ", prefixStart: 0, caretLocation: 10)
        XCTAssertEqual(p.text, "Ciao come")
        XCTAssertTrue(p.userEndedWithSpace)
    }

    func testMidWordPromptKeptAsIs() {
        let p = SuggestionText.prompt(prefix: "Ciao co", prefixStart: 0, caretLocation: 7)
        XCTAssertEqual(p.text, "Ciao co")
        XCTAssertFalse(p.userEndedWithSpace)
    }

    func testPromptWindowIsStableWhileTyping() {
        let base = String(repeating: "parola ", count: 400)   // 2800 chars
        let a = SuggestionText.prompt(prefix: base, prefixStart: 0, caretLocation: (base as NSString).length)
        let typed = base + "nuo"
        let b = SuggestionText.prompt(prefix: typed, prefixStart: 0, caretLocation: (typed as NSString).length)
        XCTAssertTrue(b.text.hasPrefix(a.text), "window start moved -> KV cache would be invalidated")
    }

    func testCleanRequiresNewWordAfterUserSpace() {
        XCTAssertEqual(SuggestionText.clean(" stai oggi?", userEndedWithSpace: true, truncated: false), "stai oggi?")
        XCTAssertEqual(SuggestionText.clean("me stai", userEndedWithSpace: true, truncated: false), "")
    }

    func testCleanDropsCutLastWordWhenTruncated() {
        XCTAssertEqual(SuggestionText.clean(" confermare l'appunta", userEndedWithSpace: false, truncated: true),
                       " confermare")
        XCTAssertEqual(SuggestionText.clean(" confermare", userEndedWithSpace: false, truncated: true), " confermare")
    }

    func testCleanFlowsAcrossPunctuation() {
        // The suggestion no longer dies at a period or a comma: the user decides where to stop.
        XCTAssertEqual(SuggestionText.clean(" alle 15. Fammi sapere", userEndedWithSpace: false, truncated: false),
                       " alle 15. Fammi sapere")
        XCTAssertEqual(SuggestionText.clean(" ci vediamo domani, va bene", userEndedWithSpace: false, truncated: false),
                       " ci vediamo domani, va bene")
        XCTAssertEqual(SuggestionText.clean(" versione 2.5 del file", userEndedWithSpace: false, truncated: false),
                       " versione 2.5 del file")
    }

    func testSplitNextWord() {
        var r = SuggestionText.splitNextWord(" stai oggi?", trailingSpace: true)
        XCTAssertEqual(r.word, " stai ")
        XCTAssertEqual(r.rest, "oggi?")
        // Punctuation is always its own press.
        r = SuggestionText.splitNextWord("oggi?", trailingSpace: true)
        XCTAssertEqual(r.word, "oggi")
        XCTAssertEqual(r.rest, "?")
        r = SuggestionText.splitNextWord("?", trailingSpace: true)
        XCTAssertEqual(r.word, "? ")
        XCTAssertEqual(r.rest, "")
        r = SuggestionText.splitNextWord(" stai oggi", trailingSpace: false)
        XCTAssertEqual(r.word, " stai")
        XCTAssertEqual(r.rest, " oggi")
    }

    func testPunctuationNeedsItsOwnPress() {
        var r = SuggestionText.splitNextWord("ciao, come stai", trailingSpace: true)
        XCTAssertEqual(r.word, "ciao")
        XCTAssertEqual(r.rest, ", come stai")
        r = SuggestionText.splitNextWord(r.rest, trailingSpace: true)
        XCTAssertEqual(r.word, ", ")
        XCTAssertEqual(r.rest, "come stai")
        // Apostrophes belong to the word ("un po'"), paired brackets/quotes too.
        r = SuggestionText.splitNextWord(" po' di tempo", trailingSpace: true)
        XCTAssertEqual(r.word, " po' ")
        r = SuggestionText.splitNextWord(" (ok) dopo", trailingSpace: true)
        XCTAssertEqual(r.word, " (ok) ")
        r = SuggestionText.splitNextWord(" 15.00.", trailingSpace: true)
        XCTAssertEqual(r.word, " 15.00")
        XCTAssertEqual(r.rest, ".")
    }

    func testCleanNeverPutsPunctuationAfterASpace() {
        // The user typed "ciao " and the model wants a comma: that would be "ciao ,".
        XCTAssertEqual(SuggestionText.clean(" , come stai", userEndedWithSpace: true, truncated: false), "")
        XCTAssertEqual(SuggestionText.clean(" .", userEndedWithSpace: true, truncated: false), "")
        // No space typed: the comma attaches to the word.
        XCTAssertEqual(SuggestionText.clean(" , come stai", userEndedWithSpace: false, truncated: false), ", come stai")
        XCTAssertEqual(SuggestionText.clean(" a domani , ciao", userEndedWithSpace: false, truncated: false), " a domani, ciao")
    }

    func testContextContinuationCopiesFacts() {
        let subject = "Oggetto: Ferie dal 19 al 23 ottobre"
        XCTAssertEqual(SuggestionText.contextContinuation(prefix: "Ciao Marco, sarò in ferie dal 19 al", sources: [subject],
                                                          userEndedWithSpace: false), " 23 ottobre")
        XCTAssertEqual(SuggestionText.contextContinuation(prefix: "sarò via dal 19 al ", sources: [subject],
                                                          userEndedWithSpace: true), "23 ottobre")
        XCTAssertEqual(SuggestionText.contextContinuation(prefix: "sarò via dal 19 al 2", sources: [subject],
                                                          userEndedWithSpace: false), "3 ottobre")
        // Generic words alone are not a fact.
        XCTAssertNil(SuggestionText.contextContinuation(prefix: "grazie per la", sources: ["grazie per la pazienza"],
                                                        userEndedWithSpace: false))
        // A different number is a different fact.
        XCTAssertNil(SuggestionText.contextContinuation(prefix: "dal 18 al", sources: [subject], userEndedWithSpace: false))
        // Screen text needs a longer match.
        XCTAssertNil(SuggestionText.contextContinuation(prefix: "dal 19 al", sources: [], strict: [subject],
                                                        userEndedWithSpace: false))
        XCTAssertEqual(SuggestionText.contextContinuation(prefix: "in ferie dal 19 al", sources: [], strict: ["Ferie dal 19 al 23 ottobre"],
                                                          userEndedWithSpace: false), " 23 ottobre")
    }

    func testSmartTabIndentPositions() {
        XCTAssertTrue(SuggestionText.isIndentPosition("Lista:\n- "))
        XCTAssertTrue(SuggestionText.isIndentPosition("Cose:\n1. "))
        XCTAssertTrue(SuggestionText.isIndentPosition("Todo\n- [ ] "))
        XCTAssertTrue(SuggestionText.isIndentPosition("Testo\n    "))
        XCTAssertFalse(SuggestionText.isIndentPosition("Ciao\n"))          // plain new line (chat): Tab accepts
        XCTAssertFalse(SuggestionText.isIndentPosition("- primo punto e "))
        XCTAssertFalse(SuggestionText.isIndentPosition("ciao come "))
    }

    func testCleanRejectsLetterlessFillerAfterSentenceEnd() {
        XCTAssertEqual(SuggestionText.clean(" (10:00) (11:05)", userEndedWithSpace: true, truncated: false,
                                            prefix: "Grazie. Edoardo. "), "")
        XCTAssertEqual(SuggestionText.clean(" 15.00.", userEndedWithSpace: false, truncated: false,
                                            prefix: "La riunione è stata spostata alle ore"), " 15.00.")
        XCTAssertEqual(SuggestionText.clean(" Ti chiamo domani.", userEndedWithSpace: true, truncated: false,
                                            prefix: "Grazie. "), "Ti chiamo domani.")
    }

    func testCleanStripsRepeatedPhrasesFromPrefix() {
        let prefix = "Continuando col discorso di prima, la mia idea è che la gente non si rende conto di quanto sia importante la privacy, "
        let looped = " e che la gente non si rende conto di quanto sia importante la privacy"
        XCTAssertEqual(SuggestionText.clean(looped, userEndedWithSpace: true, truncated: false, prefix: prefix), "")

        let partialThenLoop = " soprattutto online e che la gente non si rende conto"
        XCTAssertEqual(SuggestionText.clean(partialThenLoop, userEndedWithSpace: true, truncated: false, prefix: prefix),
                       "soprattutto online")
    }

    func testSafeForInsertionDropsControlAndBidiCharacters() {
        XCTAssertEqual(SuggestionText.safeForInsertion(" ciao\u{0007} a\u{202E}tutti\u{2066}\n\tok"), " ciao atutti\n\tok")
        XCTAssertEqual(SuggestionText.safeForInsertion("perché 🙂"), "perché 🙂")
    }

    func testLectureAudioHeaderAndLabelStripping() {
        let h = SuggestionText.header(appName: "Obsidian", instructions: "", appInstructions: "",
                                      screen: nil, clipboard: nil, examples: [],
                                      audio: "Giacomo Leopardi nacque a Recanati nel 1798.")
        XCTAssertTrue(h.contains("[Live audio & call transcript"))
        XCTAssertTrue(h.contains("Giacomo Leopardi nacque a Recanati"))
        XCTAssertEqual(SuggestionText.cutAtContextLabel("nel 1798 [Live lecture / microphone transcript]"), "nel 1798 ")
    }

    func testWebLookupCleanQueryStripsConversationalPrefixes() {
        XCTAssertEqual(WebLookup.cleanQuery("sai cos'è successo oggi in Florida?"), "oggi in Florida?")
        XCTAssertEqual(WebLookup.cleanQuery("Do you know what happened in Tokyo today?"), "in Tokyo today?")
        XCTAssertEqual(WebLookup.cleanQuery("«Giacomo Leopardi»"), "Giacomo Leopardi")
    }

    func testMenuBarIconStatesProduceTemplateImages() {
        for state in [MenuBarIcon.State.active, .paused, .off, .loading, .reading, .error] {
            let img = MenuBarIcon.image(for: state)
            XCTAssertTrue(img.isTemplate)
            XCTAssertEqual(img.size.width, 18)
            XCTAssertEqual(img.size.height, 18)
        }
    }

    func testSpellingFixesItalianTrailingApostrophesAndSkipsShortWords() {
        XCTAssertEqual(Spelling.lastFinishedWord("Questo ha una alta probabilita' ")?.word, "probabilita'")
        XCTAssertEqual(Spelling.correction(for: "probabilita'", context: "Questo ha una alta probabilita' "), "probabilità")
        XCTAssertEqual(Spelling.correction(for: "probablita'", context: "Questo ha una alta probablita' "), "probabilità")
        XCTAssertEqual(Spelling.correction(for: "perche'", context: "Non capisco perche' "), "perché")
        // Short 4-letter word / slang must never be shortened to "sua"
        XCTAssertNil(Spelling.correction(for: "suca", context: "suca "))
    }

    func testContextContinuationMatchesTwoWordStudyPhrases() {
        let bookPage = "Giacomo Leopardi elabora la teoria del piacere nello Zibaldone tra il 1820 e il 1821."
        XCTAssertEqual(SuggestionText.contextContinuation(prefix: "Appunti: la teoria del",
                                                          sources: [bookPage],
                                                          userEndedWithSpace: false),
                       " piacere nello Zibaldone tra il 1820")
    }

    func testWebLookupDistinguishesQuestionsFromSingleWords() {
        XCTAssertFalse(WebLookup.isQuestionOrNews("grazie"))
        XCTAssertTrue(WebLookup.isQuestionOrNews("I prezzi della benzina aumenteranno in Italia?"))
        XCTAssertTrue(WebLookup.isQuestionOrNews("cos'è successo oggi in Florida"))
    }

    func testDraftTargetForRewriteWorksAtEndOfWordWithoutTrailingSpace() {
        // Single word right at the caret without a space
        let single = CompletionController.draftTargetForRewrite("probablita'")
        XCTAssertEqual(single?.text, "probablita'")
        XCTAssertEqual(single?.replaceCount, 11)
        XCTAssertEqual(single?.trailingWhitespace, "")

        // Full paragraph ending mid-word / end-of-word without a space
        let multi = CompletionController.draftTargetForRewrite("Prima frase. Ho un probablita'")
        XCTAssertEqual(multi?.text, "Prima frase. Ho un probablita'")
        XCTAssertEqual(multi?.replaceCount, 30)
        XCTAssertEqual(multi?.trailingWhitespace, "")

        // Paragraph with trailing space preserves trailingWhitespace and includes it in replaceCount
        let withSpace = CompletionController.draftTargetForRewrite("Ciao! Come va ")
        XCTAssertEqual(withSpace?.text, "Ciao! Come va")
        XCTAssertEqual(withSpace?.replaceCount, 14)
        XCTAssertEqual(withSpace?.trailingWhitespace, " ")

        // Spelling fix helper fixes the word right at the end even without trailing space
        XCTAssertEqual(CompletionController.applySpellingFixes(to: "probablita'", context: "Questa è una "), "probabilità")
    }

    @MainActor
    func testQuickMenuSubmenuExpansionAndShiftNumberActivation() {
        let exp = expectation(description: "subitem action")
        let menu = QuickMenuOverlay()
        var subTriggered = 0
        let sub1 = QuickMenuItem(symbol: "wand.and.stars", title: "Improve") { subTriggered = 1 }
        let sub2 = QuickMenuItem(symbol: "checkmark.seal", title: "Fix Grammar") {
            subTriggered = 2
            exp.fulfill()
        }
        let items = [
            QuickMenuItem(symbol: "wand.and.stars", title: "Writing Tools", subitems: [sub1, sub2]),
            QuickMenuItem(symbol: "circle.fill", title: "Disable in Terminal") {}
        ]
        menu.show(status: "Ready", statusColor: .green, words: 12, items: items, topLeft: NSPoint(x: 300, y: 600))
        XCTAssertFalse(menu.hasExpandedSubmenu)
        // Shift+2 before opening the dropdown does nothing
        menu.activateSubitem(1)
        XCTAssertEqual(subTriggered, 0)

        // Pressing 1 opens the Writing Tools dropdown without closing the menu
        menu.activate(0)
        XCTAssertTrue(menu.hasExpandedSubmenu)
        XCTAssertEqual(menu.expandedIndex, 0)

        // Now Shift+2 activates Fix Grammar (index 1)
        menu.activateSubitem(1)
        wait(for: [exp], timeout: 5.0)
        XCTAssertEqual(subTriggered, 2)
    }

    func testScreenSelectionSearchBarPositionMemoryExpiresAfterTenMinutes() {
        ScreenSelectionOverlay.resetBarOffset()
        let t0 = Date()
        ScreenSelectionOverlay.saveBarOffset(CGSize(width: 140, height: 85), now: t0)
        XCTAssertEqual(ScreenSelectionOverlay.currentBarOffset(now: t0.addingTimeInterval(300)), CGSize(width: 140, height: 85))
        // After 10 minutes (600 seconds), resets to .zero
        XCTAssertEqual(ScreenSelectionOverlay.currentBarOffset(now: t0.addingTimeInterval(601)), .zero)
    }

    @MainActor
    func testQuickMenuArrowNavigationWithNestedSubmenus() {
        let exp = expectation(description: "nested language action")
        var pickedLang = ""
        let langSubitems = [
            QuickMenuItem(symbol: "globe", title: "English") { pickedLang = "en" },
            QuickMenuItem(symbol: "globe", title: "Italiano") {
                pickedLang = "it"
                exp.fulfill()
            },
        ]
        let writingSubitems = [
            QuickMenuItem(symbol: "wand.and.stars", title: "Improve Writing"),
            QuickMenuItem(symbol: "checkmark.seal", title: "Fix Grammar"),
            QuickMenuItem(symbol: "globe", title: "Translate…", subitems: langSubitems),
        ]
        let menu = QuickMenuOverlay()
        menu.show(
            status: "Ready",
            statusColor: .green,
            words: 12,
            items: [
                QuickMenuItem(symbol: "wand.and.stars", title: "Writing Tools", subitems: writingSubitems),
                QuickMenuItem(symbol: "sparkle.magnifyingglass", title: "Smart Web Lookup"),
            ],
            topLeft: NSPoint(x: 200, y: 400)
        )
        defer { menu.hide() }

        XCTAssertEqual(menu.selectedIndex, 0)
        XCTAssertNil(menu.expandedIndex)
        XCTAssertNil(menu.selectedSubIndex)

        // Right arrow opens Writing Tools dropdown and selects subitem 0
        menu.expandRight()
        XCTAssertEqual(menu.expandedIndex, 0)
        XCTAssertEqual(menu.selectedSubIndex, 0)

        // Down arrow moves inside the open dropdown: 0 -> 1 -> 2 ("Translate…")
        menu.moveSelection(1)
        XCTAssertEqual(menu.selectedSubIndex, 1)
        menu.moveSelection(1)
        XCTAssertEqual(menu.selectedSubIndex, 2)

        // Right arrow on "Translate…" enters nested language submenu and selects index 0
        menu.expandRight()
        XCTAssertEqual(menu.items[0].subitems.count, 2)
        XCTAssertEqual(menu.selectedSubIndex, 0)

        // Left arrow exits nested language submenu back to Writing Tools at index 2 ("Translate…")
        menu.collapseLeft()
        XCTAssertEqual(menu.items[0].subitems.count, 3)
        XCTAssertEqual(menu.selectedSubIndex, 2)

        // Left arrow again closes Writing Tools dropdown back to top-level item 0
        menu.collapseLeft()
        XCTAssertNil(menu.expandedIndex)
        XCTAssertNil(menu.selectedSubIndex)
        XCTAssertEqual(menu.selectedIndex, 0)

        // Re-enter Writing Tools -> Translate… -> Italiano and activate with Return (`activateCurrent`)
        menu.expandRight()
        menu.moveSelection(2)
        menu.expandRight()
        menu.moveSelection(1)
        XCTAssertEqual(menu.selectedSubIndex, 1)
        menu.activateCurrent()

        wait(for: [exp], timeout: 5.0)
        XCTAssertEqual(pickedLang, "it")
    }

    func testBrandIdentityAndGitHubUsername() {
        XCTAssertEqual(Brand.author, "EdevS")
        XCTAssertEqual(Brand.website.absoluteString, "https://github.com/edevscomp/NexoLLM")
        XCTAssertEqual(Brand.websiteLabel, "github.com/edevscomp/NexoLLM")
        XCTAssertEqual(Brand.coffee.absoluteString, "https://buymeacoffee.com/edevs")
    }

    func testFullParagraphDraftTargetForRewrite() {
        let bio = "ciao mi chiamo Edoardo e sono un esperto di AI. Sono un ingegnere informatico e ho lavorato per 10 anni nel settore della sicurezza informatica."
        let target = CompletionController.draftTargetForRewrite(bio)
        XCTAssertEqual(target?.text, bio)
        XCTAssertEqual(target?.replaceCount, bio.count)
    }

    func testLanguageMatchedBuildRewritePromptAndTranslation() {
        let bio = "ciao mi chiamo Edoardo e sono un esperto di AI. Sono un ingegnere informatico e ho lavorato per 10 anni nel settore della sicurezza informatica."
        let fixGrammarPrompt = CompletionController.buildRewritePrompt(text: bio, instruction: "Fix grammar and spelling")
        XCTAssertTrue(fixGrammarPrompt.contains("italiano"))
        XCTAssertFalse(fixGrammarPrompt.contains("the report are ready"))

        let spanishPrompt = CompletionController.buildRewritePrompt(
            text: bio,
            instruction: "Translate into Español, keeping the exact meaning and tone"
        )
        XCTAssertTrue(spanishPrompt.contains("Español"))
        XCTAssertTrue(spanishPrompt.contains("El archivo está listo"))
    }

    func testPolishCapitalizationAndUnwantedLanguageSwitchGuard() {
        let polished = CompletionController.polishCapitalizationAndPunctuation("ciao mi chiamo Edoardo. sono un ingegnere.")
        XCTAssertEqual(polished, "Ciao, mi chiamo Edoardo. Sono un ingegnere.")

        let originalIT = "ciao mi chiamo Edoardo e sono un esperto di AI. Sono un ingegnere informatico e ho lavorato per 10 anni nel settore della sicurezza informatica."
        let mixedSpanglish = "Ciao, mi chiamo Edoardo e io sono un AI expert. Io un computer engineer e io ho worked for 10 years in the cybersecurity field."
        let translatedEN = "Hello, my name is Edoardo and I specialize in AI. I am an engineer with 10 years of experience in the cybersecurity field."
        let cleanIT = "Ciao, mi chiamo Edoardo e sono un esperto di IA. Sono un ingegnere informatico e ho lavorato per 10 anni nel settore della sicurezza informatica."

        XCTAssertTrue(CompletionController.hasUnwantedLanguageSwitch(original: originalIT, output: mixedSpanglish, instruction: "Fix grammar and spelling"))
        XCTAssertTrue(CompletionController.hasUnwantedLanguageSwitch(original: originalIT, output: translatedEN, instruction: "Improve clarity and flow"))
        XCTAssertFalse(CompletionController.hasUnwantedLanguageSwitch(original: originalIT, output: cleanIT, instruction: "Fix grammar and spelling"))
    }

    func testInstantLanguageDetectionWhileTyping() {
        let saved = Settings.shared.prefs.exampleLanguage
        defer { Settings.shared.prefs.exampleLanguage = saved }

        Settings.shared.prefs.exampleLanguage = .italian
        XCTAssertEqual(Spelling.detectedLanguageCode(for: "privacy inspector"), "en")

        Settings.shared.prefs.exampleLanguage = .english
        XCTAssertEqual(Spelling.detectedLanguageCode(for: "ciao mi chiamo Edoardo"), "it")
    }

    func testWebLookupIdiomAndRelevanceFilter() {
        XCTAssertFalse(WebLookup.isQuestionOrNews("avere il coltello fra i denti"))
        XCTAssertTrue(WebLookup.isQuestionOrNews("I prezzi della benzina aumenteranno in Italia?"))
        XCTAssertFalse(WebLookup.isRelevantNewsItem(title: "Scacchi, Luca Moroni vince il campionato italiano", forQuery: "avere il coltello fra i denti"))
        XCTAssertTrue(WebLookup.isRelevantNewsItem(title: "Prezzi della benzina in aumento in tutta Italia", forQuery: "prezzi della benzina in Italia"))
        XCTAssertEqual(WebLookup.queryLanguage("¿Qué está pasando hoy en Madrid?"), "es")
        XCTAssertEqual(WebLookup.queryLanguage("Qu'est-ce qui se passe aujourd'hui à Paris ?"), "fr")
        XCTAssertEqual(WebLookup.queryLanguage("Was passiert heute in Berlin und Deutschland?"), "de")
        XCTAssertEqual(WebLookup.queryLanguage("O que está a acontecer hoje em Lisboa?"), "pt")
    }

    func testScreenContextRelevantExcerptAcrossWindows() {
        let fullScreen = """
        [WhatsApp]
        Marco: Mi mandi un riassunto del capitolo sulla crittografia quantistica?
        ---
        [TextEdit — Appunti Libro]
        Capitolo 4: Crittografia quantistica e protocollo BB84
        Il protocollo BB84 utilizza stati di polarizzazione dei fotoni per distribuire una chiave segreta.
        Qualsiasi tentativo di intercettazione altera lo stato quantistico e viene rilevato immediatamente.
        """
        let excerpt = ScreenContext.relevantExcerpt(from: fullScreen, forDraft: "Ecco il riassunto sulla crittografia quantistica e il protocollo BB84:", budget: 350)
        XCTAssertTrue(excerpt.contains("BB84"))
        XCTAssertTrue(excerpt.contains("polarizzazione dei fotoni"))
    }

    func testMenuBarIconSmartScreenStates() {
        for state in [MenuBarIcon.State.active, .paused, .loading, .reading, .smartScreen, .readingScreen] {
            let img = MenuBarIcon.image(for: state)
            XCTAssertTrue(img.isTemplate)
            XCTAssertEqual(img.size.width, 18)
        }
    }

    @MainActor
    func testMenuBarIconAnimationsAndAnimatorLifecycle() {
        let pairs: [(MenuBarIcon.State, MenuBarIcon.State)] = [
            (.active, .paused), (.paused, .active), (.smartScreen, .paused), (.paused, .smartScreen),
            (.active, .smartScreen), (.off, .active), (.active, .off), (.loading, .active), (.reading, .active)
        ]
        for (from, to) in pairs {
            for p in [0.0, 0.25, 0.5, 0.75, 1.0] as [CGFloat] {
                let img = MenuBarIcon.transitionImage(from: from, to: to, progress: p)
                XCTAssertTrue(img.isTemplate)
                XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
            }
        }
        for state in [MenuBarIcon.State.active, .smartScreen] {
            for p in [0.0, 0.25, 0.5, 0.75, 1.0] as [CGFloat] {
                let img = MenuBarIcon.acceptPulseImage(for: state, progress: p)
                XCTAssertTrue(img.isTemplate)
                XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
            }
        }
        for state in [MenuBarIcon.State.loading, .reading, .readingScreen] {
            XCTAssertTrue(MenuBarAnimator.isLooping(state))
            for ph in [0.0, 0.9, 2.4] as [CGFloat] {
                let img = MenuBarIcon.animatedImage(for: state, phase: ph, level: 0.6)
                XCTAssertTrue(img.isTemplate)
                XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
            }
        }
        XCTAssertFalse(MenuBarAnimator.isLooping(.active))
        XCTAssertFalse(MenuBarAnimator.isLooping(.paused))
        XCTAssertFalse(MenuBarAnimator.isLooping(.off))

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        guard let btn = item.button else { return }
        let animator = MenuBarAnimator()
        animator.attach(btn)
        animator.setState(.active, dimmed: false, reduceMotion: false)
        XCTAssertFalse(animator.isAnimating)
        animator.setState(.paused, dimmed: false, reduceMotion: false)
        XCTAssertTrue(animator.isAnimating)
        animator.stop()
        XCTAssertFalse(animator.isAnimating)
        animator.setState(.loading, dimmed: false, reduceMotion: false)
        XCTAssertTrue(animator.isAnimating)
        animator.setState(.loading, dimmed: false, reduceMotion: true)
        XCTAssertFalse(animator.isAnimating)
    }

    func testAmbientGainRaisesQuietVoicesAndNeverBoostsSilence() {
        // Distant voice (≈ −40 dBFS): gain grows toward the target, capped.
        var g: Float = 4
        for _ in 0..<80 { g = AmbientGain.nextGain(current: g, rms: 0.01) }
        XCTAssertGreaterThan(g, 7.5)
        XCTAssertLessThanOrEqual(g, AmbientGain.maxGain)
        // Room noise below the floor: gain is held, never raised.
        XCTAssertEqual(AmbientGain.nextGain(current: 5, rms: 0.0001), 5)
        // Loud close speech: gain drops fast (fast attack) so nothing is distorted.
        XCTAssertLessThan(AmbientGain.nextGain(current: 12, rms: 0.3), 7)
    }

    func testAudioTranscriptCombinesRoomAndCallAndCutsAtWordBoundary() {
        let t = AudioContext.combine(committed: "prima parte", sys: "voce della call", mic: "voce in aula")
        XCTAssertEqual(t, "prima parte voce della call voce in aula")
        let long = AudioContext.combine(committed: String(repeating: "parola ", count: 200), sys: "", mic: "fine", limit: 50)
        XCTAssertLessThanOrEqual(long.count, 50)
        XCTAssertTrue(long.hasPrefix("parola"))
        XCTAssertTrue(long.hasSuffix("fine"))
    }

    func testTranslationMustBeInTheTargetLanguage() {
        let bio = "ciao mi chiamo Edoardo e sono un esperto di AI. Sono un ingegnere informatico e ho lavorato per 10 anni nel settore della sicurezza informatica."
        XCTAssertEqual(CompletionController.translationTarget("Translate this text into natural Spanish"), "es")
        XCTAssertNil(CompletionController.translationTarget("Fix grammar, spelling and punctuation only"))
        let spanish = "Hola, me llamo Edoardo y soy un experto en IA. Soy ingeniero informático y he trabajado durante 10 años en el sector de la ciberseguridad."
        XCTAssertFalse(CompletionController.hasUnwantedLanguageSwitch(original: bio, output: spanish, instruction: "Translate this text into natural Spanish"))
        // The model returned Italian/itanglese instead of Spanish: rejected.
        let mixed = "Ciao, mi chiamo Edoardo e io sono un AI expert. Io un computer engineer e io ho worked for 10 years in the cybersecurity field."
        XCTAssertTrue(CompletionController.hasUnwantedLanguageSwitch(original: bio, output: mixed, instruction: "Translate this text into natural Spanish"))
    }

    func testMakeFormalUsesTheFormalPrompt() {
        let p = CompletionController.buildRewritePrompt(text: "ciao ti mando il file dopo", instruction: "Rewrite in a formal, polite and professional tone in the same language")
        XCTAssertTrue(p.contains("Formale:"))
    }

    func testDominantLanguageReadsTheWholeText() {
        XCTAssertEqual(Spelling.dominantLanguageCode(of: "ciao mi chiamo Edoardo e sono un esperto di AI. Sono un ingegnere informatico."), "it")
        XCTAssertEqual(Spelling.dominantLanguageCode(of: "Hello, my name is Edoardo and I am an engineer with ten years of experience."), "en")
    }

    // MARK: PLAN_V17

    func testFixGrammarSingleWordTypoXciaoRecognizesItalian() {
        let saved = Settings.shared.prefs.exampleLanguage
        defer { Settings.shared.prefs.exampleLanguage = saved }
        Settings.shared.prefs.exampleLanguage = .english
        XCTAssertTrue(Spelling.isNearMiss("xciao", "ciao"))
        XCTAssertTrue(Spelling.isNearMiss("ciaoo", "ciao"))
        XCTAssertFalse(Spelling.isNearMiss("cat", "bat"))
        XCTAssertEqual(Spelling.correction(for: "xciao", context: "xciao"), "ciao")
        XCTAssertEqual(Spelling.correction(for: "Xciao", context: "Xciao"), "Ciao")
        XCTAssertEqual(Spelling.detectedLanguageCode(for: "xciao"), "it")
        XCTAssertEqual(Spelling.dominantLanguageCode(of: "xciao"), "it")
        XCTAssertEqual(CompletionController.applySpellingFixes(to: "xciao").lowercased(), "ciao")
        XCTAssertEqual(CompletionController.rewriteLanguage(text: "xciao", before: ""), "it")
        let p = CompletionController.buildRewritePrompt(text: "ciao", instruction: "Fix grammar, spelling and punctuation only, keeping the same language",
                                                        language: CompletionController.rewriteLanguage(text: "xciao", before: ""))
        XCTAssertTrue(p.contains("Corretto:"))
        XCTAssertFalse(p.contains("Corrected:"))
        // A one-word answer in the other language is rejected.
        XCTAssertTrue(CompletionController.hasUnwantedLanguageSwitch(original: "ciao", output: "Hello",
                                                                     instruction: "Fix grammar, spelling and punctuation only", language: "it"))
        XCTAssertFalse(CompletionController.hasUnwantedLanguageSwitch(original: "ciao", output: "Ciao!",
                                                                      instruction: "Fix grammar, spelling and punctuation only", language: "it"))
    }

    func testAmbientGainFarFieldAndDecibelMeter() {
        // A teacher two meters away: raw RMS ≈ 0.0012 (−58 dBFS). The gain climbs to the cap…
        var g: Float = 10
        for _ in 0..<60 { g = AmbientGain.nextGain(current: g, rms: 0.0012) }
        XCTAssertGreaterThan(g, 40)
        // …and the meter (dB scale) shows a clearly lively level, not 7–12 %.
        XCTAssertGreaterThan(AmbientGain.meterLevel(rms: 0.0012 * g), 0.5)
        XCTAssertGreaterThan(AmbientGain.meterLevel(rms: AmbientGain.targetRMS), 0.75)
        XCTAssertEqual(AmbientGain.meterLevel(rms: 0), 0)
    }

    func testAudioAutoLocaleFollowsTheMacWhenTheAppIsInEnglish() {
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .italian, preferred: ["en-US"], region: "US"), "it")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .french, preferred: ["en-US"], region: "US"), "fr")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .english, preferred: ["en-US", "it-IT"], region: "US"), "it")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .english, preferred: ["en-US"], region: "IT"), "it")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .english, preferred: ["en-GB"], region: "GB"), "en")
    }

    func testWebLookupTypoQueryAndItalianIdiom() {
        let saved = Settings.shared.prefs.exampleLanguage
        defer { Settings.shared.prefs.exampleLanguage = saved }
        Settings.shared.prefs.exampleLanguage = .english
        XCTAssertEqual(WebLookup.normalizedSearchQuery("coaa sta succednedo in palestina?").lowercased(), "cosa sta succedendo in palestina")
        XCTAssertEqual(WebLookup.contentWords(in: "cosa sta succedendo in palestina"), ["palestina"])
        XCTAssertTrue(WebLookup.isRelevantNewsItem(title: "Palestina, ultime notizie da Gaza e Cisgiordania", forQuery: "coaa sta succednedo in palestina?"))
        XCTAssertEqual(WebLookup.queryLanguage("avere il coltello dalla parte del manico"), "it")
        XCTAssertEqual(WebLookup.queryLanguage("what is happening in the world today"), "en")
        let json = #"{"query":{"search":[{"title":"manico","snippet":"<span class=\"searchmatch\">avere</span> il coltello dalla parte del manico"}]}}"#
        let hits = WebLookup.parseMediaWikiSearch(data: json.data(using: .utf8), host: "it.wiktionary.org")
        XCTAssertEqual(hits.first?.snippet, "avere il coltello dalla parte del manico")
        XCTAssertEqual(hits.first?.url.absoluteString, "https://it.wiktionary.org/wiki/manico")
    }
    // MARK: PLAN_V18

    func testRewriteResultKeepsInnerQuotes() {
        XCTAssertEqual(CompletionController.rewriteResult("L'espressione \"avere il coltello dalla parte del manico\" significa essere in vantaggio.\""),
                       "L'espressione \"avere il coltello dalla parte del manico\" significa essere in vantaggio.")
        XCTAssertEqual(CompletionController.rewriteResult("Ciao, come stai?\"\nOriginale: \"altro\""), "Ciao, come stai?")
        XCTAssertEqual(CompletionController.rewriteResult("Ho letto \"Il nome della rosa\" ieri."), "Ho letto \"Il nome della rosa\" ieri.")
        XCTAssertNil(CompletionController.rewriteResult("\""))
        XCTAssertEqual(CompletionController.rewriteResult("Ciao, mi chiamo Edoardo.\" Corretto: \"Ciao."), "Ciao, mi chiamo Edoardo.")
    }

    func testTaskGenerationIsIndependentFromTyping() {
        let engine = LLMEngine()
        let task = engine.taskGeneration.next()
        engine.generation.next(); engine.generation.next()   // keystrokes, focus and app switches
        XCTAssertEqual(engine.taskGeneration.current, task)
    }

    func testIdiomDictionaryAndPhraseCore() {
        XCTAssertEqual(WebLookup.phraseCore("avere il coltello fra i denti"), "coltello fra i denti")
        XCTAssertEqual(WebLookup.phraseCore("avere l'acqua alla gola"), "acqua alla gola")
        XCTAssertNotNil(WebLookup.idiomMeaning("avere il coltello dalla parte del manico"))
        XCTAssertNotNil(WebLookup.idiomMeaning("ha il coltello dalla parte del manico"))
        XCTAssertNotNil(WebLookup.idiomMeaning("Tenere il coltello dalla parte del manico"))
        XCTAssertNotNil(WebLookup.idiomMeaning("break the ice"))
        XCTAssertNil(WebLookup.idiomMeaning("ghiaccio"))
        XCTAssertNil(WebLookup.idiomMeaning("prezzi della benzina"))
    }

    func testIdiomUsageExamplesAndFocusedSentence() {
        let core = "coltello dalla parte del manico"
        let snippet = "noi? (Samuel Butler) Sai, Josey, bisogna sempre tenere il coltello dalla parte del manico. Se vuoi vivere, devi"
        let f = WebLookup.focusedSentence(snippet, on: core)
        XCTAssertEqual(f, "Sai, Josey, bisogna sempre tenere il coltello dalla parte del manico.")
        XCTAssertTrue(WebLookup.isUsageExample(f!, core: core))
        XCTAssertFalse(WebLookup.isUsageExample("Henri Barbusse, Il coltello fra i denti, Casa ed.", core: "coltello fra i denti"))
        let list = "Stiracchiato, forzato. Col coltello fra i denti - Con grande tenacia. Occhio per occhio"
        XCTAssertEqual(WebLookup.focusedSentence(list, on: "coltello fra i denti"), "Col coltello fra i denti - Con grande tenacia.")
    }

    func testNewsAndWikiMatchByStem() {
        XCTAssertTrue(WebLookup.mentions("proteste dei palestinesi a gaza", "palestina"))
        XCTAssertTrue(WebLookup.isRelevantNewsItem(title: "Gaza, i palestinesi tornano a nord", forQuery: "coaa sta succednedo in palestina?"))
        XCTAssertFalse(WebLookup.mentions("le mani in alto", "manico"))   // short words: whole word only
        XCTAssertEqual(WebLookup.cleanEncyclopedia("La Palestina (in arabo فلسطين?, , nel dialetto locale ), ufficialmente Stato di Palestina, è uno Stato."),
                       "La Palestina, ufficialmente Stato di Palestina, è uno Stato.")
        XCTAssertFalse(WebLookup.cleanEncyclopedia("Disambiguazione – Palestina rimanda qui. La Palestina è una regione.").contains("rimanda"))
    }

    func testAudioAllowedLanguages() {
        let itFirst = AudioContext.allowedLanguages(startingWith: "it-IT")
        XCTAssertEqual(itFirst.first, "it")
        XCTAssertEqual(Set(itFirst), Set(WhisperEngine.supportedLanguages))
        let fallback = AudioContext.allowedLanguages(startingWith: "ja")
        XCTAssertEqual(fallback.first, "en")
    }

    @MainActor
    func testLookupCopyText() {
        let card = WebLookup.ResultCard(query: "q", isDefinition: true, summary: "Sunto.", bullets: ["uno", "due"], bulletTitle: "", sources: [])
        XCTAssertEqual(LookupCardView.copyText(card), "Sunto.\n• uno\n• due")
    }

    func testNonBreakingSpaceHandlingInPromptHealCleanAndInsertion() {
        let p = SuggestionText.prompt(prefix: "ciao\u{00A0}", prefixStart: 0, caretLocation: 5)
        XCTAssertTrue(p.userEndedWithSpace)
        XCTAssertEqual(p.text, "ciao")
        XCTAssertEqual(SuggestionText.clean(" mi chiamo", userEndedWithSpace: p.userEndedWithSpace, truncated: false), "mi chiamo")

        let healed = SuggestionText.healSplit("ciao\u{00A0}mi")
        XCTAssertEqual(healed?.stem, "ciao")
        XCTAssertEqual(healed?.heal, " mi")

        XCTAssertTrue(SuggestionText.isIndentPosition("-\u{00A0}"))
        XCTAssertEqual(SuggestionText.safeForInsertion("mi\u{00A0}chiamo"), "mi chiamo")
    }

    func testReconcileFixesOneKeystrokeLagAndPreventsDoubleSpaces() {
        XCTAssertEqual(
            SuggestionText.reconcile(suggestion: "g how are you", basePrefix: "learnin", livePrefix: "learning"),
            " how are you"
        )
        XCTAssertEqual(
            SuggestionText.reconcile(suggestion: "g how are you", basePrefix: "learnin", livePrefix: "learning "),
            "how are you"
        )
        XCTAssertEqual(
            SuggestionText.reconcile(suggestion: " mi chiamo", basePrefix: "ciao", livePrefix: "ciao "),
            "mi chiamo"
        )
        XCTAssertEqual(
            SuggestionText.reconcile(suggestion: " mi chiamo", basePrefix: "ciao\u{00A0}", livePrefix: "ciao\u{00A0}"),
            "mi chiamo"
        )
        XCTAssertEqual(
            SuggestionText.reconcile(suggestion: "g", basePrefix: "learnin", livePrefix: "learning "),
            ""
        )
    }
}
