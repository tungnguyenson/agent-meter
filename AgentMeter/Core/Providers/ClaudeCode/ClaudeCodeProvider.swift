import Foundation

final class ClaudeCodeProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .claudeCode
    let metadata = ProviderMetadata(
        id: .claudeCode,
        displayName: "Claude Code",
        shortName: "Claude",
        symbolName: "sparkles"
    )

    private let apiService: APIServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let secretStore: ProviderSecretStoring
    private let webOrganizationID: String

    init(
        apiService: APIServiceProtocol = APIService(),
        keychainService: KeychainServiceProtocol = KeychainService(),
        secretStore: ProviderSecretStoring = ProviderSecretStore.shared,
        webOrganizationID: String = ""
    ) {
        self.apiService = apiService
        self.keychainService = keychainService
        self.secretStore = secretStore
        self.webOrganizationID = webOrganizationID
    }

    func configurationStatus() async -> ProviderConfigurationStatus {
        guard let credentials = try? keychainService.getCredentials() else {
            return .authenticationRequired("Run `claude login` to connect Claude Code.")
        }
        guard credentials.isValid else {
            return .authenticationRequired("Claude Code credentials have expired.")
        }
        return .ready
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        guard let credentials = try keychainService.getCredentials() else {
            throw AppError.noCredentials
        }
        guard credentials.isValid else {
            throw AppError.credentialsExpired
        }

        do {
            let usage = try await apiService.fetchUsage(token: credentials.accessToken)
            return ClaudeUsageMapper.map(usage, planLabel: credentials.subscriptionType)
        } catch let error as APIError {
            if let fallback = try await webFallback() {
                return ClaudeUsageMapper.map(
                    fallback,
                    planLabel: credentials.subscriptionType
                )
            }
            throw AppError.from(error)
        }
    }

    private func webFallback() async throws -> UsageData? {
        guard !webOrganizationID.isEmpty,
              let sessionKey = try secretStore.read(
                account: ProviderSecretAccount.claudeWebSessionKey
              ),
              !sessionKey.isEmpty else {
            return nil
        }
        let (usage, refreshedKey) = try await apiService.fetchUsageFromWeb(
            sessionKey: sessionKey,
            organizationId: webOrganizationID
        )
        if let refreshedKey, !refreshedKey.isEmpty {
            try secretStore.save(
                refreshedKey,
                account: ProviderSecretAccount.claudeWebSessionKey
            )
        }
        return usage
    }
}
