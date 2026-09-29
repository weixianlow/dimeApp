import Foundation
import Testing

@testable import DimeFX

/// Captured verbatim from `api.frankfurter.dev/v2/rates?base=myr&quotes=...` on 2026-09-29.
/// Note that INR and TWD carry the previous day's date while the rest are current — the
/// mixed dates are the point of this fixture, not an accident of capture.
private let livePayload = Data("""
[{"date":"2026-09-29","base":"MYR","quote":"AED","rate":0.90043},
 {"date":"2026-09-29","base":"MYR","quote":"JPY","rate":38.609},
 {"date":"2026-09-28","base":"MYR","quote":"INR","rate":23.49},
 {"date":"2026-09-29","base":"MYR","quote":"SGD","rate":0.31325},
 {"date":"2026-09-28","base":"MYR","quote":"TWD","rate":7.7917},
 {"date":"2026-09-29","base":"MYR","quote":"VND","rate":6354}]
""".utf8)

@Suite("Decoding the rate feed")
struct FrankfurterDecoderTests {
    let decoder = FrankfurterDecoder()

    @Test("Decodes the live payload shape")
    func decodesLivePayload() throws {
        let rates = try decoder.decode(livePayload)
        #expect(rates.count == 6)
        #expect(rates.allSatisfy { $0.base == .myr })
        #expect(rates.allSatisfy { $0.provider == "Frankfurter" })
    }

    @Test("Preserves each row's own date rather than stamping the batch")
    func perRowDates() throws {
        let rates = try decoder.decode(livePayload)
        let byQuote = Dictionary(uniqueKeysWithValues: rates.map { ($0.quote.rawValue, $0) })
        #expect(byQuote["JPY"]?.date == ISODay.date(from: "2026-09-29"))
        #expect(byQuote["INR"]?.date == ISODay.date(from: "2026-09-28"))
        #expect(byQuote["TWD"]?.date == ISODay.date(from: "2026-09-28"))
    }

    @Test("Parses rates exactly, without drifting through binary floating point")
    func exactDecimals() throws {
        let rates = try decoder.decode(livePayload)
        let byQuote = Dictionary(uniqueKeysWithValues: rates.map { ($0.quote.rawValue, $0) })
        #expect(byQuote["AED"]?.rate == Decimal(string: "0.90043")!)
        #expect(byQuote["JPY"]?.rate == Decimal(string: "38.609")!)
        #expect(byQuote["VND"]?.rate == Decimal(string: "6354")!)
        #expect(byQuote["SGD"]?.rate == Decimal(string: "0.31325")!)
    }

    @Test("Rejects malformed payloads instead of producing empty rates")
    func malformed() {
        #expect(throws: FrankfurterDecoder.Failure.self) {
            try decoder.decode(Data("not json".utf8))
        }
    }

    @Test("Rejects rows the app cannot act on")
    func unusableRows() {
        let badCurrency = Data(#"[{"date":"2026-09-29","base":"MYR","quote":"XX","rate":1.0}]"#.utf8)
        #expect(throws: FrankfurterDecoder.Failure.self) { try decoder.decode(badCurrency) }

        let badDate = Data(#"[{"date":"29/09/2026","base":"MYR","quote":"JPY","rate":1.0}]"#.utf8)
        #expect(throws: FrankfurterDecoder.Failure.self) { try decoder.decode(badDate) }

        let zeroRate = Data(#"[{"date":"2026-09-29","base":"MYR","quote":"JPY","rate":0}]"#.utf8)
        #expect(throws: FrankfurterDecoder.Failure.self) { try decoder.decode(zeroRate) }
    }

    @Test("An empty result set is valid, not an error")
    func emptyIsFine() throws {
        #expect(try decoder.decode(Data("[]".utf8)).isEmpty)
    }
}

@Suite("Endpoint construction")
struct FrankfurterEndpointTests {
    @Test("Builds a v2 rates URL with sorted quotes")
    func basicURL() {
        let url = FrankfurterEndpoint.rates(base: .myr, quotes: [.jpy, .thb, .sgd])
        #expect(url.absoluteString == "https://api.frankfurter.dev/v2/rates?base=MYR&quotes=JPY,SGD,THB")
    }

    @Test("Carries no API key, because the provider requires none")
    func carriesNoSecret() {
        let url = FrankfurterEndpoint.rates(base: .myr, quotes: [.jpy])
        let query = url.query ?? ""
        #expect(!query.lowercased().contains("key"))
        #expect(!query.lowercased().contains("token"))
        #expect(!query.lowercased().contains("apikey"))
        #expect(url.user == nil)
        #expect(url.password == nil)
        #expect(url.scheme == "https")
    }

    @Test("Requests a historical quote for a back-dated entry")
    func historical() {
        let url = FrankfurterEndpoint.rates(
            base: .myr,
            quotes: [.jpy],
            on: ISODay.date(from: "2026-03-02")!
        )
        #expect(url.absoluteString.contains("date=2026-03-02"))
    }

    @Test("Pins to a single source when asked")
    func pinnedProvider() {
        let url = FrankfurterEndpoint.rates(base: .myr, quotes: [.jpy], restrictedToProviders: ["ecb"])
        #expect(url.absoluteString.contains("providers=ecb"))
    }
}

private struct StubTransport: HTTPFetching {
    let payload: Data
    func data(from _: URL) async throws -> Data { payload }
}

@Suite("Provider wiring")
struct FrankfurterProviderTests {
    @Test("Fetches and decodes without touching the network in tests")
    func fetches() async throws {
        let provider = FrankfurterProvider(transport: StubTransport(payload: livePayload))
        let rates = try await provider.rates(base: .myr, quotes: [.jpy], on: nil)
        #expect(rates.count == 6)
    }

    @Test("A fetched table converts end to end")
    func endToEnd() async throws {
        let provider = FrankfurterProvider(transport: StubTransport(payload: livePayload))
        let table = RateTable(try await provider.rates(base: .myr, quotes: [], on: nil))
        let converter = CurrencyConverter(home: .myr)

        let outcome = converter.convertToHome(
            Money(Decimal(5_000), .jpy),
            using: table,
            asOf: ISODay.date(from: "2026-09-29")!
        )
        let result = try #require(outcome.result)
        #expect(result.converted.currency == .myr)
        #expect(result.converted.amount > 120)
        #expect(result.converted.amount < 140)
    }
}
