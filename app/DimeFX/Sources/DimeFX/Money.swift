import Foundation

/// An amount paired with the currency it is denominated in.
///
/// `Decimal` rather than `Double`: converting 6,354 VND per ringgit through binary
/// floating point accumulates visible error once totals are summed over a trip.
public struct Money: Hashable, Sendable, Codable {
    public let amount: Decimal
    public let currency: CurrencyCode

    public init(_ amount: Decimal, _ currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    public var isZero: Bool { amount == 0 }

    /// Rounds to the currency's own minor-unit count, half away from zero.
    public func rounded() -> Money {
        Money(Self.round(amount, scale: currency.minorUnits), currency)
    }

    static func round(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}

extension Money: CustomStringConvertible {
    public var description: String {
        "\(rounded().amount) \(currency)"
    }
}
