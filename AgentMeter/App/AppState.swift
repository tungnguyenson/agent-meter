import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var providerStates: [ProviderID: ProviderUsageState]
    @Published var lastUpdateTime: Date?
    @Published var isPopoverShown = false
    @Published var settings: AppSettings {
        didSet {
            settings.save()
            applySettings()
            if oldValue.codexBinaryPath != settings.codexBinaryPath
                || oldValue.webOrganizationId != settings.webOrganizationId {
                if oldValue.codexBinaryPath != settings.codexBinaryPath {
                    providerAuthBlocked.remove(.codex)
                    providerCooldownUntil.removeValue(forKey: .codex)
                }
                if oldValue.webOrganizationId != settings.webOrganizationId {
                    providerAuthBlocked.remove(.claudeCode)
                    providerCooldownUntil.removeValue(forKey: .claudeCode)
                }
                persistProviderCooldowns()
                rebuildUsageCoordinator()
            }
        }
    }

    let pollingManager: PollingManager
    private(set) var usageCoordinator: UsageCoordinator

    private var previousSnapshots: [ProviderID: UsageSnapshot] = [:]
    private var providerCooldownUntil: [ProviderID: Date]
    private var providerAuthBlocked = Set<ProviderID>()
    private var providersFetching = Set<ProviderID>()
    private var wakeRetryTask: Task<Void, Never>?
    private var coordinatorCancellable: AnyCancellable?
    private var codexUpdateCancellable: AnyCancellable?

    var selectedProviderID: ProviderID {
        settings.selectedProviderID
    }

    var selectedProviderState: ProviderUsageState {
        providerStates[selectedProviderID] ?? .idle
    }

    var selectedSnapshot: UsageSnapshot? {
        selectedProviderState.snapshot
    }

    var isLoading: Bool {
        selectedProviderState.isLoading
    }

    var error: Error? {
        selectedProviderState.error
    }

    var enabledProviderIDs: [ProviderID] {
        settings.enabledProviderIDs
    }

    init() {
        var loadedSettings = AppSettings.load()
        Self.migrateLegacySecret(settings: &loadedSettings)
        Self.migrateLegacyCache()

        settings = loadedSettings
        providerCooldownUntil = Self.loadProviderCooldowns()
        pollingManager = PollingManager()
        let providers = Self.makeProviders(settings: loadedSettings)
        usageCoordinator = UsageCoordinator(
            providers: providers,
            cache: SnapshotCacheManager.shared
        )
        providerStates = usageCoordinator.states
        lastUpdateTime = providerStates[loadedSettings.selectedProviderID]?
            .snapshot?
            .fetchedAt

        setupBindings()
        setupCodexUpdateHandling()
        applySettings()
        setupNetworkRecovery()
        startDeferredPolling()
        requestNotificationPermission()
    }

    func selectProvider(_ providerID: ProviderID) {
        guard settings.enabledProviderIDs.contains(providerID) else { return }
        settings.selectedProviderID = providerID
        lastUpdateTime = providerStates[providerID]?.snapshot?.fetchedAt
    }

    func setProviderEnabled(_ providerID: ProviderID, isEnabled: Bool) {
        let current = settings.enabledProviderIDs
        let updated = isEnabled
            ? Array(Set(current + [providerID])).sorted { $0.rawValue < $1.rawValue }
            : current.filter { $0 != providerID }
        guard !updated.isEmpty else { return }
        settings.enabledProviderIDs = updated
        if !updated.contains(settings.selectedProviderID), let first = updated.first {
            settings.selectedProviderID = first
        }
    }

    func setMetricVisibility(
        providerID: ProviderID,
        metricID: String,
        isVisible: Bool
    ) {
        var providerVisibility = settings.metricVisibilityByProvider[providerID] ?? [:]
        providerVisibility[metricID] = isVisible
        var allVisibility = settings.metricVisibilityByProvider
        allVisibility[providerID] = providerVisibility
        settings.metricVisibilityByProvider = allVisibility
    }

    func metricIsVisible(providerID: ProviderID, metricID: String) -> Bool {
        settings.metricVisibilityByProvider[providerID]?[metricID] ?? true
    }

    func setMetricPinned(
        providerID: ProviderID,
        metricID: String,
        isPinned: Bool
    ) {
        settings = settings.updatingMetricPin(
            providerID: providerID,
            metricID: metricID,
            isPinned: isPinned
        )
    }

    func metricIsPinned(providerID: ProviderID, metricID: String) -> Bool {
        settings.pinnedMetricIDsByProvider[providerID]?.contains(metricID) ?? false
    }

    func claudeWebSessionKey() -> String {
        (try? ProviderSecretStore.shared.read(
            account: ProviderSecretAccount.claudeWebSessionKey
        )) ?? ""
    }

    func updateClaudeWebSessionKey(_ value: String) throws {
        if value.isEmpty {
            try ProviderSecretStore.shared.delete(
                account: ProviderSecretAccount.claudeWebSessionKey
            )
        } else {
            try ProviderSecretStore.shared.save(
                value,
                account: ProviderSecretAccount.claudeWebSessionKey
            )
        }
    }

    func refresh(reason: String = "unknown") async {
        await performRefresh(reason: reason)
    }

    func refreshSelected(reason: String = "manual_refresh") async {
        await refreshProvider(selectedProviderID, reason: reason)
    }

    func onAppBecameActive() {
        if isDataFresh() {
            pollingManager.resumeFromBackground()
        } else {
            pollingManager.onAppBecameActive()
        }
    }

    func onAppResignedActive() {
        pollingManager.onAppResignedActive()
    }

    func onSystemWillSleep() {
        wakeRetryTask?.cancel()
        wakeRetryTask = nil
        pollingManager.onSystemWillSleep()
    }

    func onSystemDidWake() {
        wakeRetryTask?.cancel()
        _ = pollingManager.onSystemDidWake()
        wakeRetryTask = Task { @MainActor [weak self] in
            let delay = UInt64(Constants.WakeRecovery.initialDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            await self.refresh(reason: "wake_recovery")
            self.pollingManager.schedulePostWakeTimer()
        }
    }

    private func setupBindings() {
        coordinatorCancellable?.cancel()
        coordinatorCancellable = usageCoordinator.$states
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                guard let self else { return }
                self.consume(states: states)
            }
    }

    private func setupCodexUpdateHandling() {
        codexUpdateCancellable = NotificationCenter.default.publisher(
            for: .codexUsageDidChange
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      self.settings.enabledProviderIDs.contains(.codex),
                      self.providerStates[.codex]?.isLoading != true else {
                    return
                }
                await self.refreshProvider(.codex, reason: "codex_push")
            }
        }
    }

    private func consume(states: [ProviderID: ProviderUsageState]) {
        let oldStates = providerStates
        providerStates = states
        lastUpdateTime = states[selectedProviderID]?.snapshot?.fetchedAt

        for providerID in settings.enabledProviderIDs {
            guard let snapshot = states[providerID]?.snapshot,
                  snapshot != oldStates[providerID]?.snapshot else {
                continue
            }
            if settings.notificationsEnabled {
                NotificationService.shared.checkAndNotify(
                    snapshot: snapshot,
                    previousSnapshot: previousSnapshots[providerID],
                    thresholds: settings.notifyAt
                )
            }
            previousSnapshots[providerID] = snapshot
        }
        updatePollingInterval()
    }

    private func performRefresh(reason: String) async {
        if Self.isUserInitiated(reason: reason) {
            pollingManager.clearAuthFailure()
            providerAuthBlocked.removeAll()
            providerCooldownUntil.removeAll()
        }
        let providerIDs = eligibleProviderIDs(reason: reason)
            .filter { !providersFetching.contains($0) }
        guard !providerIDs.isEmpty else { return }
        providersFetching.formUnion(providerIDs)
        defer { providersFetching.subtract(providerIDs) }
        await usageCoordinator.refresh(providerIDs)
        recordRefreshOutcome(providerIDs: providerIDs)
    }

    private func recordRefreshOutcome(providerIDs: [ProviderID]) {
        let states = usageCoordinator.states
        for providerID in providerIDs {
            switch states[providerID]?.configurationStatus {
            case .authenticationRequired:
                providerAuthBlocked.insert(providerID)
            case .ready, .unavailable, .none:
                break
            }
            guard let error = states[providerID]?.error as? AppError else {
                if states[providerID]?.error == nil {
                    providerAuthBlocked.remove(providerID)
                    providerCooldownUntil.removeValue(forKey: providerID)
                }
                continue
            }
            switch error {
            case .rateLimited(let retryAfter):
                let duration = retryAfter ?? Constants.RateLimit.defaultCooldownDuration
                providerCooldownUntil[providerID] = Date().addingTimeInterval(duration)
            case .noCredentials, .invalidCredentials, .credentialsExpired,
                 .authenticationFailed:
                providerAuthBlocked.insert(providerID)
            default:
                break
            }
        }
        persistProviderCooldowns()

        if providerIDs.contains(where: {
            states[$0]?.snapshot != nil && states[$0]?.error == nil
        }) {
            pollingManager.recordSuccess()
        } else {
            pollingManager.recordFailure()
        }
    }

    private func eligibleProviderIDs(reason: String) -> [ProviderID] {
        if Self.isUserInitiated(reason: reason) {
            return settings.enabledProviderIDs
        }
        let now = Date()
        return settings.enabledProviderIDs.filter { providerID in
            guard !providerAuthBlocked.contains(providerID) else { return false }
            guard let cooldown = providerCooldownUntil[providerID] else { return true }
            return cooldown <= now
        }
    }

    private func refreshProvider(_ providerID: ProviderID, reason: String) async {
        guard settings.enabledProviderIDs.contains(providerID),
              !providersFetching.contains(providerID) else {
            return
        }
        if Self.isUserInitiated(reason: reason) {
            providerAuthBlocked.remove(providerID)
            providerCooldownUntil.removeValue(forKey: providerID)
            persistProviderCooldowns()
        } else {
            guard !providerAuthBlocked.contains(providerID) else { return }
            if let cooldown = providerCooldownUntil[providerID], cooldown > Date() {
                return
            }
        }
        providersFetching.insert(providerID)
        defer { providersFetching.remove(providerID) }
        await usageCoordinator.refresh(providerID)
        recordRefreshOutcome(providerIDs: [providerID])
    }

    private func applySettings() {
        pollingManager.setDefaultInterval(TimeInterval(settings.refreshInterval))
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    private func rebuildUsageCoordinator() {
        let previousCoordinator = usageCoordinator
        let replacement = UsageCoordinator(
            providers: Self.makeProviders(settings: settings),
            cache: SnapshotCacheManager.shared
        )
        usageCoordinator = replacement
        providerStates = replacement.states
        setupBindings()
        Task {
            await previousCoordinator.shutdown()
        }
    }

    private func setupNetworkRecovery() {
        pollingManager.startNetworkMonitor { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.pollingManager.isRunning,
                      self.selectedSnapshot == nil else {
                    return
                }
                await self.refresh(reason: "network_recovery")
            }
        }
    }

    private func startDeferredPolling() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            self.pollingManager.start(immediateRefresh: false) { [weak self] in
                await self?.performRefresh(reason: "timer")
            }
        }
    }

    private func requestNotificationPermission() {
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            _ = await NotificationService.shared.requestPermission()
        }
    }

    private func updatePollingInterval() {
        let maxUsage = providerStates.values
            .compactMap(\.snapshot)
            .flatMap(\.percentageMetrics)
            .compactMap(\.usedPercent)
            .max() ?? 0
        pollingManager.updateForUsage(maxUsage)
    }

    private func isDataFresh() -> Bool {
        guard let fetchedAt = selectedSnapshot?.fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) < TimeInterval(settings.refreshInterval)
    }

    private static func isUserInitiated(reason: String) -> Bool {
        ["manual_refresh", "retry_button", "empty_state_refresh"].contains(reason)
    }

    private static let providerCooldownsKey = "com.agentmeter.provider-cooldowns"

    private static func loadProviderCooldowns() -> [ProviderID: Date] {
        guard let values = UserDefaults.standard.dictionary(
            forKey: providerCooldownsKey
        ) as? [String: Double] else {
            return [:]
        }
        let now = Date()
        return Dictionary(uniqueKeysWithValues: values.compactMap { key, timestamp in
            guard let providerID = ProviderID(rawValue: key) else { return nil }
            let deadline = Date(timeIntervalSince1970: timestamp)
            return deadline > now ? (providerID, deadline) : nil
        })
    }

    private func persistProviderCooldowns() {
        let values = Dictionary(uniqueKeysWithValues: providerCooldownUntil.map {
            ($0.key.rawValue, $0.value.timeIntervalSince1970)
        })
        UserDefaults.standard.set(values, forKey: Self.providerCooldownsKey)
    }

    private static func makeProviders(settings: AppSettings) -> [any UsageProvider] {
        [
            ClaudeCodeProvider(webOrganizationID: settings.webOrganizationId),
            CodexProvider(
                resolver: CodexBinaryResolver(
                    configuredPath: settings.codexBinaryPath.isEmpty
                        ? nil
                        : settings.codexBinaryPath
                )
            )
        ]
    }

    private static func migrateLegacySecret(settings: inout AppSettings) {
        guard !settings.webSessionKey.isEmpty else { return }
        do {
            try ProviderSecretStore.shared.save(
                settings.webSessionKey,
                account: ProviderSecretAccount.claudeWebSessionKey
            )
        } catch {
            return
        }
        settings.webSessionKey = ""
        settings.save()
        AppSettings.removeLegacySettingsData()
    }

    private static func migrateLegacyCache() {
        guard SnapshotCacheManager.shared.load(
            providerID: .claudeCode,
            maxAge: nil
        ) == nil,
        let legacy = legacyCachedUsageData() else {
            return
        }
        try? SnapshotCacheManager.shared.save(ClaudeUsageMapper.map(legacy))
    }

    private static func legacyCachedUsageData() -> UsageData? {
        if let currentBundleCache = CacheManager.shared.getCachedUsageData(maxAge: nil) {
            return currentBundleCache
        }

        let cacheRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first
        // Legacy cache path from previous version — maintain migration compatibility
        let legacyURL = cacheRoot?
            .appendingPathComponent("ClaudeMeter", isDirectory: true)
            .appendingPathComponent(Constants.Cache.usageDataFilename)
        guard let legacyURL,
              let data = try? Data(contentsOf: legacyURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LegacyUsageCacheEntry.self, from: data).data
    }
}

private struct LegacyUsageCacheEntry: Decodable {
    let data: UsageData
}
