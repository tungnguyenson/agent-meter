//
//  AppSettings.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import Foundation
import SwiftUI

// MARK: - Display Mode
enum DisplayMode: String, Codable, CaseIterable {
    case iconOnly = "Icon Only"
    case compact = "Compact"
    case detailed = "Detailed"
}

// MARK: - Detailed Mode Style
enum DetailedModeStyle: String, Codable, CaseIterable {
    case fixed = "12% 5h | 20% 7d"
    case countdown = "12% 3h 46m | 20% 6d 7h"
}

// MARK: - Color Scheme
enum AppColorScheme: String, Codable, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - App Settings
struct AppSettings: Codable, Equatable {
    // Providers
    var enabledProviderIDs: [ProviderID] = [.claudeCode]
    var selectedProviderID: ProviderID = .claudeCode
    var metricVisibilityByProvider: [ProviderID: [String: Bool]] = [:]
    var pinnedMetricIDsByProvider: [ProviderID: [String]] = [
        .claudeCode: ["claude.five-hour", "claude.seven-day"],
        .codex: ["codex.codex.primary", "codex.codex.secondary"],
        .cursor: ["cursor.plan.auto", "cursor.plan.api"]
    ]
    var codexBinaryPath: String = ""

    // Display
    var displayMode: DisplayMode = .detailed
    var detailedModeStyle: DetailedModeStyle = .countdown
    var colorScheme: AppColorScheme = .auto
    var showInDock: Bool = false
    var showSonnetLimit: Bool = false
    var showDesignLimit: Bool = true
    var showExtraUsage: Bool = false
    var customMenuBarColorsEnabled: Bool = false
    var menuBarIconColorHex: String = "#FFFFFF"
    var menuBarTextColorHex: String = "#FFFFFF"

    // Polling
    var refreshInterval: Int = Constants.Settings.defaultRefreshInterval

    // Startup
    var launchAtLogin: Bool = false

    // Notifications
    var notifyAt: [Int] = Constants.Settings.defaultNotifyThresholds
    var notificationsEnabled: Bool = true

    // Web API Fallback (claude.ai session credentials)
    var webSessionKey: String = ""
    var webOrganizationId: String = ""

    private enum CodingKeys: String, CodingKey {
        case enabledProviderIDs
        case selectedProviderID
        case metricVisibilityByProvider
        case pinnedMetricIDsByProvider
        case codexBinaryPath
        case displayMode
        case detailedModeStyle
        case colorScheme
        case showInDock
        case showSonnetLimit
        case showDesignLimit
        case showExtraUsage
        case customMenuBarColorsEnabled
        case menuBarIconColorHex
        case menuBarTextColorHex
        case refreshInterval
        case launchAtLogin
        case notifyAt
        case notificationsEnabled
        case webSessionKey
        case webOrganizationId
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        let hasProviderSettings = container.contains(.enabledProviderIDs)
        enabledProviderIDs = try container.decodeIfPresent(
            [ProviderID].self,
            forKey: .enabledProviderIDs
        ) ?? [.claudeCode]
        selectedProviderID = try container.decodeIfPresent(
            ProviderID.self,
            forKey: .selectedProviderID
        ) ?? .claudeCode
        metricVisibilityByProvider = try container.decodeIfPresent(
            [ProviderID: [String: Bool]].self,
            forKey: .metricVisibilityByProvider
        ) ?? [:]
        pinnedMetricIDsByProvider = try container.decodeIfPresent(
            [ProviderID: [String]].self,
            forKey: .pinnedMetricIDsByProvider
        ) ?? [.claudeCode: ["claude.five-hour", "claude.seven-day"]]
        codexBinaryPath = try container.decodeIfPresent(
            String.self,
            forKey: .codexBinaryPath
        ) ?? ""

        displayMode = try container.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        detailedModeStyle = try container.decodeIfPresent(DetailedModeStyle.self, forKey: .detailedModeStyle) ?? defaults.detailedModeStyle
        colorScheme = try container.decodeIfPresent(AppColorScheme.self, forKey: .colorScheme) ?? defaults.colorScheme
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? defaults.showInDock
        showSonnetLimit = try container.decodeIfPresent(Bool.self, forKey: .showSonnetLimit) ?? defaults.showSonnetLimit
        showDesignLimit = try container.decodeIfPresent(Bool.self, forKey: .showDesignLimit) ?? defaults.showDesignLimit
        showExtraUsage = try container.decodeIfPresent(Bool.self, forKey: .showExtraUsage) ?? defaults.showExtraUsage
        customMenuBarColorsEnabled = try container.decodeIfPresent(Bool.self, forKey: .customMenuBarColorsEnabled) ?? defaults.customMenuBarColorsEnabled
        menuBarIconColorHex = try container.decodeIfPresent(String.self, forKey: .menuBarIconColorHex) ?? defaults.menuBarIconColorHex
        menuBarTextColorHex = try container.decodeIfPresent(String.self, forKey: .menuBarTextColorHex) ?? defaults.menuBarTextColorHex
        refreshInterval = try container.decodeIfPresent(Int.self, forKey: .refreshInterval) ?? defaults.refreshInterval
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        notifyAt = try container.decodeIfPresent([Int].self, forKey: .notifyAt) ?? defaults.notifyAt
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? defaults.notificationsEnabled
        webSessionKey = try container.decodeIfPresent(String.self, forKey: .webSessionKey) ?? defaults.webSessionKey
        webOrganizationId = try container.decodeIfPresent(String.self, forKey: .webOrganizationId) ?? defaults.webOrganizationId

