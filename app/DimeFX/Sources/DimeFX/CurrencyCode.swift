import Foundation

/// An ISO 4217 alphabetic currency code.
///
/// Stored uppercased so that codes arriving from Shortcuts input, the rate API and
/// Core Data all compare equal regardless of how they were typed.
public struct CurrencyCode: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// Returns `nil` for anything that is not three ASCII letters.
    public init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 3,
              trimmed.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return nil }
        self.rawValue = trimmed
    }

    /// For codes that are known good at compile time.
    public init(unchecked rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let code = CurrencyCode(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(raw)' is not a three-letter ISO 4217 code"
            )
        }
        self = code
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension CurrencyCode {
    static let myr = CurrencyCode(unchecked: "MYR")
    static let sgd = CurrencyCode(unchecked: "SGD")
    static let jpy = CurrencyCode(unchecked: "JPY")
    static let usd = CurrencyCode(unchecked: "USD")
    static let eur = CurrencyCode(unchecked: "EUR")
    static let vnd = CurrencyCode(unchecked: "VND")
    static let kwd = CurrencyCode(unchecked: "KWD")
    static let thb = CurrencyCode(unchecked: "THB")
}

public extension CurrencyCode {
    /// ISO 4217 minor unit count, i.e. how many decimal places the currency subdivides into.
    ///
    /// The default is 2. Only the exceptions are listed, because getting these wrong is the
    /// difference between logging 12,000 yen and 120 yen.
    var minorUnits: Int {
        if Self.zeroDecimalCurrencies.contains(rawValue) { return 0 }
        if Self.threeDecimalCurrencies.contains(rawValue) { return 3 }
        return 2
    }

    private static let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
        "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"
    ]

    private static let threeDecimalCurrencies: Set<String> = [
        "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"
    ]
}

public extension CurrencyCode {
    /// Whether this is a currency the app is prepared to handle.
    ///
    /// Used when reading a three-letter token out of free text: without a known-good list,
    /// a merchant name like "BAR" or "GAS" would be mistaken for a currency code.
    var isRecognised: Bool { Self.recognised.contains(rawValue) }

    /// Deliberately a fixed list rather than everything ISO 4217 has ever minted. It needs
    /// to cover the currencies the rate provider quotes and the places the user travels,
    /// and nothing else — every extra entry is another way for text parsing to go wrong.
    static let recognised: Set<String> = [
        // Southeast Asia
        "MYR", "SGD", "THB", "IDR", "VND", "PHP", "KHR", "LAK", "MMK", "BND",
        // East Asia
        "JPY", "KRW", "CNY", "HKD", "TWD", "MOP",
        // South and Central Asia
        "INR", "LKR", "BDT", "PKR", "NPR", "KZT",
        // Middle East
        "AED", "SAR", "QAR", "KWD", "BHD", "OMR", "ILS", "TRY", "JOD", "IQD", "LYD", "TND", "YER",
        // Oceania
        "AUD", "NZD", "FJD", "PGK",
        // Europe
        "EUR", "GBP", "CHF", "NOK", "SEK", "DKK", "PLN", "CZK", "HUF", "RON", "BGN", "ISK",
        "RUB", "UAH",
        // Americas
        "USD", "CAD", "MXN", "BRL", "ARS", "CLP", "COP", "PEN", "UYU",
        // Africa
        "ZAR", "EGP", "MAD", "KES", "NGN", "TZS", "UGX", "RWF", "BIF", "DJF", "GNF", "KMF",
        "XAF", "XOF", "XPF", "PYG", "VUV"
    ]
}
