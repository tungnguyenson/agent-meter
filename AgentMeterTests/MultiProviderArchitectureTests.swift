//
//  MultiProviderArchitectureTests.swift
//  AgentMeterTests
//
//  Contract tests for the Agent Meter multi-provider architecture.
//

import XCTest
@testable import AgentMeter

final class UsageDomainMappingTests: XCTestCase {
    func testClaudeMapperProducesProviderScopedDynamicMetrics() throws {
        // Arrange
        let fiveHourReset = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-29T10:00:00Z"))
        let sevenDayReset = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-04T10:00:00Z"))
        let source = UsageData(
            fiveHour: UsageWindow(utilization: 42, resetsAt: fiveHourReset),
            sevenDay: UsageWindow(utilization: 17, resetsAt: sevenDayReset),
            sevenDayOpus: nil,
            sevenDaySonnet: UsageWindow(utilization: 8, resetsAt: sevenDayReset),
            sevenDayDesign: UsageWindow(utilization: 63, resetsAt: sevenDayReset),
            extraUsage: ExtraUsage(
                isEnabled: true,
                monthlyLimit: 100,
                usedCredits: 25,
                utilization: 25
            ),
            fetchedAt: fiveHourReset
        )

        // Act
        let snapshot = ClaudeUsageMapper.map(source)
        let metricsByID = Dictionary(uniqueKeysWithValues: snapshot.metrics.map { ($0.id, $0) })

        // Assert
        XCTAssertEqual(snapshot.providerID, .claudeCode)
        XCTAssertEqual(snapshot.fetchedAt, fiveHourReset)
        XCTAssertEqual(metricsByID["claude.five-hour"]?.usedPercent, 42)
        XCTAssertEqual(metricsByID["claude.five-hour"]?.resetsAt, fiveHourReset)
        XCTAssertEqual(metricsByID["claude.seven-day"]?.usedPercent, 17)
        XCTAssertEqual(metricsByID["claude.seven-day-sonnet"]?.usedPercent, 8)
        XCTAssertEqual(metricsByID["claude.seven-day-design"]?.usedPercent, 63)
        XCTAssertEqual(metricsByID["claude.extra-usage"]?.category, .credits)
        XCTAssertEqual(metricsByID["claude.extra-usage"]?.usedValue, 25)
        XCTAssertEqual(metricsByID["claude.extra-usage"]?.limitValue, 100)
        XCTAssertNil(metricsByID["claude.seven-day-opus"])
    }
}

final class CodexRateLimitsMappingTests: XCTestCase {
    func testMapPrefersNamedRateLimitsAndIncludesPrimaryAndSecondaryWindows() throws {
        // Arrange
        let json = """
        {
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": "Codex",
              "planType": "pro",
              "primary": {
                "usedPercent": 12.5,
                "windowDurationMins": 300,
                "resetsAt": 1785322800
              },
              "secondary": {
                "usedPercent": 33,
                "windowDurationMins": 10080,
                "resetsAt": 1785927600
              }
            }
          },
          "rateLimits": {
            "primary": {
              "usedPercent": 99,
              "windowDurationMins": 60,
              "resetsAt": 1785322800
            }
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: json)

        // Act
        let snapshot = CodexUsageMapper.map(
            response,
            fetchedAt: Date(timeIntervalSince1970: 1_785_300_000)
        )
        let metricsByID = Dictionary(uniqueKeysWithValues: snapshot.metrics.map { ($0.id, $0) })

        // Assert
        XCTAssertEqual(snapshot.providerID, .codex)
        XCTAssertEqual(snapshot.planLabel, "pro")
        XCTAssertEqual(metricsByID.count, 2, "Legacy rateLimits must not be duplicated when named limits exist")
        XCTAssertEqual(metricsByID["codex.codex.primary"]?.usedPercent, 12.5)
        XCTAssertEqual(metricsByID["codex.codex.primary"]?.windowDuration, 5 * 60 * 60)
        XCTAssertEqual(
            metricsByID["codex.codex.primary"]?.resetsAt,
            Date(timeIntervalSince1970: 1_785_322_800)
        )
        XCTAssertEqual(metricsByID["codex.codex.secondary"]?.usedPercent, 33)
        XCTAssertEqual(metricsByID["codex.codex.secondary"]?.windowDuration, 7 * 24 * 60 * 60)
    }

    func testMapFallsBackToLegacyRateLimitsWhenNamedMapIsMissing() throws {
        // Arrange
        let json = """
        {
          "rateLimits": {
            "primary": {
              "usedPercent": 48,
              "windowDurationMins": 300,
              "resetsAt": 1785322800
            },
            "secondary": null
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: json)

        // Act
        let snapshot = CodexUsageMapper.map(response, fetchedAt: .distantPast)

        // Assert
        XCTAssertEqual(snapshot.metrics.map(\.id), ["codex.default.primary"])
        XCTAssertEqual(snapshot.metrics.first?.usedPercent, 48)
    }

    func testUnknownFieldsDoNotPreventRateLimitDecoding() throws {
        // Arrange
        let json = """
        {
          "futureField": { "anything": true },
          "rateLimitsByLimitId": {
            "review": {
              "limitId": "review",
              "limitName": "Code review",
              "unknownWindowMetadata": "ignored",
              "primary": {
                "usedPercent": 5,
                "windowDurationMins": 60,
                "resetsAt": 1785322800,
                "futureField": 123
              }
            }
          }
        }
        """.data(using: .utf8)!

        // Act
        let response = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: json)
        let snapshot = CodexUsageMapper.map(response, fetchedAt: .distantPast)

        // Assert
        XCTAssertEqual(snapshot.metrics.map(\.id), ["codex.review.primary"])
        XCTAssertEqual(snapshot.metrics.first?.title, "Code review · 1h")
    }
}

