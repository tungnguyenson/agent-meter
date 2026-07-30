import Foundation

enum CursorProviderError: Error, LocalizedError, Equatable {
    case noCredentials
    case malformedCredentials
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "Cursor is not signed in. Run `cursor-agent login` to connect."
        case .malformedCredentials:
            return "Could not read the Cursor session token."
        case .sessionExpired:
            return "Cursor session has expired. Sign in again with `cursor-agent login`."
        }
    }
}

final class CursorProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .cursor
    let metadata = ProviderMetadata(
        id: .cursor,
        displayName: "Cursor",
        shortName: "Cursor",
        symbolName: "cursorarrow"
    )
    let debugEndpoint = "\(Constants.Cursor.baseURL)/api/usage-summary"

    private let credentialsReader: CursorCredentialsReading
    private let apiClient: CursorAPIServing

    init(
        credentialsReader: CursorCredentialsReading = CursorKeychainReader(),
        apiClient: CursorAPIServing = CursorAPIClient()
    ) {
        self.credentialsReader = credentialsReader
        self.apiClient = apiClient
    }

    func configurationStatus() async -> ProviderConfigurationStatus {
        do {
            let session = try readSession()
            if let expiresAt = session.token.expiresAt, expiresAt <= Date() {
                return .authenticationRequired(CursorProviderError.sessionExpired.localizedDescription)
            }
            return .ready
        } catch let error as CursorProviderError {
            return .authenticationRequired(error.localizedDescription)
        } catch {
            return .authenticationRequired(CursorProviderError.noCredentials.localizedDescription)
        }
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        let session = try readSession()
        if let expiresAt = session.token.expiresAt, expiresAt <= Date() {
            throw CursorProviderError.sessionExpired
        }
        let summary = try await apiClient.fetchUsageSummary(
            sessionToken: session.accessToken,
            subject: session.token.subject
        )
        return CursorUsageMapper.map(summary)
    }

    func shutdown() async {}

    private func readSession() throws -> (accessToken: String, token: CursorSessionToken) {
        guard let accessToken = try credentialsReader.readAccessToken(), !accessToken.isEmpty else {
            throw CursorProviderError.noCredentials
        }
        guard let token = CursorSessionToken.decode(accessToken) else {
            throw CursorProviderError.malformedCredentials
        }
        return (accessToken, token)
    }
}