        if !hasProviderSettings {
            metricVisibilityByProvider[.claudeCode] = [
                "claude.seven-day-sonnet": showSonnetLimit,
                "claude.seven-day-design": showDesignLimit,
                "claude.extra-usage": showExtraUsage
            ]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabledProviderIDs, forKey: .enabledProviderIDs)
        try container.encode(selectedProviderID, forKey: .selectedProviderID)
        try container.encode(metricVisibilityByProvider, forKey: .metricVisibilityByProvider)
        try container.encode(pinnedMetricIDsByProvider, forKey: .pinnedMetricIDsByProvider)
        try container.encode(codexBinaryPath, forKey: .codexBinaryPath)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(detailedModeStyle, forKey: .detailedModeStyle)
        try container.encode(colorScheme, forKey: .colorScheme)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(showSonnetLimit, forKey: .showSonnetLimit)
        try container.encode(showDesignLimit, forKey: .showDesignLimit)
        try container.encode(showExtraUsage, forKey: .showExtraUsage)
        try container.encode(customMenuBarColorsEnabled, forKey: .customMenuBarColorsEnabled)
        try container.encode(menuBarIconColorHex, forKey: .menuBarIconColorHex)
        try container.encode(menuBarTextColorHex, forKey: .menuBarTextColorHex)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(notifyAt, forKey: .notifyAt)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(webOrganizationId, forKey: .webOrganizationId)
        // webSessionKey is intentionally decode-only for one-time legacy migration.
    }

    // Computed property for backward compatibility
    var notifyAt90: Bool {
        get { notifyAt.contains(90) }
        set {
            if newValue && !notifyAt.contains(90) {
                notifyAt.append(90)
                notifyAt.sort()
            } else if !newValue {
                notifyAt.removeAll { $0 == 90 }
            }
        }
    }

    // Check if notification should be sent for a threshold
    func shouldNotify(at threshold: Int) -> Bool {
        return notificationsEnabled && notifyAt.contains(threshold)
    }

    // Get all enabled thresholds sorted
    var sortedThresholds: [Int] {
        return notifyAt.sorted()
    }
}

// MARK: - Settings Keys
extension AppSettings {
    static let userDefaultsKey = Constants.Settings.userDefaultsKey

    // Validation bounds
    private static let minRefreshInterval = Constants.Settings.minRefreshInterval
    private static let maxRefreshInterval = Constants.Settings.maxRefreshInterval

    static func load() -> AppSettings {
        guard let data = currentOrLegacySettingsData(),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        if settings.webSessionKey.isEmpty,
           let legacyData = legacySettingsData(),
           let legacySettings = try? JSONDecoder().decode(
               AppSettings.self,
               from: legacyData
           ),
           !legacySettings.webSessionKey.isEmpty {
            settings.webSessionKey = legacySettings.webSessionKey
        }
        // Validate loaded settings
        settings.validate()
        return settings
    }

    private static func currentOrLegacySettingsData() -> Data? {
        if let current = UserDefaults.standard.data(forKey: userDefaultsKey) {
            return current
        }
        return legacySettingsData()
    }

    private static func legacySettingsData() -> Data? {
        UserDefaults(suiteName: Constants.Settings.legacyBundleIdentifier)?
            .data(forKey: Constants.Settings.legacyUserDefaultsKey)
    }

    static func removeLegacySettingsData() {
        UserDefaults(suiteName: Constants.Settings.legacyBundleIdentifier)?
            .removeObject(forKey: Constants.Settings.legacyUserDefaultsKey)
    }

    func save() {
        var validatedSettings = self
        validatedSettings.validate()
        if let data = try? JSONEncoder().encode(validatedSettings) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }

    func updatingMetricPin(
        providerID: ProviderID,
        metricID: String,
        isPinned: Bool
    ) -> AppSettings {
        var updated = self
        let currentPins = pinnedMetricIDsByProvider[providerID] ?? []
        let pinsWithoutMetric = currentPins.filter { $0 != metricID }
        let nextPins = isPinned
            ? Array((pinsWithoutMetric + [metricID]).suffix(2))
            : pinsWithoutMetric
        var allPins = pinnedMetricIDsByProvider
        allPins[providerID] = nextPins
        updated.pinnedMetricIDsByProvider = allPins
        return updated
    }

    /// Validate and fix any out-of-bounds values
    mutating func validate() {
        enabledProviderIDs = enabledProviderIDs.reduce(into: []) { result, providerID in
            if !result.contains(providerID) {
                result.append(providerID)
            }
        }
        if enabledProviderIDs.isEmpty {
            enabledProviderIDs = [.claudeCode]
        }
        if !enabledProviderIDs.contains(selectedProviderID) {
            selectedProviderID = enabledProviderIDs[0]
        }
        pinnedMetricIDsByProvider = pinnedMetricIDsByProvider.mapValues {
            Array($0.reduce(into: []) { result, metricID in
                if !result.contains(metricID) {
                    result.append(metricID)
                }
            }.prefix(2))
        }

        // Validate refresh interval bounds
        refreshInterval = max(Self.minRefreshInterval, min(refreshInterval, Self.maxRefreshInterval))

        // Validate notification thresholds (must be between 0 and 100)
        notifyAt = notifyAt.filter { $0 > 0 && $0 <= 100 }.sorted()

        // Ensure at least default thresholds if empty
        if notifyAt.isEmpty {
            notifyAt = Constants.Settings.defaultNotifyThresholds
        }
    }
}