final class CursorUsageMappingTests: XCTestCase {
    /// Payload shape verified against the live `cursor.com/dashboard`
    /// Spending page on 2026-07-30; see `docs/providers/cursor.md`.
    func testMapProducesMetricsMatchingVerifiedSpendingPageValues() throws {
        // Arrange
        let json = """
        {
          "billingCycleStart": "2026-07-18T10:44:30.000Z",
          "billingCycleEnd": "2026-08-18T10:44:30.000Z",
          "membershipType": "pro",
          "individualUsage": {
            "plan": {
              "enabled": true,
              "breakdown": { "included": 2000, "bonus": 32047, "total": 34047 },
              "autoPercentUsed": 100,
              "apiPercentUsed": 88.888888888888,
              "totalPercentUsed": 98.686956521739
            },
            "onDemand": { "enabled": true, "used": 0, "limit": 500 }
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: try container.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad date")
            }
            return date
        }
        let response = try decoder.decode(CursorUsageSummaryResponse.self, from: json)

        // Act
        let snapshot = CursorUsageMapper.map(response, fetchedAt: .distantPast)
        let metricsByID = Dictionary(uniqueKeysWithValues: snapshot.metrics.map { ($0.id, $0) })

        // Assert
        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertEqual(snapshot.planLabel, "pro")
        XCTAssertEqual(metricsByID["cursor.plan.auto"]?.usedPercent, 100)
        XCTAssertEqual(metricsByID["cursor.plan.api"]?.usedPercent ?? 0, 88.888888888888, accuracy: 0.0001)
        XCTAssertEqual(
            metricsByID["cursor.plan.auto"]?.windowDuration,
            31 * 24 * 60 * 60,
            "billingCycleEnd - billingCycleStart for the verified fixture is 31 days"
        )
        let onDemand = try XCTUnwrap(metricsByID["cursor.on-demand"])
        XCTAssertEqual(onDemand.category, .credits)
        XCTAssertEqual(onDemand.usedValue, 0, "cents-to-dollars: 0 cents used")
        XCTAssertEqual(onDemand.limitValue, 5, "cents-to-dollars: 500 cents == $5 on-demand limit")
        XCTAssertEqual(onDemand.unit, "USD")
    }

    func testOnDemandDisabledProducesNoCreditsMetric() throws {
        // Arrange
        let json = """
        {
          "membershipType": "free",
          "individualUsage": {
            "plan": { "enabled": true, "autoPercentUsed": 10, "apiPercentUsed": 0 },
            "onDemand": { "enabled": false, "used": 0, "limit": 0 }
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: json)

        // Act
        let snapshot = CursorUsageMapper.map(response, fetchedAt: .distantPast)

        // Assert
        XCTAssertNil(snapshot.metric(id: "cursor.on-demand"))
        XCTAssertEqual(snapshot.metrics.map(\.id).sorted(), ["cursor.plan.api", "cursor.plan.auto"])
    }

    func testUnknownFieldsDoNotPreventDecoding() throws {
        // Arrange
        let json = """
        {
          "futureField": { "anything": true },
          "membershipType": "pro",
          "autoModelSelectedDisplayMessage": "You've used 99% of your included total usage",
          "individualUsage": {
            "plan": { "enabled": true, "autoPercentUsed": 42, "futureField": 1 },
            "onDemand": { "enabled": true, "used": 100, "limit": 500 }
          }
        }
        """.data(using: .utf8)!

        // Act
        let response = try JSONDecoder().decode(CursorUsageSummaryResponse.self, from: json)
        let snapshot = CursorUsageMapper.map(response, fetchedAt: .distantPast)

        // Assert
        XCTAssertEqual(snapshot.metric(id: "cursor.plan.auto")?.usedPercent, 42)
        XCTAssertNil(snapshot.metric(id: "cursor.plan.api"), "apiPercentUsed absent from fixture")
    }
}

final class CursorSessionTokenTests: XCTestCase {
    private func makeJWT(claims: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"])
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(base64URL(header)).\(base64URL(payload)).signature"
    }

