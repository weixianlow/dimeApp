import Foundation
import Testing

@testable import DimeFX

private func day(_ string: String) -> Date {
    ISODay.date(from: string)!
}

private func rate(_ base: String, _ quote: String, _ value: String, _ dateString: String) -> ExchangeRate {
    ExchangeRate(
        base: CurrencyCode(unchecked: base),
        quote: CurrencyCode(unchecked: quote),
        rate: Decimal(string: value)!,
        date: day(dateString),
        provider: "test"
    )
}

@Suite("Rate resolution")
struct RateTableTests {
    // Real quotes captured from the live API on 2026-09-29, MYR base.
    let table = RateTable([
        rate("MYR", "JPY", "38.609", "2026-09-29"),
        rate("MYR", "USD", "0.24518", "2026-09-29"),
        rate("MYR", "THB", "8.2085", "2026-09-29"),
        rate("MYR", "INR", "23.49", "2026-09-28")
    ])

    @Test("A currency converts to itself at par without consulting any quote")
    func identity() {
        let resolved = RateTable().resolve(from: .myr, to: .myr)
        #expect(resolved?.multiplier == 1)
        #expect(resolved?.derivation == .identity)
    }

    @Test("Uses a published quote directly when one exists")
    func direct() throws {
        let resolved = try #require(table.resolve(from: .myr, to: .jpy))
        #expect(resolved.multiplier == Decimal(string: "38.609")!)
        #expect(resolved.derivation == .direct)
        #expect(resolved.date == day("2026-09-29"))
    }

    @Test("Inverts a quote to go the other way, which is the direction travel actually needs")
    func inverted() throws {
        // Everything is cached against MYR, but a Tokyo receipt arrives as JPY and has
        // to become MYR, so the inverse leg is the common case rather than the exotic one.
        let resolved = try #require(table.resolve(from: .jpy, to: .myr))
        #expect(resolved.derivation == .inverted)
        #expect(resolved.multiplier == 1 / Decimal(string: "38.609")!)
    }

    @Test("Round-tripping through an inverse returns the original amount")
    func inverseRoundTrip() throws {
        let toJPY = try #require(table.resolve(from: .myr, to: .jpy)).multiplier
        let toMYR = try #require(table.resolve(from: .jpy, to: .myr)).multiplier
        let original = Decimal(string: "250.00")!
        let roundTripped = original * toJPY * toMYR
        #expect(Money.round(roundTripped, scale: 2) == original)
    }

    @Test("Crosses two legs through a shared pivot when no direct quote exists")
    func crossed() throws {
        let resolved = try #require(table.resolve(from: .jpy, to: .thb))
        #expect(resolved.derivation == .crossed(via: .myr))
        // 1 JPY -> MYR -> THB
        let expected = Decimal(string: "8.2085")! / Decimal(string: "38.609")!
        #expect(resolved.multiplier == expected)
    }

    @Test("A cross-rate is only as fresh as its staler leg")
    func crossTakesOlderDate() throws {
        // JPY is quoted on the 29th but INR only on the 28th, so JPY->INR must report
        // the 28th rather than flattering itself with the newer of the two.
        let resolved = try #require(table.resolve(from: .jpy, to: CurrencyCode(unchecked: "INR")))
        #expect(resolved.date == day("2026-09-28"))
    }

    @Test("Returns nothing when neither a direct, inverse nor pivot path exists")
    func unresolvable() {
        #expect(table.resolve(from: .jpy, to: CurrencyCode(unchecked: "ZAR")) == nil)
    }

    @Test("Keeps the freshest quote when the same pair is inserted twice")
    func freshestWins() throws {
        var table = RateTable([rate("MYR", "JPY", "38.000", "2026-09-28")])
        table.insert(rate("MYR", "JPY", "38.609", "2026-09-29"))
        let resolved = try #require(table.resolve(from: .myr, to: .jpy))
        #expect(resolved.multiplier == Decimal(string: "38.609")!)

        table.insert(rate("MYR", "JPY", "1.000", "2026-09-01"))
        let unchanged = try #require(table.resolve(from: .myr, to: .jpy))
        #expect(unchanged.multiplier == Decimal(string: "38.609")!)
    }

    @Test("Refuses to invert a zero or negative rate rather than dividing by zero")
    func guardsAgainstZero() {
        let table = RateTable([rate("MYR", "XXX", "0", "2026-09-29")])
        #expect(table.resolve(from: CurrencyCode(unchecked: "XXX"), to: .myr) == nil)
    }
}
