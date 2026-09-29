import Foundation

/// URL construction for the Frankfurter API, kept separate from transport so it can be
/// asserted on without a network round trip.
///
/// Frankfurter needs no API key. That is a deliberate selection criterion rather than a
/// convenience: an FX provider requiring a key would mean shipping a secret inside an app
/// binary, and there is no safe way to do that. If a keyed provider ever becomes necessary
/// for coverage reasons, the key belongs in the Keychain and must never be committed.
public enum FrankfurterEndpoint {
    public static let host = "api.frankfurter.dev"
    public static let providerName = "Frankfurter"

    /// `v2` is current; `v1` is deprecated upstream though it still responds.
    public static func rates(
        base: CurrencyCode,
        quotes: [CurrencyCode],
        on day: Date? = nil,
        restrictedToProviders providers: [String] = []
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v2/rates"

        var items = [URLQueryItem(name: "base", value: base.rawValue)]

        if !quotes.isEmpty {
            let sorted = quotes.map(\.rawValue).sorted().joined(separator: ",")
            items.append(URLQueryItem(name: "quotes", value: sorted))
        }
        if let day {
            items.append(URLQueryItem(name: "date", value: ISODay.string(from: day)))
        }
        if !providers.isEmpty {
            items.append(URLQueryItem(name: "providers", value: providers.joined(separator: ",")))
        }

        components.queryItems = items
        return components.url!
    }
}

/// `yyyy-MM-dd` in UTC, which is how the API both accepts and reports quote dates.
///
/// Public because the app needs to render the date a quote was published — "converted at
/// Friday's rate" is the sort of thing worth showing next to a stale conversion.
public enum ISODay {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func string(from date: Date) -> String { formatter.string(from: date) }
    public static func date(from string: String) -> Date? { formatter.date(from: string) }
}

public struct FrankfurterDecoder: Sendable {
    public init() {}

    /// The payload is a flat array, one element per quote, each carrying its own date.
    private struct Row: Decodable {
        let date: String
        let base: String
        let quote: String
        let rate: Decimal
    }

    public enum Failure: Error, Equatable {
        case malformedPayload(String)
        case unusableRow(String)
    }

    public func decode(_ data: Data) throws -> [ExchangeRate] {
        let rows: [Row]
        do {
            rows = try JSONDecoder().decode([Row].self, from: data)
        } catch {
            throw Failure.malformedPayload(String(describing: error))
        }

        return try rows.map { row in
            guard let base = CurrencyCode(row.base) else {
                throw Failure.unusableRow("base '\(row.base)'")
            }
            guard let quote = CurrencyCode(row.quote) else {
                throw Failure.unusableRow("quote '\(row.quote)'")
            }
            guard let date = ISODay.date(from: row.date) else {
                throw Failure.unusableRow("date '\(row.date)'")
            }
            guard row.rate > 0 else {
                throw Failure.unusableRow("non-positive rate for \(row.base)/\(row.quote)")
            }
            return ExchangeRate(
                base: base,
                quote: quote,
                rate: row.rate,
                date: date,
                provider: FrankfurterEndpoint.providerName
            )
        }
    }
}

/// Transport seam. Production supplies a `URLSession`-backed implementation; tests supply
/// canned bytes so the decoding and conversion paths stay verifiable offline.
public protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

public protocol ExchangeRateProviding: Sendable {
    func rates(base: CurrencyCode, quotes: [CurrencyCode], on day: Date?) async throws -> [ExchangeRate]
}

public struct FrankfurterProvider: ExchangeRateProviding {
    private let transport: any HTTPFetching
    private let decoder: FrankfurterDecoder
    private let providers: [String]

    /// - Parameter providers: pass `["ecb"]` to pin quotes to the European Central Bank
    ///   alone. Left empty, Frankfurter blends across its full set of official sources,
    ///   which is what gives coverage of currencies the ECB does not publish.
    public init(
        transport: any HTTPFetching,
        decoder: FrankfurterDecoder = FrankfurterDecoder(),
        restrictedToProviders providers: [String] = []
    ) {
        self.transport = transport
        self.decoder = decoder
        self.providers = providers
    }

    public func rates(base: CurrencyCode, quotes: [CurrencyCode], on day: Date? = nil) async throws -> [ExchangeRate] {
        let url = FrankfurterEndpoint.rates(
            base: base,
            quotes: quotes,
            on: day,
            restrictedToProviders: providers
        )
        let data = try await transport.data(from: url)
        return try decoder.decode(data)
    }
}
