import Foundation

/// Where the currency for a transaction came from.
///
/// Persisting this matters: a currency that was guessed from GPS deserves a different
/// level of trust in the UI than one the Shortcut stated outright.
public enum CurrencySource: Hashable, Sendable {
    case explicit
    case inferredFromRegion(String)
    case homeDefault
}

public struct ResolvedCurrency: Hashable, Sendable {
    public let currency: CurrencyCode
    public let source: CurrencySource

    public var wasInferred: Bool {
        if case .inferredFromRegion = source { return true }
        return false
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
    ///   - explicit: a currency stated by the caller, e.g. a Shortcuts parameter. Always wins.
    ///   - regionCode: ISO 3166-1 alpha-2 country from reverse geocoding, when available.
    public func resolve(explicit: CurrencyCode? = nil, regionCode: String? = nil) -> ResolvedCurrency {
        if let explicit {
            return ResolvedCurrency(currency: explicit, source: .explicit)
        }

        if let regionCode,
           let inferred = Self.currency(forRegion: regionCode) {
            return ResolvedCurrency(
                currency: inferred,
                source: .inferredFromRegion(regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            )
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
