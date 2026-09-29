import Foundation
import Testing

@testable import DimeFX

@Suite("Choosing the currency for a new transaction")
struct CurrencyResolutionTests {
    let resolver = CurrencyResolver(home: .myr)

    @Test("An explicitly supplied currency always wins")
    func explicitWins() {
        let resolved = resolver.resolve(explicit: .jpy, regionCode: "TH")
        #expect(resolved.currency == .jpy)
        #expect(resolved.source == .explicit)
        #expect(!resolved.wasInferred)
    }

    @Test("Falls back to the region when nothing was stated")
    func infersFromRegion() {
        let resolved = resolver.resolve(regionCode: "JP")
        #expect(resolved.currency == .jpy)
        #expect(resolved.source == .inferredFromRegion("JP"))
        #expect(resolved.wasInferred)
    }

    @Test("Falls back to home when there is no region either")
    func fallsBackHome() {
        let resolved = resolver.resolve()
        #expect(resolved.currency == .myr)
        #expect(resolved.source == .homeDefault)
    }

    @Test("Falls back to home for a region it does not recognise")
    func unknownRegion() {
        let resolved = resolver.resolve(regionCode: "ZZ")
        #expect(resolved.currency == .myr)
        #expect(resolved.source == .homeDefault)
    }

    @Test("Being at home resolves to the home currency through the region path")
    func atHome() {
        let resolved = resolver.resolve(regionCode: "MY")
        #expect(resolved.currency == .myr)
        #expect(resolved.source == .inferredFromRegion("MY"))
    }

    @Test("Region codes are matched case-insensitively")
    func caseInsensitive() {
        #expect(resolver.resolve(regionCode: "jp").currency == .jpy)
        #expect(resolver.resolve(regionCode: " Sg ").currency == .sgd)
        #expect(resolver.resolve(regionCode: " Sg ").source == .inferredFromRegion("SG"))
    }

    @Test("Covers the destinations this app was built for")
    func travelCoverage() {
        let expected: [String: String] = [
            "SG": "SGD", "TH": "THB", "ID": "IDR", "VN": "VND", "JP": "JPY",
            "KR": "KRW", "TW": "TWD", "HK": "HKD", "CN": "CNY", "AE": "AED",
            "GB": "GBP", "US": "USD", "AU": "AUD", "DE": "EUR", "FR": "EUR"
        ]
        for (region, currency) in expected {
            #expect(CurrencyResolver.currency(forRegion: region)?.rawValue == currency, "region \(region)")
        }
    }

    @Test("Every mapped currency is a well-formed, recognised ISO 4217 code")
    func mappingIsWellFormed() {
        for region in ["MY", "JP", "KW", "VN", "IS", "NG"] {
            let code = CurrencyResolver.currency(forRegion: region)
            #expect(code != nil)
            #expect(CurrencyCode(code!.rawValue) != nil)
            #expect(code!.isRecognised)
        }
    }
}

@Suite("Resolving with what the amount text revealed")
struct ParsedCurrencyResolutionTests {
    let resolver = CurrencyResolver(home: .myr)

    @Test("A currency named in the text is trusted without consulting the region")
    func textNamesCurrency() {
        let parsed = AmountParser.parse("€12.34")
        let resolved = resolver.resolve(parsed: parsed, regionCode: "TH")
        #expect(resolved.currency == .eur)
        #expect(resolved.source == .parsedFromText)
        #expect(resolved.confidence == .high)
    }

    @Test("An explicit Currency Code still outranks the text")
    func explicitOutranksText() {
        // The Wallet trigger's own Currency Code is authoritative; the formatted string is
        // only a fallback for when the shortcut leaves that field unmapped.
        let parsed = AmountParser.parse("$25.00")
        let resolved = resolver.resolve(explicit: .sgd, parsed: parsed, regionCode: "US")
        #expect(resolved.currency == .sgd)
        #expect(resolved.source == .explicit)
    }

    @Test("The region settles a shared symbol")
    func regionDisambiguatesSymbol() {
        // A dollar sign tapped in Singapore is SGD, even though a bare $ usually means USD.
        let resolved = resolver.resolve(parsed: AmountParser.parse("$25.00"), regionCode: "SG")
        #expect(resolved.currency == .sgd)
        #expect(resolved.source == .ambiguousSymbolResolvedByRegion("SG"))
        #expect(resolved.confidence == .medium)

        let yen = resolver.resolve(parsed: AmountParser.parse("¥12,000"), regionCode: "JP")
        #expect(yen.currency == .jpy)

        let yuan = resolver.resolve(parsed: AmountParser.parse("¥12,000"), regionCode: "CN")
        #expect(yuan.currency == CurrencyCode(unchecked: "CNY"))
    }

