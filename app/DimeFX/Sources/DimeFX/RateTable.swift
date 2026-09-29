import Foundation

/// An immutable set of quotes that can answer "what do I multiply by to get from A to B?".
///
/// Resolution is attempted in descending order of confidence: identity, a directly
/// published quote, the inverse of a published quote, then a cross-rate through a shared
/// pivot currency. The pivot path exists because the app caches everything against the
/// home currency, so converting a Tokyo receipt into the Thai baht view of a past trip
/// has to go through MYR.
public struct RateTable: Sendable {
    private var quotes: [Pair: ExchangeRate]

    private struct Pair: Hashable {
        let base: CurrencyCode
        let quote: CurrencyCode
    }

    public init(_ rates: [ExchangeRate] = []) {
        quotes = [:]
        for rate in rates {
            insert(rate)
        }
    }

    public mutating func insert(_ rate: ExchangeRate) {
        let pair = Pair(base: rate.base, quote: rate.quote)
        // Keep the freshest quote when the same pair arrives twice.
        if let existing = quotes[pair], existing.date >= rate.date { return }
        quotes[pair] = rate
    }

    public var isEmpty: Bool { quotes.isEmpty }

    public var all: [ExchangeRate] {
        quotes.values.sorted {
            ($0.base.rawValue, $0.quote.rawValue) < ($1.base.rawValue, $1.quote.rawValue)
        }
    }

    /// The multiplier taking an amount in `from` to an amount in `to`, with provenance.
    ///
    /// The returned date is the oldest quote involved, so a cross-rate is only ever as
    /// fresh as its staler leg.
    public func resolve(from: CurrencyCode, to: CurrencyCode) -> ResolvedRate? {
        if from == to {
            return ResolvedRate(
                multiplier: 1,
                date: .distantFuture,
                provider: "identity",
                derivation: .identity
            )
        }

        if let direct = quotes[Pair(base: from, quote: to)] {
            return ResolvedRate(
                multiplier: direct.rate,
                date: direct.date,
                provider: direct.provider,
                derivation: .direct
            )
        }

        if let reverse = quotes[Pair(base: to, quote: from)], reverse.rate > 0 {
            return ResolvedRate(
                multiplier: 1 / reverse.rate,
                date: reverse.date,
                provider: reverse.provider,
                derivation: .inverted
            )
        }

        return crossRate(from: from, to: to)
    }

    /// Finds a pivot `p` for which both legs are known, preferring the freshest option.
    private func crossRate(from: CurrencyCode, to: CurrencyCode) -> ResolvedRate? {
        var best: ResolvedRate?

        for pivot in pivotCandidates {
            guard let toFrom = leg(from: pivot, to: from), toFrom.multiplier > 0,
                  let toTo = leg(from: pivot, to: to)
            else { continue }

            let candidate = ResolvedRate(
                multiplier: toTo.multiplier / toFrom.multiplier,
                date: min(toFrom.date, toTo.date),
                provider: toTo.provider,
                derivation: .crossed(via: pivot)
            )

            if best == nil || candidate.date > best!.date {
                best = candidate
            }
        }

        return best
    }

    /// A single hop, direct or inverted, without recursing back into cross-rate search.
    private func leg(from: CurrencyCode, to: CurrencyCode) -> ResolvedRate? {
        if from == to {
            return ResolvedRate(multiplier: 1, date: .distantFuture, provider: "identity", derivation: .identity)
        }
        if let direct = quotes[Pair(base: from, quote: to)] {
            return ResolvedRate(multiplier: direct.rate, date: direct.date, provider: direct.provider, derivation: .direct)
        }
        if let reverse = quotes[Pair(base: to, quote: from)], reverse.rate > 0 {
            return ResolvedRate(multiplier: 1 / reverse.rate, date: reverse.date, provider: reverse.provider, derivation: .inverted)
        }
        return nil
    }

    private var pivotCandidates: Set<CurrencyCode> {
        var candidates = Set<CurrencyCode>()
        for pair in quotes.keys {
            candidates.insert(pair.base)
            candidates.insert(pair.quote)
        }
        return candidates
    }
}

public struct ResolvedRate: Hashable, Sendable {
    public let multiplier: Decimal
    public let date: Date
    public let provider: String
    public let derivation: RateDerivation
}
