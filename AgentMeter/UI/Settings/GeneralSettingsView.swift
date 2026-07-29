//
//  GeneralSettingsView.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI
import ServiceManagement

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLoginError: String?
    @State private var claudeWebSessionKey = ""
    @State private var isClaudeWebSessionKeyDirty = false
    @State private var claudeWebSessionKeyError: String?

    var body: some View {
        SettingsTabContainer {
            Form {
                Section(header: Text("Providers")) {
                    Toggle(
                        "Claude Code",
                        isOn: providerBinding(.claudeCode)
                    )
                    Toggle(
                        "Codex",
                        isOn: providerBinding(.codex)
                    )
                    TextField(
                        "Codex binary path (automatic when blank)",
                        text: $appState.settings.codexBinaryPath
                    )
                    .font(.caption)
                }

                ForEach(appState.enabledProviderIDs) { providerID in
                    if let metrics = appState.providerStates[providerID]?.snapshot?.metrics,
                       !metrics.isEmpty {
                        Section(header: Text("\(providerName(providerID)) Metrics")) {
                            ForEach(metrics.filter { $0.usedPercent != nil }) { metric in
                                metricSettingsRow(providerID: providerID, metric: metric)
                            }
                            Text("Up to two pinned metrics appear in the menu bar.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { appState.settings.launchAtLogin },
                        set: { newValue in
                            appState.settings.launchAtLogin = newValue
                            toggleLaunchAtLogin(newValue)
                        }
                    ))
                    .help("Automatically start AgentMeter when you log in.")
                    .accessibilityLabel("Launch at Login")
                    .accessibilityHint("When enabled, AgentMeter will start automatically when you log in")

                    if let error = launchAtLoginError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(ColorTheme.red)
                            .accessibilityLabel("Error: \(error)")
                    }

                    Toggle("Show in Dock", isOn: Binding(
                        get: { appState.settings.showInDock },
                        set: { newValue in
                            appState.settings.showInDock = newValue
                            updateDockVisibility(newValue)
                        }
                    ))
                    .help("Show AgentMeter icon in the Dock.")
                    .accessibilityLabel("Show in Dock")
                    .accessibilityHint("When enabled, AgentMeter will appear in the Dock")

                    Picker("Refresh Interval", selection: $appState.settings.refreshInterval) {
                        Text("30 Seconds").tag(30)
                        Text("1 Minute").tag(60)
                        Text("2 Minutes").tag(120)
                        Text("5 Minutes").tag(300)
                        Text("15 Minutes").tag(900)
                        Text("30 Minutes").tag(1800)
                        Text("1 Hour").tag(3600)
                    }
                    .accessibilityLabel("Refresh Interval")
                    .accessibilityHint("Choose how often to update usage data")
                }
                .background(ScrollBarHider())

                Section(header: Text("Web API Fallback (Experimental)")) {
                    TextField("Organization ID", text: $appState.settings.webOrganizationId)
                        .font(.caption)
                        .help("Your Claude organization UUID (from claude.ai URL)")
                    SecureField(
                        "Session Key",
                        text: Binding(
                            get: { claudeWebSessionKey },
                            set: {
                                claudeWebSessionKey = $0
                                isClaudeWebSessionKeyDirty = true
                            }
                        )
                    )
                        .font(.caption)
                        .help("sessionKey cookie from claude.ai browser session")
                        .onSubmit {
                            saveClaudeWebSessionKey()
                        }
                    if let claudeWebSessionKeyError {
                        Text(claudeWebSessionKeyError)
                            .font(.caption2)
                            .foregroundColor(ColorTheme.red)
                    }
                    Text("Used as backup when the OAuth API is rate limited.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollIndicators(.hidden)
            .onAppear {
                claudeWebSessionKey = appState.claudeWebSessionKey()
                isClaudeWebSessionKeyDirty = false
            }
            .onDisappear {
                if isClaudeWebSessionKeyDirty {
                    saveClaudeWebSessionKey()
                }
            }

        }
    }

    private func providerBinding(_ providerID: ProviderID) -> Binding<Bool> {
        Binding(
            get: { appState.settings.enabledProviderIDs.contains(providerID) },
            set: { appState.setProviderEnabled(providerID, isEnabled: $0) }
        )
    }

    private func providerName(_ providerID: ProviderID) -> String {
        providerID == .claudeCode ? "Claude Code" : "Codex"
    }

    private func metricSettingsRow(
        providerID: ProviderID,
        metric: UsageMetric
    ) -> some View {
        HStack {
            Toggle(
                metric.title,
                isOn: Binding(
                    get: {
                        appState.metricIsVisible(
                            providerID: providerID,
                            metricID: metric.id
                        )
                    },
                    set: {
                        appState.setMetricVisibility(
                            providerID: providerID,
                            metricID: metric.id,
                            isVisible: $0
                        )
                    }
                )
            )

            Button {
                appState.setMetricPinned(
                    providerID: providerID,
                    metricID: metric.id,
                    isPinned: !appState.metricIsPinned(
                        providerID: providerID,
                        metricID: metric.id
                    )
                )
            } label: {
                Image(
                    systemName: appState.metricIsPinned(
                        providerID: providerID,
                        metricID: metric.id
                    ) ? "pin.fill" : "pin"
                )
            }
            .buttonStyle(.plain)
            .help("Pin \(metric.title) to the menu bar")
            .accessibilityLabel("Pin \(metric.title)")
        }
    }

    private func saveClaudeWebSessionKey() {
        do {
            try appState.updateClaudeWebSessionKey(claudeWebSessionKey)
            isClaudeWebSessionKeyDirty = false
            claudeWebSessionKeyError = nil
        } catch {
            isClaudeWebSessionKeyDirty = true
            claudeWebSessionKeyError = "Could not save the session key: \(error.localizedDescription)"
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = "Failed to update: \(error.localizedDescription)"
            // Revert the setting on failure
            appState.settings.launchAtLogin = !enabled
        }
    }

    private func updateDockVisibility(_ showInDock: Bool) {
        if showInDock {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
