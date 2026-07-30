import Foundation

enum CursorAPIError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Cursor API URL."
        case .invalidResponse:
            return "Cursor returned an unexpected response."
        case .unauthorized:
            return "Cursor session is no longer valid. Sign in again with `cursor-agent login`."
        case .serverError(let statusCode):
            return "Cursor server error: \(statusCode)"
        case .decodingError:
            return "Failed to decode Cursor usage response."
        }
    }
}

protocol CursorAPIServing: Sendable {
    func fetchUsageSummary(sessionToken: String, subject: String) async throws -> CursorUsageSummaryResponse
}

/// Talks to the private `cursor.com` dashboard API. There is no public
/// contract for individual-account usage; see `docs/providers/cursor.md` for
/// the endpoints, auth format and units this client relies on.
final class CursorAPIClient: CursorAPIServing {
    private let session: URLSession
    private let baseURL: String

    init(session: URLSession? = nil, baseURL: String = Constants.Cursor.baseURL) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Constants.API.requestTimeout
            config.timeoutIntervalForResource = Constants.API.resourceTimeout
            self.session = URLSession(configuration: config)
        }
        self.baseURL = baseURL
    }

    func fetchUsageSummary(sessionToken: String, subject: String) async throws -> CursorUsageSummaryResponse {
        guard let url = URL(string: baseURL)?.appendingPathComponent("/api/usage-summary") else {
            throw CursorAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            Self.cookieHeader(sessionToken: sessionToken, subject: subject),
            forHTTPHeaderField: "Cookie"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CursorAPIError.invalidResponse
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorAPIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200:
            return try Self.decodeUsageSummary(data)
        case 401:
            throw CursorAPIError.unauthorized
        default:
            throw CursorAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    private static func decodeUsageSummary(_ data: Data) throws -> CursorUsageSummaryResponse {
        let decoder = JSONDecoder()
        // Dates arrive as ISO-8601 with fractional seconds
        // (e.g. "2026-07-18T10:44:30.000Z"), which the built-in `.iso8601`
        // strategy does not support.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                return date
            }

            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
        do {
            return try decoder.decode(CursorUsageSummaryResponse.self, from: data)
        } catch {
            throw CursorAPIError.decodingError
        }
    }

    /// Percent-encodes only the RFC 3986 unreserved characters, matching the
    /// format the `cursor.com` web client sends (`|` in the WorkOS subject
    /// must become `%7C`, `-`/`_` stay literal).
    private static let subjectAllowedCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func cookieHeader(sessionToken: String, subject: String) -> String {
        let encodedSubject = subject.addingPercentEncoding(
            withAllowedCharacters: subjectAllowedCharacters
        ) ?? subject
        return "WorkosCursorSessionToken=\(encodedSubject)%3A%3A\(sessionToken)"
    }
}
