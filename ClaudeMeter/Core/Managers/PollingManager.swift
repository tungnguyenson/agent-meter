//
//  PollingManager.swift
//  ClaudeMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import Combine
import Network

class PollingManager {
    // MARK: - Configuration
    struct Config {
        var defaultInterval: TimeInterval = Constants.Polling.defaultInterval
        var minInterval: TimeInterval = Constants.Polling.minInterval
        var maxInterval: TimeInterval = Constants.Polling.maxInterval
        var backgroundInterval: TimeInterval = Constants.Polling.backgroundInterval

        // Adaptive polling thresholds
        var highUsageThreshold: Double = Constants.Polling.highUsageThreshold
        var criticalUsageThreshold: Double = Constants.Polling.criticalUsageThreshold

        // Circuit breaker for consecutive failures
        var maxConsecutiveFailures: Int = Constants.Polling.maxConsecutiveFailures
        var failureBackoffInterval: TimeInterval = Constants.Polling.failureBackoffInterval
    }

    // MARK: - State
    enum State {
        case idle
        case running
        case paused
        case background
    }

    private(set) var config: Config
    private var timer: Timer?
    private var onTick: (() async -> Void)?
    private var currentInterval: TimeInterval
    private(set) var state: State = .idle
    private var lastUsage: Double = 0

    // Circuit breaker state
    private var consecutiveFailures: Int = 0
    private var isInFailureBackoff: Bool = false

    // Sleep tracking
    private var sleepStartTime: Date?
    private(set) var lastSleepDuration: TimeInterval = 0

    // Network monitoring
    private var networkMonitor: NWPathMonitor?
    private var networkMonitorQueue: DispatchQueue?
    private(set) var isNetworkAvailable: Bool = true
    private var networkBecameAvailableCallback: (() -> Void)?

    // Rate limit gate
    private var lastRequestTime: Date?
    private var rateLimitCooldownUntil: Date?

    // Concurrent fetch guard
    private(set) var isFetching: Bool = false

    // MARK: - Initialization
    init(config: Config = Config()) {
        self.config = config
        self.currentInterval = config.defaultInterval
    }

    // MARK: - Public Methods

    func start(immediateRefresh: Bool = true, onTick: @escaping () async -> Void) {
        self.onTick = onTick
        state = .running
        scheduleTimer(interval: currentInterval)

        // Trigger immediate fetch only if requested (e.g. skip if cached data is still fresh)
        if immediateRefresh {
            Task {
                guard canMakeRequest(reason: "start") else { return }
                await onTick()
            }
        }
    }

    /// Resume from background state without triggering an immediate fetch.
    /// Use this when coming to foreground but data is still fresh.
    func resumeFromBackground() {
        guard state == .background else { return }
        state = .running
        let newInterval = calculateInterval(for: lastUsage)
        scheduleTimer(interval: newInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = .idle
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .background else { return }
        state = .running
        scheduleTimer(interval: currentInterval)
    }

    /// Called when app becomes active (foreground)
    func onAppBecameActive() {
        guard state == .background else { return }
        state = .running
        // Use calculated interval based on last known usage
        let newInterval = calculateInterval(for: lastUsage)
        scheduleTimer(interval: newInterval)

        // Immediate refresh when coming to foreground (performRefresh handles its own fetch guard)
        Task {
            guard canMakeRequest(reason: "app_became_active") else { return }
            await onTick?()
        }
    }

    /// Called when app goes to background
    func onAppResignedActive() {
        guard state == .running else { return }
        state = .background
        scheduleTimer(interval: config.backgroundInterval)
    }

    /// Update polling interval based on usage
    /// - Parameter usage: Current usage percentage (0-100)
    func updateForUsage(_ usage: Double) {
        lastUsage = usage
        guard state == .running, !isInFailureBackoff else { return }

        let newInterval = calculateInterval(for: usage)
        // Hysteresis: only change if difference is significant
        if abs(newInterval - currentInterval) > Constants.Polling.intervalChangeThreshold {
            currentInterval = newInterval
            scheduleTimer(interval: newInterval)
        }
    }

    /// Update configuration
    func updateConfig(_ newConfig: Config) {
        self.config = newConfig
        if state == .running {
            let newInterval = calculateInterval(for: lastUsage)
            scheduleTimer(interval: newInterval)
        }
    }

    /// Set default interval from settings
    func setDefaultInterval(_ interval: TimeInterval) {
        config.defaultInterval = max(config.minInterval, min(interval, config.maxInterval))
        if state == .running {
            scheduleTimer(interval: config.defaultInterval)
        }
    }

    /// Record a successful fetch - resets circuit breaker
    func recordSuccess() {
        consecutiveFailures = 0
        if isInFailureBackoff {
            isInFailureBackoff = false
            // Return to normal polling interval
            if state == .running {
                let newInterval = calculateInterval(for: lastUsage)
                scheduleTimer(interval: newInterval)
            }
        }
    }

    /// Record a failed fetch - triggers circuit breaker after threshold
    func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= config.maxConsecutiveFailures && !isInFailureBackoff {
            isInFailureBackoff = true
            // Switch to longer backoff interval
            if state == .running {
                scheduleTimer(interval: config.failureBackoffInterval)
            }
        }
    }

