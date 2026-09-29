import Foundation
import Testing

@testable import DimeFX

private func day(_ string: String) -> Date {
    ISODay.date(from: string)!
}

@Suite("Converting into the home currency")
struct ConversionTests {
    let converter = CurrencyConverter(home: .myr)

    let table = RateTable([
        ExchangeRate(base: .myr, quote: .jpy, rate: Decimal(string: "38.609")!, date: day("2026-09-29"), provider: "Frankfurter"),
        ExchangeRate(base: .myr, quote: .vnd, rate: Decimal(string: "6354")!, date: day("2026-09-29"), provider: "Frankfurter")
    ])

    @Test("A Tokyo receipt in yen becomes ringgit at the inverse of the cached quote")
    func convertsYenToRinggit() throws {
        let outcome = converter.convertToHome(
            Money(Decimal(12_000), .jpy),
            using: table,
            asOf: day("2026-09-29")
        )
        let result = try #require(outcome.result)

        #expect(result.converted.currency == .myr)
        #expect(result.original == Money(Decimal(12_000), .jpy))
        #expect(result.derivation == .inverted)
        #expect(result.freshness == .fresh)

        // Guards against the classic multiply-instead-of-divide inversion: 12,000 yen is
        // a few hundred ringgit, not a few hundred thousand.
        #expect(result.converted.amount > 300)
        #expect(result.converted.amount < 320)
        #expect(result.converted.amount == Money.round(Decimal(12_000) / Decimal(string: "38.609")!, scale: 2))
    }

    @Test("Converted amounts are rounded to the home currency's scale, not the source's")
    func roundsToHomeScale() throws {
        // VND has no minor units and the amounts are large; the ringgit result must still
        // land on two decimal places.
        let outcome = converter.convertToHome(
            Money(Decimal(1_500_000), .vnd),
            using: table,
            asOf: day("2026-09-29")
        )
        let result = try #require(outcome.result)
        #expect(result.converted.currency == .myr)
        #expect(Money.round(result.converted.amount, scale: 2) == result.converted.amount)
    }

    @Test("Spending at home is a no-op rather than a lookup")
    func homeCurrencyIsIdentity() throws {
        let outcome = converter.convertToHome(
            Money(Decimal(string: "49.90")!, .myr),
            using: RateTable(),
            asOf: day("2026-09-29")
        )
        let result = try #require(outcome.result)
        #expect(result.converted == Money(Decimal(string: "49.90")!, .myr))
        #expect(result.multiplier == 1)
        #expect(result.derivation == .identity)
        #expect(result.freshness == .fresh)
    }

    @Test("With no usable quote the amount is carried forward instead of lost")
    func offlineYieldsPending() {
        // Landing somewhere with roaming off must never block recording the expense.
        let outcome = converter.convertToHome(
            Money(Decimal(500), CurrencyCode(unchecked: "TWD")),
            using: table,
            asOf: day("2026-09-29")
        )
        #expect(outcome == .pending(Money(Decimal(500), CurrencyCode(unchecked: "TWD"))))
        #expect(outcome.result == nil)
    }
}

@Suite("Rate freshness")
struct FreshnessTests {
    let converter = CurrencyConverter(home: .myr)

    @Test("A quote from today is fresh")
    func sameDay() {
        #expect(converter.freshness(of: day("2026-09-29"), asOf: day("2026-09-29")) == .fresh)
    }

    @Test("A Monday purchase on Friday's quote is still fresh, because banks shut at weekends")
    func weekendGap() {
        // 2026-09-25 was a Friday; the following Monday is the 28th. Treating that
        // ordinary gap as stale would flag most travel spending for no reason.
        #expect(converter.freshness(of: day("2026-09-25"), asOf: day("2026-09-28")) == .fresh)
    }

    @Test("Beyond the tolerance window the age is reported in whole days")
    func genuinelyStale() {
        #expect(converter.freshness(of: day("2026-09-20"), asOf: day("2026-09-29")) == .stale(byDays: 9))
    }

    @Test("Tolerance is configurable for callers that need stricter quotes")
    func customTolerance() {
        let strict = CurrencyConverter(home: .myr, tolerance: 0)
        #expect(strict.freshness(of: day("2026-09-28"), asOf: day("2026-09-29")) == .stale(byDays: 1))
    }

    @Test("Stale quotes still convert, and are marked rather than refused")
    func staleStillConverts() throws {
        let table = RateTable([
            ExchangeRate(base: .myr, quote: .jpy, rate: Decimal(string: "38.609")!, date: day("2026-08-01"), provider: "Frankfurter")
        ])
        let outcome = converter.convertToHome(Money(Decimal(1_000), .jpy), using: table, asOf: day("2026-09-29"))
        let result = try #require(outcome.result)
        #expect(result.isStale)
        #expect(result.converted.amount > 0)
    }
}
