//
//  AppState.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Combine
import AppKit

@MainActor
class AppState: ObservableObject {
    // Usage Data
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var lastUpdateTime: Date?
    @Published var error: Error?



    // Previous usage for notification comparison
    private var previousUsageData: UsageData?

    // Wake recovery
    private var wakeRetryTask: Task<Void, Never>?

    // UI State
    @Published var isPopoverShown: Bool = false

    // Settings - Single source of truth with UserDefaults
    @Published var settings: AppSettings {
        didSet {
            saveSettings()
            applySettings()
        }
    }

    // Managers
    private let usageManager: UsageManager
    let pollingManager: PollingManager

    private var cancellables = Set<AnyCancellable>()

    init() {
        // PHASE 1: Sync, fast initialization
        self.usageManager = UsageManager()
        self.pollingManager = PollingManager()

        // Load settings from UserDefaults
        self.settings = AppSettings.load()

        setupBindings()
        applySettings()

        // Restore lastUpdateTime from the on-disk cache timestamp so we know
        // how old the data is without making an API call.
        if let cacheAge = CacheManager.shared.cacheAge {
            lastUpdateTime = Date().addingTimeInterval(-cacheAge)
        }

        // Restore persisted rate-limit state so the UI shows the banner and
        // the scheduler refuses to fetch until the cooldown expires. Writing
        // to usageManager.error lets the existing $error binding propagate.
        if let cooldownUntil = pollingManager.activeRateLimitCooldown {
            let remaining = cooldownUntil.timeIntervalSinceNow
            usageManager.error = AppError.rateLimited(retryAfter: remaining)
        }

        // Setup network monitor for wake recovery
        pollingManager.startNetworkMonitor { [weak self] in
            Task { @MainActor in
                self?.onNetworkBecameAvailable()
            }
        }

        // PHASE 2: Deferred polling (300ms delay to let UI render first).
        // Skip the immediate fetch when cached data is still within the refresh interval.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self = self else { return }
            // Never fetch on app start — respect the schedule. The user can
            // press "Refresh usage data" if they want fresh data immediately.
            // This avoids hammering the API during rate-limit or error states.
            self.pollingManager.start(immediateRefresh: false) { [weak self] in
                await self?.performRefresh(reason: "timer")
            }
        }

