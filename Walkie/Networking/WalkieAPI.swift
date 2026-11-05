import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol WalkieAPIClient: Sendable {
    func token(channel: String, name: String) async throws -> TokenResponse
    /// Takes the channel lock. On success the server grants `canPublish` over LiveKit.
    func requestFloor(_ credentials: FloorCredentials) async throws
    func releaseFloor(_ credentials: FloorCredentials) async throws
}

/// JSON client for the web walkie API server (not the Vite dev server).
struct HTTPWalkieAPI: WalkieAPIClient {
    let baseURL: URL
    var session: URLSession = .shared
    var timeout: TimeInterval = 10

    func token(channel: String, name: String) async throws -> TokenResponse {
        let data = try await post("token", body: TokenRequest(channel: channel, name: name))
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw WalkieAPIError.invalidResponse
        }
    }

    func requestFloor(_ credentials: FloorCredentials) async throws {
        _ = try await post("floor/request", body: credentials)
    }

    func releaseFloor(_ credentials: FloorCredentials) async throws {
        _ = try await post("floor/release", body: credentials)
    }

    func report(_ credentials: FloorCredentials) async throws {
        _ = try await post("report", body: credentials)
    }

    func makeRequest(_ path: String, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func post(_ path: String, body: some Encodable) async throws -> Data {
        let request = try makeRequest(path, body: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw WalkieAPIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw WalkieAPIError.invalidResponse }
        if let error = WalkieAPIError.from(status: http.statusCode, body: data) { throw error }
        return data
    }
}