    func testDecodeExtractsSubjectAndExpiry() {
        // Arrange
        let jwt = makeJWT(claims: [
            "sub": "google-oauth2|user_01JNRDXH3VAJ20W3XQW2NX8AD4",
            "exp": 1_786_971_980
        ])

        // Act
        let token = CursorSessionToken.decode(jwt)

        // Assert
        XCTAssertEqual(token?.subject, "google-oauth2|user_01JNRDXH3VAJ20W3XQW2NX8AD4")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_786_971_980))
    }

    func testDecodeReturnsNilForMalformedToken() {
        XCTAssertNil(CursorSessionToken.decode("not-a-jwt"))
        XCTAssertNil(CursorSessionToken.decode(""))
        XCTAssertNil(CursorSessionToken.decode("only.two"))
    }

    func testDecodeReturnsNilWhenSubjectClaimMissing() {
        let jwt = makeJWT(claims: ["exp": 1_786_971_980])
        XCTAssertNil(CursorSessionToken.decode(jwt))
    }
}

final class CursorProviderAuthenticationTests: XCTestCase {
    func testConfigurationStatusIsAuthenticationRequiredWithoutCredentials() async {
        // Arrange
        let provider = CursorProvider(
            credentialsReader: StubCursorCredentialsReader(result: .success(nil)),
            apiClient: StubCursorAPIClient(result: .failure(CursorAPIError.unauthorized))
        )

        // Act
        let status = await provider.configurationStatus()

        // Assert
        guard case .authenticationRequired = status else {
            return XCTFail("Expected authenticationRequired, got \(status)")
        }
    }

    func testConfigurationStatusIsAuthenticationRequiredWhenTokenExpired() async {
        // Arrange
        let jwt = makeExpiredJWT()
        let provider = CursorProvider(
            credentialsReader: StubCursorCredentialsReader(result: .success(jwt)),
            apiClient: StubCursorAPIClient(result: .failure(CursorAPIError.unauthorized))
        )

        // Act
        let status = await provider.configurationStatus()

        // Assert
        guard case .authenticationRequired = status else {
            return XCTFail("Expected authenticationRequired, got \(status)")
        }
    }

    func testFetchSnapshotMapsUsageWhenSessionIsValid() async throws {
        // Arrange
        let jwt = makeValidJWT(subject: "google-oauth2|user_test")
        let summary = CursorUsageSummaryResponse(
            billingCycleStart: nil,
            billingCycleEnd: nil,
            membershipType: "pro",
            individualUsage: CursorIndividualUsage(
                plan: CursorPlanUsage(
                    enabled: true,
                    breakdown: nil,
                    autoPercentUsed: 55,
                    apiPercentUsed: nil,
                    totalPercentUsed: nil
                ),
                onDemand: nil
            )
        )
        let apiClient = StubCursorAPIClient(result: .success(summary))
        let provider = CursorProvider(
            credentialsReader: StubCursorCredentialsReader(result: .success(jwt)),
            apiClient: apiClient
        )

        // Act
        let snapshot = try await provider.fetchSnapshot()

        // Assert
        XCTAssertEqual(snapshot.providerID, .cursor)
        XCTAssertEqual(snapshot.metric(id: "cursor.plan.auto")?.usedPercent, 55)
        let receivedSubject = await apiClient.receivedSubject
        XCTAssertEqual(receivedSubject, "google-oauth2|user_test")
    }

