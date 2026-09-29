import Foundation

/// An amount recovered from free text, along with whatever the text revealed about its currency.
public struct ParsedAmount: Hashable, Sendable {
    public let amount: Decimal
    /// Set only when the text named the currency beyond doubt: a recognised ISO code, or a
    /// symbol that exactly one currency uses.
    public let currency: CurrencyCode?
    /// Populated instead of `currency` when the symbol is shared, ordered by how commonly
    /// the bare symbol means each one. A lone `$` is far more often USD than TWD.
    public let candidates: [CurrencyCode]
    /// The currency token as it appeared, kept for diagnostics and for showing the user
    /// what the app thought it saw.
    public let token: String?

    public var isAmbiguous: Bool { currency == nil && !candidates.isEmpty }
}

/// Recovers an amount and currency from the text a Shortcuts automation supplies.
///
/// The Wallet transaction trigger exposes a `Currency Code` property, but it is optional and
/// easy to leave unmapped, and the amount itself can arrive already formatted — `¥12,000`,
/// `RM 45.90`, `1.234,56 €`. Parsing has to cope with that without a `Replace Text` step in
/// the shortcut, because anything the user has to assemble by hand is something that breaks
/// silently when iOS changes the trigger.
///
/// Formatting is not read through `NumberFormatter`: its behaviour depends on the device
/// locale, which is exactly the thing that is wrong when travelling, and it differs between
/// Apple and swift-corelibs Foundation. The rules below are explicit so they can be tested.
public enum AmountParser {
    public static func parse(_ raw: String) -> ParsedAmount? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let amount = number(in: text) else { return nil }