        // Request notification permission on first launch (deferred)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            _ = await NotificationService.shared.requestPermission()
        }
    }

    private func setupBindings() {
        usageManager.$usageData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newData in
                self?.previousUsageData = self?.usageData
                self?.usageData = newData

                // Check notifications
                if let data = newData {
                    self?.checkNotifications(data)
                    self?.updatePollingInterval(data)
                }
            }
            .store(in: &cancellables)

        usageManager.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        usageManager.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    // MARK: - Settings Management

    private func loadSettings() {
        settings = AppSettings.load()
    }

    private func saveSettings() {
        settings.save()
    }

    private func applySettings() {
        // Apply refresh interval to polling manager
        pollingManager.setDefaultInterval(TimeInterval(settings.refreshInterval))

        // Apply web API fallback credentials
        usageManager.webSessionKey = settings.webSessionKey
        usageManager.webOrganizationId = settings.webOrganizationId
        usageManager.onSessionKeyRefreshed = { [weak self] newKey in
            self?.settings.webSessionKey = newKey
        }

        // Apply dock visibility
        if settings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Data Refresh

    func refresh(reason: String = "unknown") async {
        await performRefresh(reason: reason)
    }

    /// Unified refresh path. Enforces the rate-limit + auth-failure gates for
    /// every caller so a restored 429 cooldown or permanent auth failure
    /// cannot be bypassed. User-initiated reasons clear the auth gate first.
    private func performRefresh(reason: String = "timer") async {
        if Self.isUserInitiated(reason: reason) {
            pollingManager.clearAuthFailure()
        }
        guard pollingManager.canMakeRequest(reason: reason) else { return }
        guard pollingManager.beginFetch() else { return }
        defer { pollingManager.endFetch() }
        await usageManager.fetchUsage()

        if usageManager.error == nil {
            lastUpdateTime = Date()
            pollingManager.recordSuccess()
            return
        }

        guard let appError = usageManager.error as? AppError else {
            pollingManager.recordFailure()
            return
        }

        switch appError {
        case .rateLimited(let retryAfter):
            // Rule 1: respect retry-after window, no attempts during cooldown.
            pollingManager.recordRateLimitHit(retryAfter: retryAfter)
        case .noCredentials, .invalidCredentials, .credentialsExpired, .authenticationFailed:
            // Rule 2: auth errors never recover automatically.
            pollingManager.recordAuthFailure()
        default:
            // Rule 3: no retry — the next scheduled tick will try again.
            pollingManager.recordFailure()
        }
    }

    private static func isUserInitiated(reason: String) -> Bool {
        switch reason {
        case "manual_refresh", "retry_button", "empty_state_refresh":
            return true
        default:
            return false
        }
    }

    // MARK: - Notifications

    private func checkNotifications(_ data: UsageData) {
        guard settings.notificationsEnabled else { return }

        NotificationService.shared.checkAndNotify(
            usage: data,
            previousUsage: previousUsageData,
            thresholds: settings.notifyAt
        )
    }

    // MARK: - Adaptive Polling

    private func updatePollingInterval(_ data: UsageData) {
        // Calculate max usage across all windows
        let maxUsage = [
            data.fiveHour?.utilization ?? 0,
            data.sevenDay?.utilization ?? 0,
            data.sevenDayOpus?.utilization ?? 0,
            data.sevenDaySonnet?.utilization ?? 0
        ].max() ?? 0

        pollingManager.updateForUsage(maxUsage)
    }

    // MARK: - App Lifecycle

    func onAppBecameActive() {
        // Only fire an immediate API call if the data is actually stale.
        // If the cached data is still within the refresh interval, just resume
        // the polling timer without an extra round-trip.
        if isDataFresh() {
            pollingManager.resumeFromBackground()
        } else {
            pollingManager.onAppBecameActive()
        }
    }

    /// Returns true when the last successful fetch is more recent than the configured refresh interval.
    private func isDataFresh() -> Bool {
        guard let lastUpdate = lastUpdateTime else { return false }
        return Date().timeIntervalSince(lastUpdate) < TimeInterval(settings.refreshInterval)
    }

    func onAppResignedActive() {
        pollingManager.onAppResignedActive()
    }

    // MARK: - Sleep/Wake Management

    func onSystemWillSleep() {
        // Cancel any in-progress wake retry
        wakeRetryTask?.cancel()
        wakeRetryTask = nil

        pollingManager.onSystemWillSleep()
        print("AppState: System going to sleep")
    }

    func onSystemDidWake() {
        // Cancel any previous wake retry task
        wakeRetryTask?.cancel()

        let sleepDuration = pollingManager.onSystemDidWake()
        let isSignificantSleep = sleepDuration >= Constants.WakeRecovery.significantSleepDuration

        if isSignificantSleep {
            usageManager.invalidateStaleData()
            print("AppState: Significant sleep (\(String(format: "%.0f", sleepDuration))s), invalidated stale data")
        }

        // Wake recovery: a single attempt after a short network-settle delay,
        // then let the scheduler drive subsequent ticks. No retry loop.
        // If the network is still down, NWPathMonitor will fire a refresh
        // when it comes back.
        wakeRetryTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let initialNanos = UInt64(Constants.WakeRecovery.initialDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: initialNanos)
            guard !Task.isCancelled else { return }

            await self.refresh(reason: "wake_recovery")
            guard !Task.isCancelled else { return }
            self.pollingManager.schedulePostWakeTimer()
        }
    }

    // MARK: - Network Recovery

    private func onNetworkBecameAvailable() {
        guard pollingManager.isRunning else { return }

        // If we have no data or data might be stale, refresh immediately
        if usageData == nil {
            print("AppState: Network became available with no data, triggering refresh")
            Task {
                await refresh(reason: "network_recovery")
            }
        }
    }
}