    private func makeValidJWT(subject: String) -> String {
        makeJWT(claims: ["sub": subject, "exp": Date().addingTimeInterval(3600).timeIntervalSince1970])
    }

    private func makeExpiredJWT() -> String {
        makeJWT(claims: ["sub": "google-oauth2|user_test", "exp": Date().addingTimeInterval(-3600).timeIntervalSince1970])
    }

    private func makeJWT(claims: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"])
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        func base64URL(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(base64URL(header)).\(base64URL(payload)).signature"
    }
}

private struct StubCursorCredentialsReader: CursorCredentialsReading {
    let result: Result<String?, Error>

    func readAccessToken() throws -> String? {
        try result.get()
    }
}

private actor StubCursorAPIClient: CursorAPIServing {
    private let result: Result<CursorUsageSummaryResponse, Error>
    private(set) var receivedSubject: String?

    init(result: Result<CursorUsageSummaryResponse, Error>) {
        self.result = result
    }

    func fetchUsageSummary(sessionToken: String, subject: String) async throws -> CursorUsageSummaryResponse {
        receivedSubject = subject
        return try result.get()
    }
}

final class CodexJSONRPCResponseDecoderTests: XCTestCase {
    private struct AccountResult: Decodable, Equatable {
        let accountType: String
    }

    func testDecodeResultReturnsTypedPayloadForExpectedRequestID() throws {
        // Arrange
        let line = #"{"jsonrpc":"2.0","id":7,"result":{"accountType":"chatgpt"}}"#

        // Act
        let result = try CodexJSONRPCResponseDecoder.decode(
            line: line,
            expectedID: 7,
            as: AccountResult.self
        )

        // Assert
        XCTAssertEqual(result, AccountResult(accountType: "chatgpt"))
    }

    func testDecodeResultThrowsTypedRemoteError() {
        // Arrange
        let line = #"{"jsonrpc":"2.0","id":8,"error":{"code":-32601,"message":"Method not found"}}"#

        // Act / Assert
        XCTAssertThrowsError(
            try CodexJSONRPCResponseDecoder.decode(
                line: line,
                expectedID: 8,
                as: AccountResult.self
            )
        ) { error in
            guard case let CodexJSONRPCResponseError.remoteError(code, message) = error else {
                return XCTFail("Expected a typed remote error, got \(error)")
            }
            XCTAssertEqual(code, -32601)
            XCTAssertEqual(message, "Method not found")
        }
    }

    func testDecodeResultRejectsMismatchedRequestID() {
        // Arrange
        let line = #"{"jsonrpc":"2.0","id":99,"result":{"accountType":"chatgpt"}}"#

        // Act / Assert
        XCTAssertThrowsError(
            try CodexJSONRPCResponseDecoder.decode(
                line: line,
                expectedID: 7,
                as: AccountResult.self
            )
        ) { error in
            guard case let CodexJSONRPCResponseError.unexpectedResponseID(expected, actual) = error else {
                return XCTFail("Expected an ID mismatch, got \(error)")
            }
            XCTAssertEqual(expected, 7)
            XCTAssertEqual(actual, 99)
        }
    }

    func testDecodeResultRejectsMalformedJSONLWithoutCrashing() {
        XCTAssertThrowsError(
            try CodexJSONRPCResponseDecoder.decode(
                line: "{not-json}",
                expectedID: 1,
                as: AccountResult.self
            )
        ) { error in
            guard case CodexJSONRPCResponseError.malformedMessage = error else {
                return XCTFail("Expected malformedMessage, got \(error)")
            }
        }
    }
}

final class CodexAppServerClientIntegrationTests: XCTestCase {
    func testClientCompletesHandshakeAndReadsRateLimitsFromJSONLProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterAppServerTests-\(UUID().uuidString)", isDirectory: true)
        let executable = root.appendingPathComponent("fake-codex")
        let node = root.appendingPathComponent("node")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nodeScript = """
        #!/bin/sh
        script="$1"
        shift
        exec /bin/sh "$script" "$@"
        """
        let script = """
        #!/usr/bin/env node
        IFS= read -r initialize_request
        printf '%s\\n' '{"id":1,"result":{"userAgent":"fake-codex"}}'
        IFS= read -r initialized_notification
        IFS= read -r rate_limit_request
        printf '%s' '{"id":2,"result":{"rateLimits":'
        printf '%s' '{"primary":{"usedPercent":21,"windowDurationMins":300,'
        printf '%s\\n' '"resetsAt":1785322800}}}}'
        while IFS= read -r remaining_request; do :; done
        """
        try XCTUnwrap(nodeScript.data(using: .utf8)).write(to: node)
        try XCTUnwrap(script.data(using: .utf8)).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: node.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let client = CodexAppServerClient(binaryURL: executable, requestTimeout: 2)

