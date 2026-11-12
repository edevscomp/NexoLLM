import Foundation
import XCTest
@testable import NexoLLM

/// PLAN_V20: soft pastel stacked histogram & word analytics, 6 active languages (UI, Tour, Writing Tools, Whisper STT),
/// offlineMode removal, device-neutral copy, and universal jurisdiction-neutral audio notice.
final class V20Tests: XCTestCase {

    // MARK: - Step 1: Per-App Daily Stats & Stacked Pastel Histogram

    func testStatsDayRecordsPerAppAndRoundTripsJSON() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let stats = Stats(days: [:])
        stats.record(words: 80, app: "com.apple.Notes", on: yesterday)
        stats.record(words: 45, app: "com.apple.mail", on: yesterday)
        stats.record(words: 120, app: "com.apple.Notes", on: today)

        let yDay = stats.day(yesterday)
        XCTAssertEqual(yDay.words, 125)
        XCTAssertEqual(yDay.completions, 2)
        XCTAssertEqual(yDay.byApp, ["com.apple.Notes": 80, "com.apple.mail": 45])
        XCTAssertEqual(yDay.appBreakdown, ["com.apple.Notes": 80, "com.apple.mail": 45])

        let totals = Stats.appTotals([yDay, stats.day(today)])
        XCTAssertEqual(totals.count, 2)
        XCTAssertEqual(totals[0].app, "com.apple.Notes")
        XCTAssertEqual(totals[0].words, 200)
        XCTAssertEqual(totals[1].app, "com.apple.mail")
        XCTAssertEqual(totals[1].words, 45)

