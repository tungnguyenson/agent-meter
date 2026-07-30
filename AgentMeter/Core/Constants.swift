//
//  Constants.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation

/// Centralized constants for the AgentMeter application
enum Constants {

    // MARK: - API Configuration
    enum API {
        static let baseURL = "https://api.anthropic.com"
        static let usageEndpoint = "/api/oauth/usage"

        // Timeouts
        static let requestTimeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 60

        // Headers
        /// Client name used in the `User-Agent` header. Combined with the
        /// installed CLI version by `ClaudeCodeVersionResolver`.
        static let clientName = "claude-code"
        /// Fallback CLI version, used only when the installed Claude Code
        /// version cannot be detected. Keep reasonably current so requests are
        /// not rejected on machines where detection fails. See
        /// `ClaudeCodeVersionResolver` for the runtime resolution path.
        static let fallbackClientVersion = "2.1.201"
        /// Static fallback `User-Agent`. Prefer
        /// `ClaudeCodeVersionResolver.shared.userAgent`, which reflects the
        /// version of the Claude Code CLI actually installed on this machine.
        static let userAgent = "\(clientName)/\(fallbackClientVersion)"
        static let anthropicBeta = "oauth-2025-04-20"
        static let contentType = "application/json"
        static let acceptType = "application/json"

        // Web API fallback (claude.ai)
        static let webBaseURL = "https://claude.ai"
        static let webUsageEndpoint = "/api/organizations/%@/usage"
    }

    // MARK: - Rate Limit Configuration
    enum RateLimit {
        static let minimumRequestInterval: TimeInterval = 15
        /// Fallback cooldown when a 429 has no parseable Retry-After value.
        static let defaultCooldownDuration: TimeInterval = 300
        static let maxCooldownDuration: TimeInterval = 86400
        static let stalenessThreshold: TimeInterval = 30
        static let manualRefreshDebounce: TimeInterval = 5
    }

    // MARK: - Polling Configuration
    enum Polling {
        static let defaultInterval: TimeInterval = 30
        static let minInterval: TimeInterval = 30
        static let maxInterval: TimeInterval = 3600
        static let backgroundInterval: TimeInterval = 900  // 15 minutes

        // Adaptive polling thresholds
        static let highUsageThreshold: Double = 75
        static let criticalUsageThreshold: Double = 90

        // Circuit breaker
        static let maxConsecutiveFailures = 3
        static let failureBackoffInterval: TimeInterval = 600  // 10 minutes

        // Hysteresis for interval changes
        static let intervalChangeThreshold: TimeInterval = 10
    }

    // MARK: - Cache Configuration
    enum Cache {
        static let directoryName = "AgentMeter"
        static let usageDataFilename = "usage_data.json"
        static let maxAge: TimeInterval = 3600 * 24  // 24 hours
        static let version = 1
    }

    // MARK: - Logging Configuration
    enum Logging {
        static let directoryName = "AgentMeter/Logs"
        static let filename = "api_logs.json"
        static let maxEntries = 50
    }


    // MARK: - Notification Configuration
    enum Notification {
        static let throttleInterval: TimeInterval = 3600  // 1 hour
        static let hysteresisBuffer: Double = 5.0

        // Default thresholds
        static let defaultThresholds: [Int] = [75, 90, 95]

        // UserDefaults keys
        static let throttleTimesKey = "com.agentmeter.throttleTimes"
        static let notificationStateKey = "com.agentmeter.notificationState"

        // Reset detection
        static let resetDropThreshold: Double = 40.0
        static let resetLowThreshold: Double = 20.0
    }

    // MARK: - Keychain Configuration
    enum Keychain {
        static let serviceName = "Claude Code-credentials"
    }

    // MARK: - Cursor Configuration
    /// Contract for these values is not public; see `docs/providers/cursor.md`.
    enum Cursor {
        static let baseURL = "https://cursor.com"
        static let keychainService = "cursor-access-token"
        static let keychainAccount = "cursor-user"
    }

    // MARK: - App Settings
    enum Settings {
        static let userDefaultsKey = "com.agentmeter.settings"
        static let legacyUserDefaultsKey = "com.claudemeter.settings"
        static let legacyBundleIdentifier = "com.claudemeter.app"

        // Validation bounds
        static let minRefreshInterval = 30
        static let maxRefreshInterval = 3600

        // Defaults
        static let defaultRefreshInterval = 300
        static let defaultNotifyThresholds: [Int] = [75, 90, 95]
    }

    // MARK: - Credentials
    enum Credentials {
        static let expirationWarningThreshold: TimeInterval = 5 * 60  // 5 minutes
        static let defaultSubscriptionType = "pro"
    }

    // MARK: - UI Dimensions
    enum UI {
        static let menuBarIconSize: CGFloat = 18
        static let menuBarIconLineWidth: CGFloat = 2.5
        static let settingsMaxWidth: CGFloat = 400
        static let aboutLogoSize: CGFloat = 64
    }

    // MARK: - All-Providers Overview
    /// Tuning for the compact surfaces that summarise every provider at once —
    /// the menu bar title and the all-providers overview screen. Both show the
    /// same short list of metrics so the popover explains what the menu bar says.
    enum Overview {
        /// Metrics rendered per provider. Matches the menu bar's two-segment
        /// title and the two-pin cap enforced by `AppSettings.validate()`.
        static let pinnedMetricLimit = 2

        /// Diameter and stroke width of a provider's metric ring.
        static let metricRingSize: CGFloat = 46
        static let metricRingLineWidth: CGFloat = 5

        /// Fixed width of one metric column, so a provider with a single
        /// pinned metric lines up with one that has two rather than
        /// stretching to fill the row.
        static let metricColumnWidth: CGFloat = 120
    }

    // MARK: - Wake Recovery Configuration
    enum WakeRecovery {
        static let initialDelay: TimeInterval = 2.0
        static let significantSleepDuration: TimeInterval = 300  // 5 minutes
    }

    // MARK: - Usage Window Forecast
    /// Tuning for the time-aware pace forecast (see `WindowForecast`). Raw
    /// utilization is meaningless without time: 50% one hour into a five-hour
    /// window is on pace to blow past the cap, while 50% four hours in is safe.
    enum Window {
        /// Fixed window durations, used to derive the window start from
        /// `resetsAt` (`start = resetsAt − duration`).
        static let fiveHourDuration: TimeInterval = 5 * 3600      // 18,000s
        static let sevenDayDuration: TimeInterval = 7 * 86400     // 604,800s

        /// Below this elapsed fraction the average-pace projection is too noisy
        /// to trust — a couple of calls right after reset would read as "will
        /// run out" — so callers fall back to a plain percentage colour.
        static let minElapsedFractionForForecast: Double = 0.05

        /// Projected end-of-window usage (%) that flips green → yellow while the
        /// window is still on track to finish under the cap.
        static let projectedWatchThreshold: Double = 90

        /// When the window *will* exhaust, the fraction of the remaining time at
        /// which exhaustion counts as "early" (→ red) versus "late" (→ orange).
        static let earlyExhaustRatio: Double = 0.5

        /// Absolute near-cap override: at or above this utilization the window is
        /// critical regardless of pace (it is nearly out right now).
        static let nearCapThreshold: Double = 95
    }

    // MARK: - Statistics Configuration
    enum Statistics {
        static let storageFileName = "usage_statistics.json"
        static let maxHistoryDays = 365
        static let refreshInterval: TimeInterval = 300  // 5 minutes
        static let claudeProjectsPath = "~/.claude/projects"
    }
}