        let response = try await client.readRateLimits()
        await client.stop()

        XCTAssertEqual(response.rateLimits?.primary?.usedPercent, 21)
    }
}

final class CodexLiveIntegrationTests: XCTestCase {
    func testLiveProviderFetchesCodexUsageSnapshot() async throws {
        let marker = URL(
            fileURLWithPath: "/private/tmp/agent-meter-live-codex-binary"
        )
        let environmentPath = ProcessInfo.processInfo.environment[
            "AGENT_METER_LIVE_CODEX_BINARY"
        ]
        let markerPath = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let binaryPath = environmentPath ?? markerPath,
              !binaryPath.isEmpty else {
            throw XCTSkip(
                "Set AGENT_METER_LIVE_CODEX_BINARY or the live-test marker"
            )
        }
        let binary = URL(fileURLWithPath: binaryPath)
        let provider = CodexProvider(
            resolver: CodexBinaryResolver(
                configuredPath: binary.path,
                environmentPath: binary.deletingLastPathComponent().path
            )
        )

        let snapshot = try await provider.fetchSnapshot()
        await provider.shutdown()

        let quota = try XCTUnwrap(
            snapshot.metrics.first { $0.category == .rateLimit }
        )
        XCTAssertEqual(snapshot.providerID, .codex)
        XCTAssertNotNil(quota.usedPercent)
        XCTAssertNotNil(quota.resetsAt)
        XCTAssertNil(snapshot.metric(id: "lifetime-tokens"))

        let evidence: [String: Any] = [
            "provider": snapshot.providerID.rawValue,
            "plan": snapshot.planLabel.map { $0 as Any } ?? NSNull(),
            "quotaMetric": quota.id,
            "quotaUsedPercent": quota.usedPercent.map { $0 as Any } ?? NSNull(),
            "quotaWindowSeconds": quota.windowDuration.map { $0 as Any } ?? NSNull(),
            "quotaResetsAt": quota.resetsAt
                .map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
            "metricCount": snapshot.metrics.count
        ]
        let data = try JSONSerialization.data(
            withJSONObject: evidence,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(
            to: URL(
                fileURLWithPath: "/private/tmp/agent-meter-live-provider-evidence.json"
            ),
            options: .atomic
        )
        print("AGENT_METER_LIVE_EVIDENCE")
        print(try XCTUnwrap(String(data: data, encoding: .utf8)))
    }
}

final class CodexProviderAuthenticationTests: XCTestCase {
    func testChatGPTAccountIsAuthenticatedWhenOpenAIAuthIsRequired() {
        let response = CodexAccountResponse(
            account: CodexAccount(
                type: "chatgpt",
                email: nil,
                planType: "plus"
            ),
            requiresOpenaiAuth: true
        )

        XCTAssertFalse(CodexProvider.requiresAuthentication(response))
    }

    func testMissingAccountRequiresAuthenticationForOpenAIProvider() {
        let response = CodexAccountResponse(
            account: nil,
            requiresOpenaiAuth: true
        )

        XCTAssertTrue(CodexProvider.requiresAuthentication(response))
    }
}

@MainActor
final class UsageCoordinatorTests: XCTestCase {
    func testRefreshAllKeepsSuccessfulProviderSnapshotWhenAnotherProviderFails() async {
        // Arrange
        let claudeSnapshot = UsageSnapshot(
            providerID: .claudeCode,
            fetchedAt: Date(timeIntervalSince1970: 100),
            metrics: [
                UsageMetric(
                    id: "claude.five-hour",
                    title: "5 hour",
                    shortLabel: "5h",
                    category: .rateLimit,
                    usedPercent: 10
                )
            ]
        )
        let coordinator = UsageCoordinator(providers: [
            StubUsageProvider(id: .claudeCode, result: .success(claudeSnapshot)),
            StubUsageProvider(id: .codex, result: .failure(StubProviderError.unavailable))
        ])

        // Act
        await coordinator.refreshAll()

        // Assert
        XCTAssertEqual(coordinator.state(for: .claudeCode).snapshot, claudeSnapshot)
        XCTAssertNil(coordinator.state(for: .claudeCode).error)
        XCTAssertNil(coordinator.state(for: .codex).snapshot)
        XCTAssertNotNil(coordinator.state(for: .codex).error)
        XCTAssertFalse(coordinator.state(for: .claudeCode).isLoading)
        XCTAssertFalse(coordinator.state(for: .codex).isLoading)
    }

