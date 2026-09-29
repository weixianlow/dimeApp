import Foundation

/// A single quote: one unit of `base` buys `rate` units of `quote`, as published on `date`.
///
/// `date` is per-rate rather than per-response on purpose. The upstream API returns
/// mixed dates in one payload — a request covering MYR to JPY, INR and TWD came back
/// with JPY quoted today and INR and TWD quoted the previous day — so a single
/// "fetched at" timestamp for the batch would overstate the freshness of the laggards.
public struct ExchangeRate: Hashable, Sendable, Codable {
    public let base: CurrencyCode
    public let quote: CurrencyCode
    public let rate: Decimal
    public let date: Date
    public let provider: String

    public init(base: CurrencyCode, quote: CurrencyCode, rate: Decimal, date: Date, provider: String) {
        self.base = base
        self.quote = quote
        self.rate = rate
        self.date = date
        self.provider = provider
    }

    /// The same quote expressed the other way round.
    public func inverted() -> ExchangeRate? {
        guard rate > 0 else { return nil }
        return ExchangeRate(
            base: quote,
            quote: base,
            rate: 1 / rate,
            date: date,
            provider: provider
        )
    }
}

/// How the multiplier used for a conversion was arrived at.
///
/// Kept on the result so the app can explain itself later: a cross-rate through a
/// pivot currency is a weaker claim than a directly published quote.
public enum RateDerivation: Hashable, Sendable, Codable {
    case identity
    case direct
    case inverted
    case crossed(via: CurrencyCode)
}
