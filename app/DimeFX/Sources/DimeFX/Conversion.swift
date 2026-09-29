import Foundation

/// How much the quote used for a conversion had aged by the time it was applied.
public enum RateFreshness: Hashable, Sendable {
    /// Quoted within the tolerance window.
    case fresh
    /// Older than the tolerance window. The conversion still happened, but the UI should
    /// mark it and the reconciler should revisit it.
    case stale(byDays: Int)
}

/// A conversion that was actually performed, carrying everything needed to audit it later.
///
/// Every field here is meant to be persisted alongside the transaction. Recomputing a
/// conversion at read time would mean last March's budget silently changing every morning
/// as rates move, so the rate that was applied is recorded rather than re-derived.
public struct ConversionResult: Hashable, Sendable {
    public let original: Money
    public let converted: Money
    public let multiplier: Decimal
    public let rateDate: Date
    public let provider: String
    public let derivation: RateDerivation
    public let freshness: RateFreshness

    public var isStale: Bool {
        if case .stale = freshness { return true }
        return false
    }
}

/// The outcome of asking for a conversion.
public enum ConversionOutcome: Hashable, Sendable {
    case converted(ConversionResult)
    /// No usable quote was available — typically offline abroad with roaming disabled.
    /// The transaction must still be recorded; the amount is carried unconverted so a
    /// later reconciliation pass can fill in the home-currency figure.
    case pending(Money)

    public var result: ConversionResult? {
        if case let .converted(result) = self { return result }
        return nil
    }
}

public struct CurrencyConverter: Sendable {
    public let home: CurrencyCode
    /// How old a quote may be before it counts as stale.
    ///
    /// Four days by default. Central banks do not publish at weekends, so a Saturday
    /// purchase legitimately uses Friday's quote, and a long weekend stretches that
    /// further. Flagging those as stale would cry wolf on ordinary travel.
    public let tolerance: TimeInterval

    public static let defaultTolerance: TimeInterval = 4 * 24 * 60 * 60

    public init(home: CurrencyCode, tolerance: TimeInterval = CurrencyConverter.defaultTolerance) {
        self.home = home
        self.tolerance = tolerance
    }

    /// Converts into the home currency, never throwing and never blocking.
    public func convertToHome(_ money: Money, using table: RateTable, asOf now: Date) -> ConversionOutcome {
        convert(money, to: home, using: table, asOf: now)
    }

    public func convert(
        _ money: Money,
        to target: CurrencyCode,
        using table: RateTable,
        asOf now: Date
    ) -> ConversionOutcome {
        guard let resolved = table.resolve(from: money.currency, to: target) else {
            return .pending(money)
        }

        let converted = Money(money.amount * resolved.multiplier, target).rounded()

        return .converted(
            ConversionResult(
                original: money,
                converted: converted,
                multiplier: resolved.multiplier,
                rateDate: resolved.date,
                provider: resolved.provider,
                derivation: resolved.derivation,
                freshness: freshness(of: resolved.date, asOf: now)
            )
        )
    }

    func freshness(of rateDate: Date, asOf now: Date) -> RateFreshness {
        let age = now.timeIntervalSince(rateDate)
        guard age > tolerance else { return .fresh }
        let days = Int((age / 86_400).rounded(.down))
        return .stale(byDays: days)
    }
}
