import Foundation

/// Where the currency for a transaction came from.
///
/// Persisting this matters: a currency that was guessed from GPS deserves a different
/// level of trust in the UI than one the Shortcut stated outright.
public enum CurrencySource: Hashable, Sendable {
    /// The caller named it — the Wallet trigger's `Currency Code`, mapped in the shortcut.
    case explicit
    /// The amount text named it, via a recognised ISO code or a symbol only one currency uses.
    case parsedFromText
    /// The amount text used a shared symbol and the region settled which one was meant.
    case ambiguousSymbolResolvedByRegion(String)
    /// A shared symbol, no usable region, but the home currency was among the candidates.
    case ambiguousSymbolResolvedByHome
    /// A shared symbol that neither region nor home could settle, so the most common
    /// reading of the symbol was taken. The weakest answer the resolver will give.
    case ambiguousSymbolDefaulted
    /// Nothing in the text named a currency, so the region was used.
    case inferredFromRegion(String)
    case homeDefault
}

public enum CurrencyConfidence: Int, Sendable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public extension CurrencySource {
    /// Drives whether the app should quietly accept the currency or flag the transaction
    /// for a glance. Anything below `.high` is a guess, however good.
    var confidence: CurrencyConfidence {
        switch self {
        case .explicit, .parsedFromText:
            .high
        case .ambiguousSymbolResolvedByRegion, .ambiguousSymbolResolvedByHome, .inferredFromRegion:
            .medium
        case .ambiguousSymbolDefaulted, .homeDefault:
            .low
        }
    }
}

public struct ResolvedCurrency: Hashable, Sendable {
    public let currency: CurrencyCode
    public let source: CurrencySource

    public var confidence: CurrencyConfidence { source.confidence }

    /// True when the currency was worked out rather than stated.
    public var wasInferred: Bool {
        switch source {
        case .explicit, .parsedFromText: false
        default: true
        }
    }
}

/// Decides which currency a new transaction is denominated in.
///
/// Deliberately ordered by how much the input can be trusted. Device locale is *not*
/// consulted anywhere: a Malaysian phone reports MYR in Osaka just as it does in Kuala
/// Lumpur, so it carries no travel signal at all.
public struct CurrencyResolver: Sendable {
    public let home: CurrencyCode

    public init(home: CurrencyCode) {
        self.home = home
    }

    /// - Parameters:
    ///   - explicit: a currency stated by the caller, e.g. the Wallet trigger's `Currency
    ///     Code` mapped into the shortcut. Always wins.
    ///   - parsed: what the amount text itself revealed, from `AmountParser`.
    ///   - regionCode: ISO 3166-1 alpha-2 country from reverse geocoding, when available.
    public func resolve(
        explicit: CurrencyCode? = nil,
        parsed: ParsedAmount? = nil,
        regionCode: String? = nil
    ) -> ResolvedCurrency {
        if let explicit {
            return ResolvedCurrency(currency: explicit, source: .explicit)
        }

        let region = regionCode.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
        let regional = region.flatMap { Self.currency(forRegion: $0) }

        if let parsed {
            if let named = parsed.currency {
                return ResolvedCurrency(currency: named, source: .parsedFromText)
            }

            if !parsed.candidates.isEmpty {
                // The symbol has narrowed it to a handful; the region picks between them.
                // Note the ordering: a `$` tapped in Singapore is SGD even though USD is
                // the more common meaning of the symbol worldwide.
                if let regional, let region, parsed.candidates.contains(regional) {
                    return ResolvedCurrency(
                        currency: regional,
                        source: .ambiguousSymbolResolvedByRegion(region)
                    )
                }
                if parsed.candidates.contains(home) {
                    return ResolvedCurrency(currency: home, source: .ambiguousSymbolResolvedByHome)
                }
                // Neither helps. The symbol is still better evidence than the region would
                // be — a `$` in Japan is not yen — so take its most common meaning.
                return ResolvedCurrency(
                    currency: parsed.candidates[0],
                    source: .ambiguousSymbolDefaulted
                )
            }
        }

        if let regional, let region {
            return ResolvedCurrency(currency: regional, source: .inferredFromRegion(region))
        }

        return ResolvedCurrency(currency: home, source: .homeDefault)
    }

    public static func currency(forRegion regionCode: String) -> CurrencyCode? {
        let key = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let code = regionToCurrency[key] else { return nil }
        return CurrencyCode(unchecked: code)
    }
}

private let regionToCurrency: [String: String] = [
    // Southeast Asia
    "MY": "MYR", "SG": "SGD", "TH": "THB", "ID": "IDR", "VN": "VND",
    "PH": "PHP", "KH": "KHR", "LA": "LAK", "MM": "MMK", "BN": "BND",
    // East Asia
    "JP": "JPY", "KR": "KRW", "CN": "CNY", "HK": "HKD", "TW": "TWD", "MO": "MOP",
    // South and Central Asia
    "IN": "INR", "LK": "LKR", "BD": "BDT", "PK": "PKR", "NP": "NPR", "KZ": "KZT",
    // Middle East
    "AE": "AED", "SA": "SAR", "QA": "QAR", "KW": "KWD", "BH": "BHD",
    "OM": "OMR", "IL": "ILS", "TR": "TRY", "JO": "JOD",
    // Oceania
    "AU": "AUD", "NZ": "NZD", "FJ": "FJD", "PG": "PGK",
    // Eurozone
    "AT": "EUR", "BE": "EUR", "CY": "EUR", "DE": "EUR", "EE": "EUR", "ES": "EUR",
    "FI": "EUR", "FR": "EUR", "GR": "EUR", "HR": "EUR", "IE": "EUR", "IT": "EUR",
    "LT": "EUR", "LU": "EUR", "LV": "EUR", "MT": "EUR", "NL": "EUR", "PT": "EUR",
    "SI": "EUR", "SK": "EUR",
    // Rest of Europe
    "GB": "GBP", "CH": "CHF", "NO": "NOK", "SE": "SEK", "DK": "DKK",
    "PL": "PLN", "CZ": "CZK", "HU": "HUF", "RO": "RON", "BG": "BGN", "IS": "ISK",
    // Americas
    "US": "USD", "CA": "CAD", "MX": "MXN", "BR": "BRL", "AR": "ARS",
    "CL": "CLP", "CO": "COP", "PE": "PEN", "UY": "UYU",
    // Africa
    "ZA": "ZAR", "EG": "EGP", "MA": "MAD", "KE": "KES", "NG": "NGN", "TZ": "TZS"
]
