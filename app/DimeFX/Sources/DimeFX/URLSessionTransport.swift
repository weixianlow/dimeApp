import Foundation

#if canImport(FoundationNetworking)
    // Linux splits URLSession into a separate module. Only needed so the package can be
    // built and tested off-device; on iOS this import does not exist and is skipped.
    import FoundationNetworking
#endif

public struct URLSessionTransport: HTTPFetching {
    private let session: URLSession
    private let timeout: TimeInterval

    /// - Parameter timeout: kept short on purpose. Rate fetching is always speculative —
    ///   nothing the user is waiting on should ever be behind this call — so failing
    ///   quickly and letting the reconciler retry beats hanging on a hotel network.
    public init(session: URLSession = .shared, timeout: TimeInterval = 10) {
        self.session = session
        self.timeout = timeout
    }

    public enum Failure: Error {
        case transport(any Error)
        case httpStatus(Int)
    }

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadRevalidatingCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Failure.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw Failure.httpStatus(http.statusCode)
        }
        return data
    }
}