        let encoded = try JSONEncoder().encode(yDay)
        let decoded = try JSONDecoder().decode(Stats.Day.self, from: encoded)
        XCTAssertEqual(decoded, yDay)
    }

    func testLegacyStatsJSONWithoutByAppFallsBackToOtherApp() throws {
        let legacyJSON = #"{"words":240,"completions":18}"#
        let day = try JSONDecoder().decode(Stats.Day.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(day.words, 240)
        XCTAssertEqual(day.completions, 18)
        XCTAssertTrue(day.byApp.isEmpty)
        XCTAssertEqual(day.appBreakdown, [Stats.otherApp: 240])

        var mixed = day
        mixed.byApp = ["com.apple.Notes": 100]
        XCTAssertEqual(mixed.appBreakdown, ["com.apple.Notes": 100, Stats.otherApp: 140])
    }

    func testStatsStreakCalculation() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func key(_ offset: Int) -> String {
            Stats.dayFormatter.string(from: cal.date(byAdding: .day, value: offset, to: today)!)
        }

        let active3: [String: Stats.Day] = [
            key(-2): Stats.Day(words: 40, completions: 2),
            key(-1): Stats.Day(words: 65, completions: 4),
            key(0): Stats.Day(words: 30, completions: 1),
        ]
        XCTAssertEqual(Stats.streak(active3, today: today), 3)

        // If nothing has been written yet today, yesterday's active run still counts.
        let endingYesterday: [String: Stats.Day] = [
            key(-2): Stats.Day(words: 20, completions: 1),
            key(-1): Stats.Day(words: 50, completions: 3),
        ]
        XCTAssertEqual(Stats.streak(endingYesterday, today: today), 2)

        // A two-day gap resets the streak.
        let broken: [String: Stats.Day] = [
            key(-3): Stats.Day(words: 90, completions: 5),
        ]
        XCTAssertEqual(Stats.streak(broken, today: today), 0)
    }

    @MainActor func testAppPaletteAndStackedBuckets() {
        let apps = (1...8).map { "app.\($0)" }
        let palette = AppPalette(ranked: apps)
        XCTAssertEqual(palette.ranked.count, AppPalette.maxApps)
        XCTAssertEqual(palette.group("app.1"), "app.1")
        XCTAssertEqual(palette.group("app.7"), AppPalette.others)
        XCTAssertEqual(palette.group(Stats.otherApp), AppPalette.others)

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let d1 = cal.date(byAdding: .day, value: -1, to: today)!
        let days: [(Date, Stats.Day)] = [
            (d1, Stats.Day(words: 150, completions: 5, byApp: ["app.1": 90, "app.7": 60])),
            (today, Stats.Day(words: 80, completions: 3)), // legacy unattributed day
        ]
        let buckets = StackedBucket.make(days: days, grouping: .day, palette: palette)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].total, 150)
        XCTAssertEqual(buckets[0].segments.map(\.app), ["app.1", AppPalette.others])
        XCTAssertEqual(buckets[1].total, 80)
        XCTAssertEqual(buckets[1].segments.map(\.app), [AppPalette.others])

        for v in [0, 1, 7, 43, 185, 312, 1250] {
            let ceil = StackedPastelHistogram.niceCeiling(v)
            XCTAssertGreaterThanOrEqual(ceil, max(4, v))
            XCTAssertEqual(ceil % 4, 0)
        }
    }

    // MARK: - Step 5: Six Active Languages (UI, Formatting, Interpolation & Tour)

    func testAllSixLanguagesAreActiveWithMetadata() {
        XCTAssertEqual(ExampleLanguage.allCases.map(\.iso), ["en", "it", "es", "fr", "de", "pt"])
        XCTAssertEqual(ExampleLanguage.allCases.map(\.code), ["EN", "IT", "ES", "FR", "DE", "PT"])
        for lang in ExampleLanguage.allCases {
            XCTAssertFalse(lang.label.isEmpty)
            XCTAssertFalse(lang.flag.isEmpty)
            XCTAssertFalse(lang.localeIdentifier.isEmpty)
            XCTAssertFalse(lang.englishName.isEmpty)
        }
    }

    func testLocalizationTablesAndTemplateInterpolation() {
        for lang in [ExampleLanguage.spanish, .french, .german, .portuguese] {
            let table = Localization.table(lang)
            XCTAssertGreaterThanOrEqual(table.count, 665, "Missing translations in \(lang.iso)")
            for (k, v) in table {
                XCTAssertFalse(v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty translation for \(k) in \(lang.iso)")
            }
        }

        let name = "Gemma 4"
        let enText: LText = "Downloading \(name)…"
        let itText: LText = "Download di \(name)…"
        XCTAssertEqual(enText.template, "Downloading {0}…")
        for lang in ExampleLanguage.allCases {
            let rendered = Localization.resolve(enText, itText, in: lang)
            XCTAssertTrue(rendered.contains("Gemma 4"), "Interpolation lost in \(lang.iso): \(rendered)")
            XCTAssertFalse(rendered.contains("{0}"), "Unexpanded placeholder in \(lang.iso): \(rendered)")
        }

        let originalSaving = Settings.shared.savingEnabled
        let originalLang = Settings.shared.prefs.exampleLanguage
        Settings.shared.savingEnabled = false
        defer {
            Settings.shared.prefs.exampleLanguage = originalLang
            Settings.shared.savingEnabled = originalSaving
        }
        for lang in ExampleLanguage.allCases {
            Settings.shared.prefs.exampleLanguage = lang
            XCTAssertFalse(Fmt.status("Ready · gemma-4.gguf").isEmpty)
            XCTAssertFalse(Stats.timeSaved(words: 240).isEmpty)
        }
    }

    func testTourExamplesAndWalkthroughFlowInAllSixLanguages() {
        for lang in ExampleLanguage.allCases {
            let ex = TourExamples.for(lang)
            XCTAssertTrue(ex.target.hasPrefix(ex.sampleStart), "Sample start mismatch in \(lang.iso)")
            XCTAssertGreaterThan(ex.target.count, ex.sampleStart.count + 10)
            XCTAssertFalse(ex.followUp.isEmpty)
            XCTAssertEqual(ex.altWords.count, 4, "Expected 4 altWords in \(lang.iso)")
            XCTAssertEqual(ex.altPhrases.count, 4, "Expected 4 altPhrases in \(lang.iso)")
            XCTAssertEqual(ex.chips.count, 4, "Expected 4 style chips in \(lang.iso)")
            XCTAssertEqual(ex.rewrites.count, 4, "Expected 4 rewrite demos in \(lang.iso)")

            let state = WalkthroughState(lang: lang)
            state.clicks = false
            state.animated = false
            XCTAssertEqual(state.typed, ex.sampleStart)
            XCTAssertFalse(state.ghost.isEmpty)
            state.acceptWord()
            XCTAssertGreaterThan(state.typed.count, ex.sampleStart.count)
            state.acceptAll()
            XCTAssertEqual(state.typed, ex.target)
            XCTAssertEqual(state.ghost, ex.followUp)
            state.acceptAll()
            XCTAssertEqual(state.typed, ex.target + ex.followUp)
        }
    }

    // MARK: - Multilingual Writing Tools & Language Detection

    func testLanguageDetectionReactsAcrossAllSixLanguages() {
        let samples: [(String, String)] = [
            ("en", "Thanks for sending the project update this morning"),
            ("it", "Grazie per aver mandato il documento della riunione oggi"),
            ("es", "Hola, mañana tenemos una reunión importante sobre el proyecto"),
            ("fr", "Bonjour, nous avons une réunion demain matin avec toute l'équipe"),
            ("de", "Hallo, morgen haben wir ein wichtiges Treffen für dieses Projekt"),
            ("pt", "Olá, amanhã temos uma reunião importante sobre o ficheiro"),
        ]
        for (expected, sample) in samples {
            XCTAssertEqual(Spelling.detectedLanguageCode(for: sample), expected, "Sample: \(sample)")
        }
    }

    func testRewritePromptsCoverAllSixLanguagesWithoutBiographies() {
        XCTAssertEqual(RewriteExamples.languages, ["en", "it", "es", "fr", "de", "pt"])
        let instructions = [
            "Improve clarity and flow, keeping the same language and meaning",
            "Fix grammar, spelling and punctuation only, keeping the same language",
            "Rewrite in a formal, polite and professional tone in the same language",
            "Make this more concise in the same language",
        ]
        let banned = ["alex", "marco", "cybersecurity", "sicurezza informatica", "computer engineer",
                      "ingegnere", "ai expert", "10 years", "10 anni", "my name is", "mi chiamo"]
        for lang in RewriteExamples.languages {
            for inst in instructions {
                let prompt = CompletionController.buildRewritePrompt(text: "test sample", instruction: inst, language: lang).lowercased()
                for b in banned {
                    XCTAssertFalse(prompt.contains(b), "Banned token '\(b)' found in \(lang) prompt for \(inst)")
                }
            }
        }
    }

    // MARK: - Local Whisper STT in 6 Languages

    func testWhisperSupportedLanguagesAndLocales() {
        XCTAssertEqual(WhisperEngine.supportedLanguages, ["en", "it", "es", "fr", "de", "pt"])
        XCTAssertEqual(AudioContext.speechLocales.map(\.iso), ["en", "it", "es", "fr", "de", "pt"])

        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .spanish, preferred: ["en-US"], region: "US"), "es")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .french, preferred: ["en-US"], region: "US"), "fr")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .german, preferred: ["en-US"], region: "US"), "de")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .portuguese, preferred: ["en-US"], region: "US"), "pt")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .english, preferred: ["fr-FR"], region: "US"), "fr")
        XCTAssertEqual(AudioContext.preferredAutoLanguage(appLanguage: .english, preferred: ["en-US"], region: "DE"), "de")

        let ordered = AudioContext.allowedLanguages(startingWith: "de-DE")
        XCTAssertEqual(ordered.first, "de")
        XCTAssertEqual(Set(ordered), Set(["en", "it", "es", "fr", "de", "pt"]))
    }

    func testWhisperHallucinationsFilteredInAllSixLanguages() {
        let hallucinations = [
            "Thank you for watching",
            "Grazie per la visione",
            "Gracias por ver el video",
            "Merci d'avoir regardé",
            "Vielen Dank fürs Zuschauen",
            "Obrigado por assistir",
            "Subtítulos realizados por la comunidad de Amara.org",
            "Sous-titres réalisés par la communauté d'Amara.org",
        ]
        for h in hallucinations {
            XCTAssertEqual(WhisperEngine.clean(h), "", "Hallucination survived: \(h)")
        }

        XCTAssertEqual(WhisperEngine.clean("El presupuesto queda aprobado [aplausos] hoy."), "El presupuesto queda aprobado hoy.")
        XCTAssertEqual(WhisperEngine.clean("Nous commençons la réunion à quinze heures."), "Nous commençons la réunion à quinze heures.")
        XCTAssertEqual(WhisperEngine.clean("Die Besprechung beginnt um fünfzehn Uhr."), "Die Besprechung beginnt um fünfzehn Uhr.")
        XCTAssertEqual(WhisperEngine.clean("A reunião começa às quinze horas."), "A reunião começa às quinze horas.")
    }

    // MARK: - Steps 2 & 3: OfflineMode Removal, Generic Copy & Universal Legal Notice

    @MainActor func testOfflineModeRemovedFromPrefs() throws {
        let data = try JSONEncoder().encode(Prefs())
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("offlineMode"))
        XCTAssertEqual(AudioPlugin.consentVersion, 2)
    }

    func testUniversalLegalNoticeAndTranslationsHaveNoJurisdictionOrOSSpecifics() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NexoLLMTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let legal = try String(contentsOf: root.appendingPathComponent("LEGAL_AUDIO_PLUGIN.md"), encoding: .utf8)
        let privacy = try String(contentsOf: root.appendingPathComponent("PRIVACY.md"), encoding: .utf8)
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let security = try String(contentsOf: root.appendingPathComponent("SECURITY.md"), encoding: .utf8)

        let forbiddenLegal = ["GDPR", "2016/679", "615-bis", "California", "Florida", "macOS", "MacBook", "Apple", "Full notice on GitHub"]
        for term in forbiddenLegal {
            XCTAssertFalse(legal.localizedCaseInsensitiveContains(term), "LEGAL_AUDIO_PLUGIN.md still mentions '\(term)'")
        }
        for term in ["Offline mode", "offlineMode", "macOS", "MacBook", "Apple", "Keychain"] {
            XCTAssertFalse(privacy.localizedCaseInsensitiveContains(term), "PRIVACY.md still mentions '\(term)'")
        }
        for term in ["for macOS", "Apple Silicon", "16 GB Macs", "8 GB Macs", "Keychain", "MacBook"] {
            XCTAssertFalse(readme.localizedCaseInsensitiveContains(term), "README.md still mentions '\(term)'")
        }
        for term in ["macOS", "MacBook", "Apple", "Keychain"] {
            XCTAssertFalse(security.localizedCaseInsensitiveContains(term), "SECURITY.md still mentions '\(term)'")
        }

        let forbiddenUI = ["GDPR", "615-bis", "Full notice on GitHub", "for macOS", "Offline mode", "Beta notice", "Coming soon"]
        for lang in [ExampleLanguage.spanish, .french, .german, .portuguese] {
            for (enKey, trans) in Localization.table(lang) {
                for term in forbiddenUI {
                    XCTAssertFalse(enKey.localizedCaseInsensitiveContains(term), "English key still contains '\(term)': \(enKey)")
                    XCTAssertFalse(trans.localizedCaseInsensitiveContains(term), "\(lang.iso) translation still contains '\(term)': \(trans)")
                }
            }
        }
    }
}