    func testFailedRefreshPreservesThatProvidersLastSuccessfulSnapshot() async {
        // Arrange
        let originalSnapshot = UsageSnapshot(
            providerID: .codex,
            fetchedAt: Date(timeIntervalSince1970: 100),
            metrics: []
        )
        let codexProvider = SequencedUsageProvider(
            id: .codex,
            results: [
                .success(originalSnapshot),
                .failure(StubProviderError.unavailable)
            ]
        )
        let coordinator = UsageCoordinator(providers: [codexProvider])
        await coordinator.refreshAll()

        // Act
        await coordinator.refreshAll()

        // Assert
        XCTAssertEqual(coordinator.state(for: .codex).snapshot, originalSnapshot)
        XCTAssertNotNil(coordinator.state(for: .codex).error)
    }
}

final class AppSettingsMultiProviderMigrationTests: XCTestCase {
    func testDecodingLegacySettingsMigratesProviderDefaultsAndMetricVisibility() throws {
        // Arrange
        let legacyJSON = """
        {
          "displayMode": "Compact",
          "showSonnetLimit": true,
          "showDesignLimit": false,
          "showExtraUsage": true,
          "refreshInterval": 120,
          "notificationsEnabled": true
        }
        """.data(using: .utf8)!

        // Act
        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        // Assert
        XCTAssertEqual(settings.displayMode, .compact)
        XCTAssertEqual(settings.enabledProviderIDs, [.claudeCode])
        XCTAssertEqual(settings.selectedProviderID, .claudeCode)
        XCTAssertEqual(
            settings.metricVisibilityByProvider[.claudeCode]?["claude.seven-day-sonnet"],
            true
        )
        XCTAssertEqual(
            settings.metricVisibilityByProvider[.claudeCode]?["claude.seven-day-design"],
            false
        )
        XCTAssertEqual(
            settings.metricVisibilityByProvider[.claudeCode]?["claude.extra-usage"],
            true
        )
        XCTAssertEqual(
            settings.pinnedMetricIDsByProvider[.claudeCode],
            ["claude.five-hour", "claude.seven-day"]
        )
    }

    func testMultiProviderSettingsRoundTripPreservesProviderSpecificChoices() throws {
        // Arrange
        var settings = AppSettings()
        settings.enabledProviderIDs = [.claudeCode, .codex]
        settings.selectedProviderID = .codex
        settings.metricVisibilityByProvider = [
            .claudeCode: ["claude.seven-day": true],
            .codex: ["codex.codex.secondary": false]
        ]
        settings.pinnedMetricIDsByProvider = [
            .claudeCode: ["claude.five-hour"],
            .codex: ["codex.codex.primary", "codex.codex.secondary"]
        ]

        // Act
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        // Assert
        XCTAssertEqual(decoded.enabledProviderIDs, [.claudeCode, .codex])
        XCTAssertEqual(decoded.selectedProviderID, .codex)
        XCTAssertEqual(decoded.metricVisibilityByProvider, settings.metricVisibilityByProvider)
        XCTAssertEqual(decoded.pinnedMetricIDsByProvider, settings.pinnedMetricIDsByProvider)
    }

    func testEncodingSettingsNeverPersistsLegacyWebSessionSecret() throws {
        var settings = AppSettings()
        settings.webSessionKey = "must-not-be-persisted"

        let encoded = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(object["webSessionKey"])
    }

    func testUpdatingMetricPinReturnsNewSettingsAndKeepsAtMostTwoPins() {
        let original = AppSettings()

        let firstUpdate = original.updatingMetricPin(
            providerID: .codex,
            metricID: "codex.first",
            isPinned: true
        )
        let secondUpdate = firstUpdate.updatingMetricPin(
            providerID: .codex,
            metricID: "codex.second",
            isPinned: true
        )
        let thirdUpdate = secondUpdate.updatingMetricPin(
            providerID: .codex,
            metricID: "codex.third",
            isPinned: true
        )

        XCTAssertEqual(
            original.pinnedMetricIDsByProvider[.codex],
            ["codex.codex.primary", "codex.codex.secondary"]
        )
        XCTAssertEqual(
            original.pinnedMetricIDsByProvider[.cursor],
            ["cursor.plan.auto", "cursor.plan.api"]
        )
        XCTAssertEqual(
            thirdUpdate.pinnedMetricIDsByProvider[.codex],
            ["codex.second", "codex.third"]
        )
    }

