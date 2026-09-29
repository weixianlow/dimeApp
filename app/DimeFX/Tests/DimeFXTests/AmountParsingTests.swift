import Foundation
import Testing

@testable import DimeFX

@Suite("Reading an amount out of text")
struct AmountParsingTests {
    @Test("Reads a plain number with no currency attached")
    func plainNumber() throws {
        let parsed = try #require(AmountParser.parse("45.90"))
        #expect(parsed.amount == Decimal(string: "45.90")!)
        #expect(parsed.currency == nil)
        #expect(parsed.candidates.isEmpty)
    }

    @Test("Reads a recognised ISO code, whichever side of the number it sits on")
    func isoCode() throws {
        #expect(try #require(AmountParser.parse("USD 14.50")).currency == .usd)
        #expect(try #require(AmountParser.parse("14.50 USD")).currency == .usd)
        #expect(try #require(AmountParser.parse("MYR45.90")).currency == .myr)
        #expect(try #require(AmountParser.parse("14.50 usd")).currency == .usd)
    }

    @Test("Will not mistake a merchant fragment for a currency code")
    func rejectsUnknownThreeLetterRuns() throws {
        // Three letters is not enough; it has to be a currency the app knows about.
        let parsed = try #require(AmountParser.parse("BAR 12.34"))
        #expect(parsed.currency == nil)
        #expect(parsed.candidates.isEmpty)
        #expect(parsed.amount == Decimal(string: "12.34")!)
    }

    @Test("Reads symbols that belong to exactly one currency")
    func unambiguousSymbols() throws {
        #expect(try #require(AmountParser.parse("€12.34")).currency == .eur)
        #expect(try #require(AmountParser.parse("£9.99")).currency == CurrencyCode(unchecked: "GBP"))
        #expect(try #require(AmountParser.parse("RM 45.90")).currency == .myr)
        #expect(try #require(AmountParser.parse("฿450")).currency == .thb)
        #expect(try #require(AmountParser.parse("₫1500000")).currency == .vnd)
        #expect(try #require(AmountParser.parse("₩12000")).currency == CurrencyCode(unchecked: "KRW"))
    }

    @Test("Prefers the longest symbol match so prefixed dollars are not read as plain dollars")
    func longestSymbolWins() throws {
        #expect(try #require(AmountParser.parse("S$38.00")).currency == .sgd)
        #expect(try #require(AmountParser.parse("HK$100")).currency == CurrencyCode(unchecked: "HKD"))
        #expect(try #require(AmountParser.parse("NT$500")).currency == CurrencyCode(unchecked: "TWD"))
        #expect(try #require(AmountParser.parse("US$5.00")).currency == .usd)
    }

    @Test("Reports shared symbols as candidates rather than picking one")
    func ambiguousSymbols() throws {
        let dollars = try #require(AmountParser.parse("$25.00"))
        #expect(dollars.currency == nil)
        #expect(dollars.isAmbiguous)
        #expect(dollars.candidates.contains(.usd))
        #expect(dollars.candidates.contains(.sgd))
        // Most common reading first, for the case where nothing else can settle it.
        #expect(dollars.candidates.first == .usd)

        let yen = try #require(AmountParser.parse("¥12,000"))
        #expect(yen.candidates == [.jpy, CurrencyCode(unchecked: "CNY")])
        #expect(yen.amount == 12_000)
    }
}

@Suite("Decimal and grouping separators")
struct SeparatorTests {
    @Test("Treats a lone separator with three digits after it as grouping")
    func groupingShape() throws {
        // Misreading 12,000 as 12 would under-report a purchase by a factor of a thousand,
        // which is the worst outcome available here.
        #expect(try #require(AmountParser.parse("¥12,000")).amount == 12_000)
        #expect(try #require(AmountParser.parse("Rp150.000")).amount == 150_000)
        #expect(try #require(AmountParser.parse("1,234")).amount == 1_234)
    }

    @Test("Treats a lone separator with one, two or four digits after it as decimal")
    func decimalShape() throws {
        #expect(try #require(AmountParser.parse("45.90")).amount == Decimal(string: "45.90")!)
        #expect(try #require(AmountParser.parse("45,90")).amount == Decimal(string: "45.90")!)
        #expect(try #require(AmountParser.parse("12.5")).amount == Decimal(string: "12.5")!)
        #expect(try #require(AmountParser.parse("1.2345")).amount == Decimal(string: "1.2345")!)
    }

