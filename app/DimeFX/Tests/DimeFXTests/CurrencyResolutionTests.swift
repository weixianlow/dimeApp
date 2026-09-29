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

    @Test("Every mapped currency is a well-formed ISO 4217 code")
    func mappingIsWellFormed() {
        for region in ["MY", "JP", "KW", "VN", "IS", "NG"] {
            let code = CurrencyResolver.currency(forRegion: region)
            #expect(code != nil)
            #expect(CurrencyCode(code!.rawValue) != nil)
        }
    }
}
