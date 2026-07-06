//
//  APIService.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case serverError(statusCode: Int)
    case unauthorized // 401
    case rateLimited(retryAfter: TimeInterval?)  // 429
    case networkError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unauthorized:
            return "Unauthorized - check credentials"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited - retry after \(Int(seconds))s"
            }
            return "Rate limited - please wait"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

class APIService: APIServiceProtocol {
    private let baseURL = Constants.API.baseURL
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = Constants.API.requestTimeout
            config.timeoutIntervalForResource = Constants.API.resourceTimeout
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Endpoints
    enum Endpoint {
        case usage

        var path: String {
            switch self {
            case .usage: return Constants.API.usageEndpoint
            }
        }
    }

    // MARK: - Methods

    /// Fetch usage data without retry
    func fetchUsage(token: String) async throws -> UsageData {
        guard let url = URL(string: baseURL)?.appendingPathComponent(Endpoint.usage.path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = headers(token: token)

        let (data, response) = try await session.data(for: request)

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            let debugPath = "/tmp/claudemeter_debug.txt"
            let entry = "[\(Date())] Status: \((response as? HTTPURLResponse)?.statusCode ?? -1)\n\(jsonString)\n---\n"
            if let existing = try? String(contentsOfFile: debugPath, encoding: .utf8) {
                try? (existing + entry).write(toFile: debugPath, atomically: true, encoding: .utf8)
            } else {
                try? entry.write(toFile: debugPath, atomically: true, encoding: .utf8)
            }
        }
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                // The API returns ISO 8601 dates with fractional seconds
                // (e.g. "2026-02-19T07:00:00.125129+00:00") which the built-in
                // .iso8601 strategy does NOT support. Use a custom formatter.
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateString = try container.decode(String.self)

                    let isoFormatter = ISO8601DateFormatter()
                    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = isoFormatter.date(from: dateString) {
                        return date
                    }

                    // Fallback: try without fractional seconds
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    if let date = fallbackFormatter.date(from: dateString) {
                        return date
                    }
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
                }
                return try decoder.decode(UsageData.self, from: data)
            } catch {
                print("APIService: Decoding error: \(error)")
                throw APIError.decodingError
            }
        case 401:
            throw APIError.unauthorized
        case 429:
            let retryAfter = Self.parseRetryAfter(response: httpResponse, body: data)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Retry-After parsing

    /// Extract the retry-after duration in seconds from a 429 response.
    /// Checks (in order): `Retry-After` header as seconds, `Retry-After` as HTTP-date,
    /// JSON body `error.retry_after` field, and natural-language patterns in the body
    /// like "retry after 3600s" / "try again in 60 seconds".
    /// Returns nil if no usable value can be extracted. Zero is treated as nil.
    static func parseRetryAfter(response: HTTPURLResponse, body: Data) -> TimeInterval? {
        // 1. Retry-After header as integer seconds
        if let headerValue = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(headerValue), seconds > 0 {
                return seconds
            }
            // 2. Retry-After header as HTTP-date
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = TimeZone(identifier: "GMT")
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = dateFormatter.date(from: headerValue) {
                let delta = date.timeIntervalSinceNow
                if delta > 0 { return delta }
            }
        }

        // 3. JSON body inspection
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if let error = json["error"] as? [String: Any] {
                if let retryAfter = error["retry_after"] as? TimeInterval, retryAfter > 0 {
                    return retryAfter
                }
                if let retryAfter = (error["retry_after"] as? NSNumber)?.doubleValue, retryAfter > 0 {
                    return retryAfter
                }
                if let message = error["message"] as? String,
                   let parsed = parseDurationFromText(message) {
                    return parsed
                }
            }
            if let message = json["message"] as? String,
               let parsed = parseDurationFromText(message) {
                return parsed
            }
        }

        // 4. Plain-text body fallback
        if let text = String(data: body, encoding: .utf8),
           let parsed = parseDurationFromText(text) {
            return parsed
        }

        return nil
    }

    /// Extract a duration in seconds from free-form text.
    /// Recognizes phrases like "retry after 3600s", "retry after 120 seconds",
    /// "try again in 5 minutes", "wait 2 hours". Returns nil if nothing matches.
    static func parseDurationFromText(_ text: String) -> TimeInterval? {
        let lowered = text.lowercased()

        // seconds: "retry after 3600s", "retry after 120 seconds", "in 60s", "wait 60 seconds"
        if let value = firstNumberMatch(in: lowered, pattern: #"(\d+(?:\.\d+)?)\s*(?:s(?:econds?)?|secs?)\b"#),
           value > 0 {
            return value
        }

        // minutes
        if let value = firstNumberMatch(in: lowered, pattern: #"(\d+(?:\.\d+)?)\s*(?:m(?:inutes?)?|mins?)\b"#),
           value > 0 {
            return value * 60
        }

        // hours
        if let value = firstNumberMatch(in: lowered, pattern: #"(\d+(?:\.\d+)?)\s*(?:h(?:ours?)?|hrs?)\b"#),
           value > 0 {
            return value * 3600
        }

        return nil
    }

    private static func firstNumberMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2,
              let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[numberRange])
    }

    func validateToken(_ token: String) async -> Bool {
        do {
            _ = try await fetchUsage(token: token)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Web API Fallback

    func fetchUsageFromWeb(sessionKey: String, organizationId: String) async throws -> (UsageData, String?) {
        let path = String(format: Constants.API.webUsageEndpoint, organizationId)
        guard let url = URL(string: Constants.API.webBaseURL + path) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue(Constants.API.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
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
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
                }
                let decoded = try decoder.decode(UsageData.self, from: data)

                // Extract refreshed sessionKey from set-cookie header
                let refreshedSessionKey: String? = {
                    guard let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") else { return nil }
                    let components = setCookie.components(separatedBy: ";")
                    guard let keyValue = components.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("sessionKey=") }) else { return nil }
                    return keyValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "sessionKey=", with: "")
                }()

                return (decoded, refreshedSessionKey)
            } catch {
                print("APIService: Web API decoding error - \(error)")
                throw APIError.decodingError
            }
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            let retryAfter = Self.parseRetryAfter(response: httpResponse, body: data)
            throw APIError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        default:
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Headers
    private func headers(token: String) -> [String: String] {
        return [
            "Authorization": "Bearer \(token)",
            "User-Agent": Constants.API.userAgent,
            "anthropic-beta": Constants.API.anthropicBeta,
            "Accept": Constants.API.acceptType,
            "Content-Type": Constants.API.contentType
        ]
    }
}