    @Test("Repeated separators can only be grouping")
    func repeatedSeparators() throws {
        #expect(try #require(AmountParser.parse("₫1.500.000")).amount == 1_500_000)
        #expect(try #require(AmountParser.parse("1,234,567")).amount == 1_234_567)
    }

    @Test("With both separators present, the later one is the decimal point")
    func mixedSeparators() throws {
        // US and European conventions, same number.
        #expect(try #require(AmountParser.parse("$1,234.56")).amount == Decimal(string: "1234.56")!)
        #expect(try #require(AmountParser.parse("1.234,56 €")).amount == Decimal(string: "1234.56")!)
        #expect(try #require(AmountParser.parse("1.234.567,89")).amount == Decimal(string: "1234567.89")!)
        #expect(try #require(AmountParser.parse("1,234,567.89")).amount == Decimal(string: "1234567.89")!)
    }

    @Test("Ignores spaces and apostrophes used for grouping")
    func exoticGrouping() throws {
        #expect(try #require(AmountParser.parse("1 234,56")).amount == Decimal(string: "1234.56")!)
        #expect(try #require(AmountParser.parse("1'234.56")).amount == Decimal(string: "1234.56")!)
        #expect(try #require(AmountParser.parse("CHF 1'234.56")).currency == CurrencyCode(unchecked: "CHF"))
    }

    @Test("Understands both minus signs and accounting parentheses")
    func negatives() throws {
        #expect(try #require(AmountParser.parse("-45.90")).amount == Decimal(string: "-45.90")!)
        #expect(try #require(AmountParser.parse("(45.90)")).amount == Decimal(string: "-45.90")!)
        #expect(try #require(AmountParser.parse("-$45.90")).amount == Decimal(string: "-45.90")!)
        // A hyphen after the digits is not a sign.
        #expect(try #require(AmountParser.parse("45.90")).amount > 0)
    }

    @Test("Returns nothing for text with no number in it")
    func noNumber() {
        #expect(AmountParser.parse("") == nil)
        #expect(AmountParser.parse("   ") == nil)
        #expect(AmountParser.parse("Starbucks") == nil)
        #expect(AmountParser.parse("$") == nil)
    }
}

@Suite("Parsing the shapes the Wallet trigger actually produces")
struct WalletInputTests {
    @Test("Handles a bare number, which is what a correctly mapped Amount property gives")
    func mappedAmountProperty() throws {
        let parsed = try #require(AmountParser.parse("12.34"))
        #expect(parsed.amount == Decimal(string: "12.34")!)
        #expect(parsed.currency == nil)
    }

    @Test("Handles a preformatted string, which is what an unmapped input gives")
    func formattedString() throws {
        // Both shapes have to work, because whether the amount arrives clean depends on
        // which property the shortcut mapped — and that is easy to get wrong.
        for (text, expected) in [("¥12,000", Decimal(12_000)), ("€8.00", Decimal(8)), ("RM45.90", Decimal(string: "45.90")!)] {
            #expect(try #require(AmountParser.parse(text)).amount == expected, "\(text)")
        }
    }

    @Test("A trip's worth of real receipt formats")
    func travelFormats() throws {
        let cases: [(String, Decimal, CurrencyCode?)] = [
            ("¥12,000", 12_000, nil),                                  // Tokyo, symbol shared with CNY
            ("₫1.500.000", 1_500_000, .vnd),                           // Hanoi
            ("฿450", 450, .thb),                                       // Bangkok
            ("S$38.00", Decimal(string: "38.00")!, .sgd),              // Changi
            ("AED 260.00", 260, CurrencyCode(unchecked: "AED")),       // Dubai
            ("RM 45.90", Decimal(string: "45.90")!, .myr)              // home
        ]
        for (text, amount, currency) in cases {
            let parsed = try #require(AmountParser.parse(text), "\(text)")
            #expect(parsed.amount == amount, "\(text)")
            #expect(parsed.currency == currency, "\(text)")
        }
    }
}