    func testUpdatingMetricPinCanUnpinWithoutChangingOtherProviders() {
        var settings = AppSettings()
        settings.pinnedMetricIDsByProvider = [
            .claudeCode: ["claude.five-hour"],
            .codex: ["codex.first", "codex.second"]
        ]

        let updated = settings.updatingMetricPin(
            providerID: .codex,
            metricID: "codex.first",
            isPinned: false
        )

        XCTAssertEqual(updated.pinnedMetricIDsByProvider[.codex], ["codex.second"])
        XCTAssertEqual(
            updated.pinnedMetricIDsByProvider[.claudeCode],
            ["claude.five-hour"]
        )
    }
}

final class CodexBinaryResolverTests: XCTestCase {
    func testSupportedVersionRequiresAtLeastCurrentAppServerContract() {
        XCTAssertFalse(CodexBinaryResolver.isSupported("0.145.9"))
        XCTAssertTrue(CodexBinaryResolver.isSupported("0.146.0"))
        XCTAssertTrue(CodexBinaryResolver.isSupported("1.0.0-beta.1"))
        XCTAssertFalse(CodexBinaryResolver.isSupported("not-a-version"))
    }

    func testConfiguredExecutableTakesPrecedenceOverPathCandidates() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterTests-\(UUID().uuidString)", isDirectory: true)
        let configured = root.appendingPathComponent("configured-codex")
        let pathDirectory = root.appendingPathComponent("path", isDirectory: true)
        let pathCandidate = pathDirectory.appendingPathComponent("codex")
        try FileManager.default.createDirectory(
            at: pathDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: configured)
        try Data().write(to: pathCandidate)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: configured.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pathCandidate.path
        )

        let resolver = CodexBinaryResolver(
            configuredPath: configured.path,
            homeDirectory: root,
            environmentPath: pathDirectory.path
        )

