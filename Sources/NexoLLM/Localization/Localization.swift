import Foundation

/// An interface string as written in the code, with its interpolations kept apart.
///
/// `L("Delete \(name)?", "Eliminare \(name)?")` hands `L` the template `"Delete {0}?"` and the value of `name`,
/// so Spanish, French, German and Portuguese can be looked up by template (and may put `{0}` wherever their
/// grammar needs it) instead of by the finished English sentence.
struct LText: ExpressibleByStringInterpolation {
    var template = ""
    var args: [String] = []

    init(stringLiteral value: String) { template = value }
    init(_ string: String) { template = string }
    init(stringInterpolation: Interpolation) { template = stringInterpolation.template; args = stringInterpolation.args }

    struct Interpolation: StringInterpolationProtocol {
        var template = ""
        var args: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { template.reserveCapacity(literalCapacity + interpolationCount * 3) }
        mutating func appendLiteral(_ literal: String) { template += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            template += "{\(args.count)}"
            args.append(String(describing: value))
        }
    }

    /// The template with its values put back in.
    func render(_ pattern: String? = nil) -> String {
        var out = pattern ?? template
        guard !args.isEmpty else { return out }
        // Highest index first, so "{1}" is never touched by the replacement of "{10}".
        for i in args.indices.reversed() { out = out.replacingOccurrences(of: "{\(i)}", with: args[i]) }
        return out
    }
}

/// The interface string in the app language chosen in Settings. English and Italian are written at the call
/// site; Spanish, French, German and Portuguese come from the tables in `Localization/`, keyed by the English
/// template. A string missing from a table falls back to English.
func L(_ en: LText, _ it: LText) -> String {
    Localization.resolve(en, it, in: Settings.shared.prefs.exampleLanguage)
}

enum Localization {
    /// English template → translation, per language (generated from scripts/i18n/*.json by scripts/gen-strings.py).
    static func table(_ lang: ExampleLanguage) -> [String: String] {
        switch lang {
        case .english, .italian: return [:]
        case .spanish: return stringsES
        case .french: return stringsFR
        case .german: return stringsDE
        case .portuguese: return stringsPT
        }
    }

    static func resolve(_ en: LText, _ it: LText, in lang: ExampleLanguage) -> String {
        switch lang {
        case .english: return en.render()
        case .italian: return it.render()
        default: return en.render(table(lang)[en.template])
        }
    }

    /// The same text in every language (for things built once, like the tour's examples).
    static func all(_ en: LText, _ it: LText) -> [ExampleLanguage: String] {
        Dictionary(uniqueKeysWithValues: ExampleLanguage.allCases.map { ($0, resolve(en, it, in: $0)) })
    }
}
