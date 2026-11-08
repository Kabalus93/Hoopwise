import Foundation
import SwiftUI

// The Plays screens came from HoopWise Journal, which follows the SYSTEM
// language through a String Catalog. Hoopwise has its own in-app language
// (LocalizationManager) and no catalog, and adding a zh-Hans localization to
// the bundle would change Locale.current and system UI app-wide. So the Plays
// strings resolve here instead: `JPString` builds the catalog key from a
// literal ("\(n) steps" → "%lld steps"), `jp` looks it up in the Journal's
// table (JournalPlayStrings) in the app's language. A missing key reads as
// itself, like a catalog miss.

nonisolated struct JPString: ExpressibleByStringInterpolation, Sendable {
    let key: String
    let args: [JPArg]

    enum JPArg: Sendable {
        case int(Int)
        case string(String)
    }

    init(stringLiteral value: String) {
        key = value
        args = []
    }

    init(stringInterpolation: Interpolation) {
        key = stringInterpolation.key
        args = stringInterpolation.args
    }

    struct Interpolation: StringInterpolationProtocol {
        var key = ""
        var args: [JPArg] = []

        init(literalCapacity: Int, interpolationCount: Int) {}

        mutating func appendLiteral(_ literal: String) { key += literal }

        mutating func appendInterpolation(_ value: Int) {
            key += "%lld"
            args.append(.int(value))
        }

        mutating func appendInterpolation(_ value: String) {
            key += "%@"
            args.append(.string(value))
        }
    }
}

enum JournalPlayLanguage {
    static var isChinese: Bool { LocalizationManager.shared.currentLanguage == .chinese }
}

/// The string in the app's language. English uses the singular form when
/// the only number is 1 ("1 step").
func jp(_ string: JPString, chinese: Bool = JournalPlayLanguage.isChinese) -> String {
    let entry = JournalPlayStrings.table[string.key] ?? JournalPlayStringsAdded.table[string.key]
    var format = string.key
    if let entry {
        if chinese, let zh = entry.zh {
            format = zh
        } else if case .int(1)? = string.args.first, string.args.count == 1, let one = entry.enOne {
            format = one
        } else {
            format = entry.en
        }
    }
    guard !string.args.isEmpty else { return format }
    // Fill %lld / %@ (and positional %1$@ forms) in order.
    var out = ""
    var rest = Substring(format)
    var next = 0
    let specifier = /%(?:(\d+)\$)?(lld|@|d)/
    while let match = rest.firstMatch(of: specifier) {
        out += rest[..<match.range.lowerBound]
        let index = match.output.1.flatMap { Int($0).map { $0 - 1 } } ?? next
        next += 1
        if string.args.indices.contains(index) {
            switch string.args[index] {
            case .int(let n): out += String(n)
            case .string(let s): out += s
            }
        }
        rest = rest[match.range.upperBound...]
    }
    return out + rest
}

/// A Plays label in the app's language.
func JText(_ string: JPString) -> Text { Text(verbatim: jp(string)) }