    @Test("Falls back to the most common reading when neither region nor home fits")
    func defaultsToCommonestReading() {
        // A dollar amount tapped in Japan is not yen and is not ringgit. USD is the least
        // bad answer, but it is explicitly marked as the weakest one.
        let resolved = resolver.resolve(parsed: AmountParser.parse("$25.00"), regionCode: "JP")
        #expect(resolved.currency == .usd)
        #expect(resolved.source == .ambiguousSymbolDefaulted)
        #expect(resolved.confidence == .low)
    }

    @Test("Uses the home currency when it is among the candidates and there is no region")
    func homeAmongCandidates() {
        let resolver = CurrencyResolver(home: .sgd)
        let resolved = resolver.resolve(parsed: AmountParser.parse("$25.00"))
        #expect(resolved.currency == .sgd)
        #expect(resolved.source == .ambiguousSymbolResolvedByHome)
    }

    @Test("Text with no currency in it falls through to the region")
    func plainNumberUsesRegion() {
        let resolved = resolver.resolve(parsed: AmountParser.parse("12.34"), regionCode: "JP")
        #expect(resolved.currency == .jpy)
        #expect(resolved.source == .inferredFromRegion("JP"))
    }

    @Test("With nothing to go on at all, home wins and says so")
    func nothingToGoOn() {
        let resolved = resolver.resolve(parsed: AmountParser.parse("12.34"))
        #expect(resolved.currency == .myr)
        #expect(resolved.source == .homeDefault)
        #expect(resolved.confidence == .low)
    }

    @Test("Confidence orders the ways an answer can be reached")
    func confidenceOrdering() {
        #expect(CurrencySource.explicit.confidence > CurrencySource.inferredFromRegion("JP").confidence)
        #expect(CurrencySource.inferredFromRegion("JP").confidence > CurrencySource.homeDefault.confidence)
        #expect(CurrencySource.parsedFromText.confidence == .high)
        #expect(CurrencySource.ambiguousSymbolDefaulted.confidence == .low)
    }
}

@Suite("End to end: text in, converted money out")
struct ShortcutPipelineTests {
    let resolver = CurrencyResolver(home: .myr)
    let converter = CurrencyConverter(home: .myr)

    let table = RateTable([
        ExchangeRate(base: .myr, quote: .jpy, rate: Decimal(string: "38.609")!,
                     date: ISODay.date(from: "2026-09-29")!, provider: "Frankfurter"),
        ExchangeRate(base: .myr, quote: .sgd, rate: Decimal(string: "0.31325")!,
                     date: ISODay.date(from: "2026-09-29")!, provider: "Frankfurter")
    ])

    /// Mirrors what the intent will do: take whatever the automation supplied, work out the
    /// currency, then convert. Kept as a test so the ordering of those steps is pinned even
    /// though the intent itself cannot be built here.
    private func log(_ text: String, currencyCode: String? = nil, region: String? = nil) -> ConversionOutcome {
        let parsed = AmountParser.parse(text)
        let resolved = resolver.resolve(
            explicit: currencyCode.flatMap(CurrencyCode.init),
            parsed: parsed,
            regionCode: region
        )
        let money = Money(parsed?.amount ?? 0, resolved.currency)
        return converter.convertToHome(money, using: table, asOf: ISODay.date(from: "2026-09-29")!)
    }

    @Test("A Tokyo tap with the Currency Code mapped")
    func tokyoWithCurrencyCode() throws {
        let result = try #require(log("12000", currencyCode: "JPY").result)
        #expect(result.original == Money(12_000, .jpy))
        #expect(result.converted.currency == .myr)
        #expect(result.converted.amount > 300)
        #expect(result.converted.amount < 320)
    }

    @Test("The same tap with Currency Code left unmapped, recovered from the formatted amount")
    func tokyoWithoutCurrencyCode() throws {
        let result = try #require(log("¥12,000", region: "JP").result)
        #expect(result.original == Money(12_000, .jpy))
        #expect(result.converted.amount > 300)
        #expect(result.converted.amount < 320)
    }

    @Test("A home-currency tap needs no conversion and no network")
    func homeTap() throws {
        let result = try #require(log("RM 45.90").result)
        #expect(result.converted == Money(Decimal(string: "45.90")!, .myr))
        #expect(result.derivation == .identity)
    }

    @Test("A currency with no cached quote is recorded rather than dropped")
    func unknownCurrencyStillRecords() {
        let outcome = log("฿450", region: "TH")
        #expect(outcome == .pending(Money(450, .thb)))
    }
}