        XCTAssertEqual(resolver.resolve()?.standardizedFileURL, configured.standardizedFileURL)
    }

    func testNVMLauncherPreservesItsDirectoryForEnvNodeShebang() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterNVMTests-\(UUID().uuidString)", isDirectory: true)
        let binDirectory = root.appendingPathComponent(
            ".nvm/versions/node/v24.0.2/bin",
            isDirectory: true
        )
        let packageDirectory = root.appendingPathComponent(
            ".nvm/versions/node/v24.0.2/lib/node_modules/@openai/codex/bin",
            isDirectory: true
        )
        let launcher = binDirectory.appendingPathComponent("codex")
        let node = binDirectory.appendingPathComponent("node")
        let script = packageDirectory.appendingPathComponent("codex.js")
        try FileManager.default.createDirectory(
            at: binDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: packageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        try Data(
            """
            #!/bin/sh
            script="$1"
            shift
            exec /bin/sh "$script" "$@"
            """.utf8
        ).write(to: node)
        try Data(
            """
            #!/usr/bin/env node
            printf 'codex-cli 0.146.0\n'
            """.utf8
        ).write(to: script)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: node.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        try FileManager.default.createSymbolicLink(
            at: launcher,
            withDestinationURL: script
        )

        let resolver = CodexBinaryResolver(
            homeDirectory: root,
            environmentPath: "/usr/bin:/bin"
        )

        let resolved = try XCTUnwrap(resolver.resolve())
        XCTAssertEqual(resolved.standardizedFileURL, launcher.standardizedFileURL)
        XCTAssertEqual(try resolver.validateVersion(at: resolved).get(), "0.146.0")
    }

    func testCodexProcessEnvironmentKeepsOnlyTrustedRuntimeVariables() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterEnvironmentTests-\(UUID().uuidString)")
        let launcherDirectory = root.appendingPathComponent("launcher", isDirectory: true)
        let interpreterDirectory = root.appendingPathComponent("interpreter", isDirectory: true)
        try FileManager.default.createDirectory(
            at: launcherDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: interpreterDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let node = interpreterDirectory.appendingPathComponent("node")
        try Data("#!/bin/sh\n".utf8).write(to: node)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: node.path
        )

        let binary = launcherDirectory.appendingPathComponent("codex")
        let environment = CodexProcessEnvironment.environment(
            for: binary,
            base: [
                "PATH": "/attacker/bin:\(interpreterDirectory.path):/usr/bin",
                "NODE_OPTIONS": "--require=/tmp/inject.js",
                "NODE_PATH": "/tmp/modules",
                "OPENAI_API_KEY": "secret",
                "CODEX_HOME": "/trusted/codex-home",
                "HTTPS_PROXY": "http://proxy.example",
                "LANG": "en_US.UTF-8",
                "SSL_CERT_FILE": "/trusted/company-ca.pem"
            ]
        )

        XCTAssertEqual(
            environment["PATH"],
            "\(interpreterDirectory.path):/usr/bin:/bin:/usr/sbin:/sbin"
        )
        XCTAssertEqual(environment["CODEX_HOME"], "/trusted/codex-home")
        XCTAssertEqual(environment["HTTPS_PROXY"], "http://proxy.example")
        XCTAssertEqual(environment["LANG"], "en_US.UTF-8")
        XCTAssertEqual(environment["SSL_CERT_FILE"], "/trusted/company-ca.pem")
        XCTAssertNil(environment["NODE_OPTIONS"])
        XCTAssertNil(environment["NODE_PATH"])
        XCTAssertNil(environment["OPENAI_API_KEY"])
    }

    func testCodexProcessEnvironmentRejectsNodeSymlinkIntoWritableTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterUnsafeNodeTests-\(UUID().uuidString)")
        let launcherDirectory = root.appendingPathComponent("launcher", isDirectory: true)
        let writableDirectory = root.appendingPathComponent("writable", isDirectory: true)
        try [launcherDirectory, writableDirectory].forEach {
            try FileManager.default.createDirectory(
                at: $0,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let unsafeNode = writableDirectory.appendingPathComponent("node")
        try Data("#!/bin/sh\n".utf8).write(to: unsafeNode)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: unsafeNode.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o777],
            ofItemAtPath: writableDirectory.path
        )
        try FileManager.default.createSymbolicLink(
            at: launcherDirectory.appendingPathComponent("node"),
            withDestinationURL: unsafeNode
        )

        let environment = CodexProcessEnvironment.environment(
            for: launcherDirectory.appendingPathComponent("codex"),
            base: [:]
        )

        XCTAssertFalse(environment["PATH", default: ""].contains(launcherDirectory.path))
    }

    func testResolverRejectsGroupWritableExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterTrustTests-\(UUID().uuidString)", isDirectory: true)
        let executable = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o775],
            ofItemAtPath: executable.path
        )
        let resolver = CodexBinaryResolver(
            configuredPath: executable.path,
            homeDirectory: root,
            environmentPath: ""
        )

        XCTAssertNotEqual(
            resolver.resolve()?.standardizedFileURL,
            executable.standardizedFileURL
        )
    }
}

final class SnapshotCacheManagerTests: XCTestCase {
    func testSnapshotsAreStoredAndClearedPerProvider() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentMeterCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = SnapshotCacheManager(directory: root)
        let fetchedAt = Date(timeIntervalSince1970: 1_785_300_000)
        let claude = UsageSnapshot(
            providerID: .claudeCode,
            fetchedAt: fetchedAt,
            metrics: []
        )
        let codex = UsageSnapshot(
            providerID: .codex,
            fetchedAt: fetchedAt,
            metrics: []
        )
        try cache.save(claude)
        try cache.save(codex)

        try cache.clear(providerID: .claudeCode)

        XCTAssertNil(cache.load(providerID: .claudeCode, maxAge: nil))
        XCTAssertEqual(cache.load(providerID: .codex, maxAge: nil), codex)
    }
}

private enum StubProviderError: Error {
    case unavailable
}

private actor StubUsageProvider: UsageProvider {
    nonisolated let id: ProviderID
    private let result: Result<UsageSnapshot, Error>

    init(id: ProviderID, result: Result<UsageSnapshot, Error>) {
        self.id = id
        self.result = result
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        try result.get()
    }
}

private actor SequencedUsageProvider: UsageProvider {
    nonisolated let id: ProviderID
    private var results: [Result<UsageSnapshot, Error>]

    init(id: ProviderID, results: [Result<UsageSnapshot, Error>]) {
        self.id = id
        self.results = results
    }

    func fetchSnapshot() async throws -> UsageSnapshot {
        guard !results.isEmpty else {
            throw StubProviderError.unavailable
        }
        return try results.removeFirst().get()
    }
}
