import Foundation
import Testing

@testable import DimeFX

@Suite("Currency codes")
struct CurrencyCodeTests {
    @Test("Accepts three letters and normalises case and padding")
    func normalisation() {
        #expect(CurrencyCode("myr")?.rawValue == "MYR")
        #expect(CurrencyCode(" jpy ")?.rawValue == "JPY")
    }

    @Test("Rejects anything that is not three ASCII letters")
    func rejection() {
        #expect(CurrencyCode("") == nil)
        #expect(CurrencyCode("MY") == nil)
        #expect(CurrencyCode("MYRR") == nil)
        #expect(CurrencyCode("M1R") == nil)
        #expect(CurrencyCode("MY R") == nil)
        #expect(CurrencyCode("円") == nil)
    }

    @Test("Knows the ISO 4217 minor unit exceptions")
    func minorUnits() {
        #expect(CurrencyCode.myr.minorUnits == 2)
        #expect(CurrencyCode.usd.minorUnits == 2)
        #expect(CurrencyCode.jpy.minorUnits == 0)
        #expect(CurrencyCode.vnd.minorUnits == 0)
        #expect(CurrencyCode(unchecked: "KRW").minorUnits == 0)
        #expect(CurrencyCode.kwd.minorUnits == 3)
        #expect(CurrencyCode(unchecked: "BHD").minorUnits == 3)
    }
}

@Suite("Money")
struct MoneyTests {
    @Test("Rounds to the currency's own scale, not a hardcoded two places")
    func roundingRespectsCurrency() {
        #expect(Money(Decimal(string: "1234.56789")!, .myr).rounded().amount == Decimal(string: "1234.57")!)
        #expect(Money(Decimal(string: "1234.56789")!, .jpy).rounded().amount == Decimal(string: "1235")!)
        #expect(Money(Decimal(string: "1234.56789")!, .kwd).rounded().amount == Decimal(string: "1234.568")!)
    }

    @Test("Rounds halves away from zero in both directions")
    func halfwayCases() {
        #expect(Money(Decimal(string: "0.125")!, .myr).rounded().amount == Decimal(string: "0.13")!)
        #expect(Money(Decimal(string: "-0.125")!, .myr).rounded().amount == Decimal(string: "-0.13")!)
        #expect(Money(Decimal(string: "2.5")!, .jpy).rounded().amount == Decimal(string: "3")!)
    }

    @Test("Decimal arithmetic stays exact where Double would drift")
    func decimalPrecision() {
        // 0.1 + 0.2 == 0.3 is false for Double and must be true here, because these
        // amounts get summed across a whole trip before being shown as a total.
        let total = Money(Decimal(string: "0.1")!, .myr).amount + Decimal(string: "0.2")!
        #expect(total == Decimal(string: "0.3")!)
    }
}
