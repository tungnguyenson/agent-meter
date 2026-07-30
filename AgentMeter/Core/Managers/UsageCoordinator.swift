import Foundation
import Combine

struct ProviderUsageState {
    let snapshot: UsageSnapshot?
    let isLoading: Bool
    let error: Error?
    let configurationStatus: ProviderConfigurationStatus

    static let idle = ProviderUsageState(
        snapshot: nil,
        isLoading: false,
        error: nil,
        configurationStatus: .ready
    )

    func loading() -> ProviderUsageState {
        ProviderUsageState(
            snapshot: snapshot,
            isLoading: true,
            error: nil,
            configurationStatus: configurationStatus
        )
    }

    func succeeded(with snapshot: UsageSnapshot) -> ProviderUsageState {
        ProviderUsageState(
            snapshot: snapshot,
            isLoading: false,
            error: nil,
            configurationStatus: .ready
        )
    }

    func failed(
        with error: Error,
        configurationStatus: ProviderConfigurationStatus? = nil
    ) -> ProviderUsageState {
        ProviderUsageState(
            snapshot: snapshot,
            isLoading: false,
            error: error,
            configurationStatus: configurationStatus ?? self.configurationStatus
        )
    }
}

@MainActor
final class UsageCoordinator: ObservableObject {
    @Published private(set) var states: [ProviderID: ProviderUsageState]

    private let providers: [any UsageProvider]
    private let cache: SnapshotCacheStoring?

    init(
        providers: [any UsageProvider],
        cache: SnapshotCacheStoring? = nil
    ) {
        self.providers = providers
        self.cache = cache
        states = Dictionary(uniqueKeysWithValues: providers.map { provider in
            let snapshot = cache?.load(providerID: provider.id, maxAge: nil)
            return (
                provider.id,
                ProviderUsageState(
                    snapshot: snapshot,
                    isLoading: false,
                    error: nil,
                    configurationStatus: .ready
                )
            )
        })
    }

    func state(for providerID: ProviderID) -> ProviderUsageState {
        states[providerID] ?? .idle
    }

    func refreshAll() async {
        await refresh(providers.map(\.id))
    }

    func refresh(_ providerIDs: [ProviderID]) async {
        let selectedProviders = providers.filter { providerIDs.contains($0.id) }
        for provider in selectedProviders {
            states[provider.id] = state(for: provider.id).loading()
        }
        await withTaskGroup(of: ProviderRefreshResult.self) { group in
            for provider in selectedProviders {
                group.addTask {
                    let status = await provider.configurationStatus()
                    guard status == .ready else {
                        return ProviderRefreshResult(
                            providerID: provider.id,
                            configurationStatus: status,
                            result: .failure(ProviderConfigurationError(status: status))
                        )
                    }
                    do {
                        await DebugLogger.shared.log(.request, "API: \(provider.debugEndpoint)", providerID: provider.id)
                        let snapshot = try await provider.fetchSnapshot()
                        await DebugLogger.shared.log(
                            .response,
                            "API: \(provider.debugEndpoint) SUCCESS",
                            providerID: provider.id
                        )
                        return ProviderRefreshResult(
                            providerID: provider.id,
                            configurationStatus: .ready,
                            result: .success(snapshot)
                        )
                    } catch {
                        await DebugLogger.shared.log(
                            .error,
                            "API: \(provider.debugEndpoint) FAILED",
                            providerID: provider.id,
                            detail: error.localizedDescription
                        )
                        let errorStatus = Self.configurationStatus(for: error)
                        return ProviderRefreshResult(
                            providerID: provider.id,
                            configurationStatus: errorStatus,
                            result: .failure(error)
                        )
                    }
                }
            }

            for await refresh in group {
                apply(refresh)
            }
        }

        for providerID in providerIDs where states[providerID]?.isLoading == true {
            states[providerID] = states[providerID]?.failed(
                with: CancellationError()
            )
        }
    }

    func refresh(_ providerID: ProviderID) async {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return
        }
        states[providerID] = state(for: providerID).loading()
        let status = await provider.configurationStatus()
        guard status == .ready else {
            states[providerID] = state(for: providerID).failed(
                with: ProviderConfigurationError(status: status),
                configurationStatus: status
            )
            return
        }
        do {
            let snapshot = try await provider.fetchSnapshot()
            try? cache?.save(snapshot)
            states[providerID] = state(for: providerID).succeeded(with: snapshot)
        } catch {
            states[providerID] = state(for: providerID).failed(
                with: error,
                configurationStatus: Self.configurationStatus(for: error)
            )
        }
    }

    nonisolated private static func configurationStatus(
        for error: Error
    ) -> ProviderConfigurationStatus {
        if let codexError = error as? CodexAppServerError,
           case .authenticationRequired = codexError {
            return .authenticationRequired(codexError.localizedDescription)
        }
        if let cursorError = error as? CursorProviderError {
            return .authenticationRequired(cursorError.localizedDescription)
        }
        if case .unauthorized = error as? CursorAPIError {
            return .authenticationRequired(CursorAPIError.unauthorized.localizedDescription)
        }
        return .ready
    }

    private func apply(_ refresh: ProviderRefreshResult) {
        switch refresh.result {
        case .success(let snapshot):
            try? cache?.save(snapshot)
            states[refresh.providerID] = state(for: refresh.providerID)
                .succeeded(with: snapshot)
        case .failure(let error):
            states[refresh.providerID] = state(for: refresh.providerID)
                .failed(
                    with: error,
                    configurationStatus: refresh.configurationStatus
                )
        }
    }

    func shutdown() async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    await provider.shutdown()
                }
            }
        }
    }
}

private struct ProviderRefreshResult: @unchecked Sendable {
    let providerID: ProviderID
    let configurationStatus: ProviderConfigurationStatus
    let result: Result<UsageSnapshot, Error>
}

private struct ProviderConfigurationError: LocalizedError {
    let status: ProviderConfigurationStatus

    var errorDescription: String? {
        switch status {
        case .ready:
            return nil
        case .unavailable(let message), .authenticationRequired(let message):
            return message
        }
    }
}
