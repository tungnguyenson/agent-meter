//
//  PopoverView.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var appState: AppState
    @State private var showingSettings = false
    @State private var showingLogs = false
    @State private var isRefreshDisabled = false

    // Size constants
    private let popoverWidth: CGFloat = 380
    private let popoverHeight: CGFloat = 420
    private let contentPadding: CGFloat = 16

    // Header layout constants
    private let headerGroupSpacing: CGFloat = 8
    private let headerIconSpacing: CGFloat = 6
    private let providerPickerWidth: CGFloat = 100

    var body: some View {
        ZStack {
            // Main content - No frame, adapts to parent size
            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, contentPadding)
                    .padding(.top, contentPadding)

                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 8)

                // Content
                contentView

                Divider()
                    .opacity(0.3)

                footerView
                    .padding(.horizontal, contentPadding)
                    .padding(.vertical, 10)
            }
            .opacity(showingSettings || showingLogs ? 0 : 1)

            // Settings - full page (not overlay)
            if showingSettings {
                SettingsView(appState: appState, onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingSettings = false
                    }
                })
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Logs - full page
            if showingLogs {
                DebugLogView(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingLogs = false
                    }
                })
                .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .background(.ultraThinMaterial)
        .preferredColorScheme(appState.settings.colorScheme.colorScheme)
        .animation(.easeInOut(duration: 0.25), value: showingSettings)
        .animation(.easeInOut(duration: 0.25), value: showingLogs)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if let snapshot = appState.selectedSnapshot {
            usageContentView(snapshot: snapshot)
        } else if let error = appState.error {
            errorView(error: error)
        } else {
            emptyStateView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: headerGroupSpacing) {
            Text("Agent Meter")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)

            providerControls

            Spacer(minLength: headerGroupSpacing)

            utilityControls
        }
        .frame(height: 22)
    }

    private var providerControls: some View {
        HStack(spacing: 4) {
            FocusRinglessProviderPicker(
                providerIDs: appState.enabledProviderIDs,
                selectedProviderID: appState.selectedProviderID,
                providerName: providerName,
                selectProvider: appState.selectProvider
            )
            .frame(width: providerPickerWidth)
            .accessibilityLabel("Usage provider")

            Image(systemName: providerHealthSymbol)
                .font(.caption2)
                .foregroundColor(providerHealthColor)
                .help(providerHealthDescription)
                .accessibilityLabel(providerHealthDescription)
        }
    }

    private var utilityControls: some View {
        HStack(spacing: headerIconSpacing) {
            ProgressView()
                .controlSize(.small)
                .opacity(appState.isLoading ? 1 : 0)
                .accessibilityLabel("Loading usage data")

            FocusRinglessIconButton(
                systemName: "arrow.clockwise",
                help: "Refresh usage data",
                accessibilityLabel: "Refresh",
                action: { triggerRefresh(reason: "manual_refresh") }
            )
            .opacity(isRefreshDisabled ? 0.5 : 1.0)
            .disabled(isRefreshDisabled)

            FocusRinglessIconButton(
                systemName: "list.bullet.rectangle.portrait",
                help: "View API logs",
                accessibilityLabel: "View Logs",
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingLogs = true
                    }
                }
            )

            FocusRinglessIconButton(
                systemName: "gear",
                help: "Open settings",
                accessibilityLabel: "Settings",
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingSettings = true
                    }
                }
            )

            FocusRinglessIconButton(
                systemName: "xmark.circle",
                help: "Quit AgentMeter",
                accessibilityLabel: "Quit",
                action: { NSApplication.shared.terminate(nil) }
            )
            .accessibilityHint("Double tap to quit AgentMeter")
        }
        .fixedSize()
    }

    // MARK: - Usage Content

    private func usageContentView(snapshot: UsageSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if snapshot.metrics.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Usage data structure not recognized")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                ForEach(visibleMetrics(in: snapshot)) { metric in
                    if metric.usedValue != nil || metric.limitValue != nil {
                        valueMetricCard(metric)
                    } else if let usage = metric.usedPercent {
                        UsageCardView(
                            title: metric.title,
                            usage: usage,
                            resetsAt: metric.resetsAt,
                            windowDuration: metric.windowDuration ?? 0
                        )
                    } else {
                        valueMetricCard(metric)
                    }
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.vertical, 8)
            .background(ScrollBarHider())
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Error View

    private func errorView(error: Error) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(ColorTheme.orange)

            Text("Error loading data")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Recovery suggestion if available
            if let appError = error as? AppError,
               let suggestion = appError.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Retry") {
                guard !isRefreshDisabled else { return }
                isRefreshDisabled = true
                Task {
                    await appState.refreshSelected(reason: "retry_button")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }
            .buttonStyle(.bordered)
            .focusEffectDisabled()
            .disabled(isRefreshDisabled)

            Spacer()
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No Usage Data")
                .font(.headline)

            Text("Click refresh to load \(providerName(appState.selectedProviderID)) usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh") {
                triggerRefresh(reason: "empty_state_refresh")
            }
            .buttonStyle(.bordered)
            .focusEffectDisabled()
            .disabled(isRefreshDisabled)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack {
                if let error = appState.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(ColorTheme.orange)
                    Text(footerErrorText(for: error))
                        .font(.caption2)
                        .foregroundColor(ColorTheme.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let lastUpdate = appState.lastUpdateTime {
                    let nextUpdate = lastUpdate.addingTimeInterval(TimeInterval(appState.settings.refreshInterval))
                    let timeString = DateFormatter.localizedString(from: nextUpdate, dateStyle: .none, timeStyle: .short)
                    Text("Updated \(lastUpdateDescription(for: lastUpdate)). Next update: \(timeString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button("Reset now") {
                        triggerRefresh(reason: "manual_refresh")
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .disabled(isRefreshDisabled)
                    .opacity(isRefreshDisabled ? 0.5 : 1.0)
                }
            }
        }
    }

    private func triggerRefresh(reason: String) {
        guard !isRefreshDisabled else { return }
        isRefreshDisabled = true
        Task {
            await appState.refreshSelected(reason: reason)
            try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
            isRefreshDisabled = false
        }
    }

    private func providerName(_ providerID: ProviderID) -> String {
        providerID.displayName
    }

    private var providerHealthSymbol: String {
        if appState.error != nil { return "exclamationmark.circle.fill" }
        if appState.selectedSnapshot != nil { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    private var providerHealthColor: Color {
        if appState.error != nil { return ColorTheme.orange }
        if appState.selectedSnapshot != nil { return ColorTheme.green }
        return .secondary
    }

    private var providerHealthDescription: String {
        if let error = appState.error {
            return "\(providerName(appState.selectedProviderID)) unavailable: \(error.localizedDescription)"
        }
        if appState.selectedSnapshot != nil {
            return "\(providerName(appState.selectedProviderID)) connected"
        }
        return "\(providerName(appState.selectedProviderID)) has not been checked"
    }

    private func visibleMetrics(in snapshot: UsageSnapshot) -> [UsageMetric] {
        let visibility = appState.settings.metricVisibilityByProvider[snapshot.providerID] ?? [:]
        return snapshot.metrics.filter { visibility[$0.id] ?? true }
    }

    private func valueMetricCard(_ metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(.headline)
            HStack {
                Text(metric.usedValue.map(formatMetricValue) ?? "Available")
                    .font(.title3.monospacedDigit())
                if let limit = metric.limitValue {
                    Text("/ \(formatMetricValue(limit))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let unit = metric.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let usedPercent = metric.usedPercent {
                ProgressBarView(
                    progress: min(max(usedPercent / 100, 0), 1),
                    showPercentage: true,
                    height: 6
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func formatMetricValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func lastUpdateDescription(for lastUpdate: Date) -> String {
        if Date().timeIntervalSince(lastUpdate) < 60 {
            return "less than 1 minute ago"
        }
        return lastUpdate.relativeDescription
    }

    /// Compact footer text for errors. When the scheduler is in an active
    /// rate-limit cooldown, show the next update time instead of the full
    /// localized description.
    private func footerErrorText(for error: Error) -> String {
        if let cooldownUntil = appState.pollingManager.activeRateLimitCooldown {
            let timeString = DateFormatter.localizedString(
                from: cooldownUntil,
                dateStyle: .none,
                timeStyle: .short
            )
            if let lastUpdate = appState.lastUpdateTime {
                return "Updated \(lastUpdateDescription(for: lastUpdate)). Next update: \(timeString) (rate limit)"
            }
            return "Rate limit. Next update: \(timeString)"
        }
        return error.localizedDescription
    }

    // MARK: - Extra Usage Card

    private func extraUsageCardView(extra: ExtraUsage) -> some View {
        let utilization = extra.utilization ?? 0
        let progressColor = ColorTheme.colorForUsage(utilization)
        let isCritical = utilization >= 90

        return VStack(spacing: 12) {
            // Header
            HStack {
                Text("Extra Usage")
                    .font(.headline)
                Spacer()
                AnimatedPercentage(value: utilization)
            }

            // Progress Ring and Details
            HStack(spacing: 16) {
                ProgressRingView(
                    progress: utilization / 100.0,
                    color: progressColor,
                    lineWidth: 6,
                    size: 50
                )
                .glowEffect(isActive: isCritical, color: progressColor)

                VStack(alignment: .leading, spacing: 4) {
                    ProgressBarView(
                        progress: utilization / 100.0,
                        showPercentage: false,
                        height: 6
                    )
                    .frame(maxWidth: .infinity)

                    // Spending info
                    if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle")
                                .font(.caption2)
                            Text(String(format: "$%.2f spent of $%.0f limit", used / 100.0, limit / 100.0))
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: isCritical ? progressColor.opacity(0.3) : .clear, radius: isCritical ? 8 : 0)
    }

    // MARK: - Powered By View

    private var poweredByView: some View {
        Button(action: {
            if let url = URL(string: "https://puq.ai") {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 4) {
                Text("powered by")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))

                HStack(spacing: 2) {
                    Text("puq")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(ColorTheme.accent)
                    Text(".ai")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Visit puq.ai")
    }
}

// MARK: - ScrollBar Hider

struct ScrollBarHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            Self.hideScrollBars(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.hideScrollBars(for: nsView)
    }

    private static func hideScrollBars(for view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
    }
}

// MARK: - AppKit Controls Without Focus Rings

private struct FocusRinglessIconButton: NSViewRepresentable {
    let systemName: String
    let help: String
    let accessibilityLabel: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = QuietFocusButton()
        button.title = ""
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.performAction)
        button.toolTip = help
        button.setAccessibilityLabel(accessibilityLabel)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.image = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: accessibilityLabel
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        )
        button.contentTintColor = .labelColor
        button.isEnabled = isEnabled
        button.focusRingType = .none
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct FocusRinglessProviderPicker: NSViewRepresentable {
    let providerIDs: [ProviderID]
    let selectedProviderID: ProviderID
    let providerName: (ProviderID) -> String
    let selectProvider: (ProviderID) -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(selectProvider: selectProvider)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = QuietFocusPopUpButton(frame: .zero, pullsDown: false)
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged)
        button.setAccessibilityLabel("Usage provider")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.providerIDs = providerIDs
        context.coordinator.selectProvider = selectProvider
        button.removeAllItems()
        button.addItems(withTitles: providerIDs.map(providerName))
        if let index = providerIDs.firstIndex(of: selectedProviderID) {
            button.selectItem(at: index)
        }
        button.isEnabled = isEnabled
        button.focusRingType = .none
    }

    final class Coordinator: NSObject {
        var providerIDs: [ProviderID] = []
        var selectProvider: (ProviderID) -> Void

        init(selectProvider: @escaping (ProviderID) -> Void) {
            self.selectProvider = selectProvider
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard providerIDs.indices.contains(sender.indexOfSelectedItem) else { return }
            selectProvider(providerIDs[sender.indexOfSelectedItem])
        }
    }
}

private final class QuietFocusButton: NSButton {
    private var showsKeyboardFocus = false

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        showsKeyboardFocus = accepted && NSApp.currentEvent?.type == .keyDown
        updateKeyboardFocusAppearance()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        showsKeyboardFocus = false
        updateKeyboardFocusAppearance()
        return accepted
    }

    private func updateKeyboardFocusAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = showsKeyboardFocus
            ? NSColor.quaternaryLabelColor.withAlphaComponent(0.45).cgColor
            : NSColor.clear.cgColor
    }
}

private final class QuietFocusPopUpButton: NSPopUpButton {
    private var showsKeyboardFocus = false

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        showsKeyboardFocus = accepted && NSApp.currentEvent?.type == .keyDown
        updateKeyboardFocusAppearance()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        showsKeyboardFocus = false
        updateKeyboardFocusAppearance()
        return accepted
    }

    private func updateKeyboardFocusAppearance() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = showsKeyboardFocus
            ? NSColor.quaternaryLabelColor.withAlphaComponent(0.45).cgColor
            : NSColor.clear.cgColor
    }
}

// MARK: - Preview

#Preview {
    PopoverView(appState: AppState())
}