    // MARK: - Sleep/Wake Management

    /// Called when system is about to sleep
    func onSystemWillSleep() {
        sleepStartTime = Date()
        pause()
        print("PollingManager: System going to sleep at \(sleepStartTime!)")
    }

    /// Called when system wakes from sleep. Returns the sleep duration.
    @discardableResult
    func onSystemDidWake() -> TimeInterval {
        if let start = sleepStartTime {
            lastSleepDuration = Date().timeIntervalSince(start)
        } else {
            lastSleepDuration = 0
        }
        sleepStartTime = nil
        state = .running
        // Do NOT schedule timer here - AppState will manage post-wake timing
        print("PollingManager: System woke after \(String(format: "%.0f", lastSleepDuration))s sleep")
        return lastSleepDuration
    }

    /// Schedule normal polling timer after wake recovery completes
    func schedulePostWakeTimer() {
        guard state == .running else { return }
        let interval = calculateInterval(for: lastUsage)
        scheduleTimer(interval: interval)
        print("PollingManager: Post-wake timer scheduled at \(interval)s interval")
    }

    // MARK: - Network Monitoring

    func startNetworkMonitor(onBecameAvailable: @escaping () -> Void) {
        networkBecameAvailableCallback = onBecameAvailable
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.claudemeter.networkmonitor")
        networkMonitor = monitor
        networkMonitorQueue = queue

        monitor.pathUpdateHandler = { [weak self] path in
            let wasAvailable = self?.isNetworkAvailable ?? true
            let isNowAvailable = path.status == .satisfied
            self?.isNetworkAvailable = isNowAvailable

            if !wasAvailable && isNowAvailable {
                print("PollingManager: Network became available")
                DispatchQueue.main.async {
                    self?.networkBecameAvailableCallback?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
        networkMonitorQueue = nil
        networkBecameAvailableCallback = nil
    }

    // MARK: - Concurrent Fetch Guard

    /// Mark fetch as started. Returns false if already fetching.
    func beginFetch() -> Bool {
        guard !isFetching else {
            print("PollingManager: Fetch already in progress, skipping")
            return false
        }
        isFetching = true
        lastRequestTime = Date()
        return true
    }

    /// Mark fetch as completed
    func endFetch() {
        isFetching = false
    }

    // MARK: - Rate Limit Gate

    /// Central gate for all API requests. Returns false if request should be blocked.
    func canMakeRequest(reason: String = "unknown") -> Bool {
        // Check 429 cooldown
        if let cooldownUntil = rateLimitCooldownUntil, Date() < cooldownUntil {
            let remaining = cooldownUntil.timeIntervalSince(Date())
            print("PollingManager: Request blocked (\(reason)) - rate limit cooldown, \(String(format: "%.0f", remaining))s remaining")
            return false
        }

        // Check minimum request interval
        if let lastRequest = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < Constants.RateLimit.minimumRequestInterval {
                print("PollingManager: Request blocked (\(reason)) - too soon, \(String(format: "%.0f", Constants.RateLimit.minimumRequestInterval - elapsed))s remaining")
                return false
            }
        }

        // Check concurrent fetch
        if isFetching {
            print("PollingManager: Request blocked (\(reason)) - fetch already in progress")
            return false
        }

        return true
    }

    /// Record a 429 rate limit hit and enter cooldown
    func recordRateLimitHit(retryAfter: TimeInterval?) {
        let cooldown = min(retryAfter ?? Constants.RateLimit.defaultCooldownDuration, Constants.RateLimit.maxCooldownDuration)
        rateLimitCooldownUntil = Date().addingTimeInterval(cooldown)

        // Activate circuit breaker immediately
        consecutiveFailures = config.maxConsecutiveFailures
        isInFailureBackoff = true

        // Reschedule timer to fire after cooldown
        if state == .running {
            scheduleTimer(interval: cooldown)
        }

        print("PollingManager: Rate limited - cooldown for \(String(format: "%.0f", cooldown))s")
    }

    /// Check if data is stale enough to warrant a new request
    func isDataStale(lastUpdateTime: Date?) -> Bool {
        guard let lastUpdate = lastUpdateTime else { return true }
        return Date().timeIntervalSince(lastUpdate) >= currentInterval
    }

    // MARK: - Private Methods

    /// Calculate optimal polling interval based on current usage
    func calculateInterval(for usage: Double) -> TimeInterval {
        // Always use the default interval from app settings (as requested)
        return config.defaultInterval
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        currentInterval = interval

        // Use Timer(timeInterval:...) + RunLoop.main.add instead of scheduledTimer
        // to avoid double-registration: scheduledTimer adds to .default mode, and
        // then add(_:forMode:.common) would add it again (common includes .default).
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                guard let self = self else { return }
                guard self.canMakeRequest(reason: "timer") else { return }
                // performRefresh handles its own beginFetch/endFetch guard
                await self.onTick?()
            }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }
}

// MARK: - Convenience
extension PollingManager {
    var isRunning: Bool {
        return state == .running
    }

    var isPaused: Bool {
        return state == .paused
    }

    var isInBackground: Bool {
        return state == .background
    }

    var currentPollingInterval: TimeInterval {
        return currentInterval
    }
}