        let token = currencyToken(in: text)
        return ParsedAmount(
            amount: amount,
            currency: token?.currency,
            candidates: token?.candidates ?? [],
            token: token?.text
        )
    }

    // MARK: - Currency

    private struct Token {
        let text: String
        let currency: CurrencyCode?
        let candidates: [CurrencyCode]
    }

    private static func currencyToken(in text: String) -> Token? {
        if let iso = isoCode(in: text) {
            return Token(text: iso.rawValue, currency: iso, candidates: [])
        }

        // Longest match first so "HK$" wins over "$" and "US$" over "$".
        for (symbol, currencies) in symbolTable {
            guard text.localizedCaseInsensitiveContains(symbol) else { continue }
            if currencies.count == 1 {
                return Token(text: symbol, currency: currencies[0], candidates: [])
            }
            return Token(text: symbol, currency: nil, candidates: currencies)
        }

        return nil
    }

    /// Looks for an isolated three-letter run that names a currency the app knows.
    ///
    /// The run has to be exactly three letters and recognised, so a merchant fragment like
    /// "BAR" or "CAFE" cannot masquerade as a currency.
    private static func isoCode(in text: String) -> CurrencyCode? {
        var run = ""
        var found: CurrencyCode?

        func consider(_ run: String) {
            guard run.count == 3, let code = CurrencyCode(run), code.isRecognised else { return }
            found = code
        }

        for character in text {
            if character.isLetter, character.isASCII {
                run.append(character)
            } else {
                consider(run)
                run = ""
            }
        }
        consider(run)

        return found
    }

    /// Ordered longest-first. Ambiguous symbols list their currencies by how commonly the
    /// bare symbol is used for each, which only matters when neither the region nor the
    /// home currency can settle it.
    private static let symbolTable: [(String, [CurrencyCode])] = [
        ("US$", [.usd]),
        ("HK$", [CurrencyCode(unchecked: "HKD")]),
        ("NT$", [CurrencyCode(unchecked: "TWD")]),
        ("AU$", [CurrencyCode(unchecked: "AUD")]),
        ("CA$", [CurrencyCode(unchecked: "CAD")]),
        ("NZ$", [CurrencyCode(unchecked: "NZD")]),
        ("A$", [CurrencyCode(unchecked: "AUD")]),
        ("C$", [CurrencyCode(unchecked: "CAD")]),
        ("S$", [.sgd]),
        ("R$", [CurrencyCode(unchecked: "BRL")]),
        ("RM", [.myr]),
        ("Rp", [CurrencyCode(unchecked: "IDR")]),
        ("zł", [CurrencyCode(unchecked: "PLN")]),
        ("Kč", [CurrencyCode(unchecked: "CZK")]),
        ("Ft", [CurrencyCode(unchecked: "HUF")]),
        ("€", [.eur]),
        ("£", [CurrencyCode(unchecked: "GBP")]),
        ("₹", [CurrencyCode(unchecked: "INR")]),
        ("₩", [CurrencyCode(unchecked: "KRW")]),
        ("฿", [.thb]),
        ("₫", [.vnd]),
        ("₱", [CurrencyCode(unchecked: "PHP")]),
        ("₪", [CurrencyCode(unchecked: "ILS")]),
        ("₺", [CurrencyCode(unchecked: "TRY")]),
        ("₦", [CurrencyCode(unchecked: "NGN")]),
        ("₸", [CurrencyCode(unchecked: "KZT")]),
        ("د.إ", [CurrencyCode(unchecked: "AED")]),
        ("$", [
            .usd,
            CurrencyCode(unchecked: "AUD"),
            CurrencyCode(unchecked: "CAD"),
            .sgd,
            CurrencyCode(unchecked: "HKD"),
            CurrencyCode(unchecked: "NZD"),
            CurrencyCode(unchecked: "TWD"),
            CurrencyCode(unchecked: "MXN")
        ]),
        ("¥", [.jpy, CurrencyCode(unchecked: "CNY")]),
        ("₨", [
            CurrencyCode(unchecked: "PKR"),
            CurrencyCode(unchecked: "LKR"),
            CurrencyCode(unchecked: "NPR")
        ]),
        ("﷼", [
            CurrencyCode(unchecked: "SAR"),
            CurrencyCode(unchecked: "QAR"),
            CurrencyCode(unchecked: "YER")
        ]),
        ("kr", [
            CurrencyCode(unchecked: "SEK"),
            CurrencyCode(unchecked: "NOK"),
            CurrencyCode(unchecked: "DKK"),
            CurrencyCode(unchecked: "ISK")
        ])
    ]

    // MARK: - Number

    private static func number(in text: String) -> Decimal? {
        // Grouping characters that are never decimal separators are dropped outright, as is
        // anything that is not a digit or a `.`/`,` — which removes symbols and letters and
        // leaves just the numeric shape.
        var shape = ""
        for character in text {
            if character.isASCII, character.isNumber {
                shape.append(character)
            } else if character == "." || character == "," {
                shape.append(character)
            }
        }
        guard shape.contains(where: \.isNumber) else { return nil }

        let separator = decimalSeparator(in: shape)
        var digits = ""
        let lastSeparatorIndex = separator.flatMap { shape.lastIndex(of: $0) }

        for index in shape.indices {
            let character = shape[index]
            if character.isNumber {
                digits.append(character)
            } else if index == lastSeparatorIndex {
                digits.append(".")
            }
        }

        guard !digits.isEmpty, let magnitude = Decimal(string: digits) else { return nil }
        return isNegative(text) ? -magnitude : magnitude
    }

    /// Decides which of `.` and `,` is acting as the decimal point.
    ///
    /// Returns `nil` when every separator present is grouping, so `¥12,000` is twelve
    /// thousand yen rather than twelve, and `Rp150.000` is a hundred and fifty thousand
    /// rupiah rather than a hundred and fifty.
    private static func decimalSeparator(in shape: String) -> Character? {
        let dots = shape.filter { $0 == "." }.count
        let commas = shape.filter { $0 == "," }.count

        if dots > 0, commas > 0 {
            // Mixed separators are unambiguous: whichever comes last is the decimal point,
            // because grouping never follows the fraction.
            return shape.lastIndex(of: ".")! > shape.lastIndex(of: ",")! ? "." : ","
        }

        let separator: Character
        let count: Int
        if dots > 0 {
            (separator, count) = (".", dots)
        } else if commas > 0 {
            (separator, count) = (",", commas)
        } else {
            return nil
        }

        // Repetition can only be grouping: "1.234.567".
        guard count == 1 else { return nil }

        // A single separator with exactly three digits after it is the classic grouping
        // shape. No currency in circulation has three minor-unit digits *and* writes them
        // with a bare group-sized tail, so treating it as grouping is the safer reading:
        // misreading 12,000 as 12 is a far worse error than the reverse.
        let trailing = shape.distance(from: shape.index(after: shape.lastIndex(of: separator)!), to: shape.endIndex)
        return trailing == 3 ? nil : separator
    }

    private static func isNegative(_ text: String) -> Bool {
        if text.hasPrefix("("), text.hasSuffix(")") { return true }
        guard let firstDigit = text.firstIndex(where: { $0.isNumber }) else { return false }
        let prefix = text[text.startIndex ..< firstDigit]
        return prefix.contains("-") || prefix.contains("\u{2212}")
    }
}
