//
//  PopoverView.swift
//  ClaudeMeter
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
        if let data = appState.usageData {
            usageContentView(data: data)
        } else if let error = appState.error {
            errorView(error: error)
        } else {
            emptyStateView
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Claude Code Usage")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            ProgressView()
                .controlSize(.small)
                .opacity(appState.isLoading ? 1 : 0)
                .accessibilityLabel("Loading usage data")

            Button(action: {
                guard !isRefreshDisabled else { return }
                isRefreshDisabled = true
                Task {
                    await appState.refresh(reason: "manual_refresh")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .opacity(isRefreshDisabled ? 0.5 : 1.0)
            .help("Refresh usage data")
            .accessibilityLabel("Refresh")
            .accessibilityHint("Double tap to refresh usage data")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingLogs = true
                }
            }) {
                Image(systemName: "list.bullet.rectangle.portrait")
            }
            .buttonStyle(.plain)
            .help("View API logs")
            .accessibilityLabel("View Logs")
            .accessibilityHint("Double tap to view API logs")

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings = true
                }
            }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help("Open settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Double tap to open settings")

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Quit ClaudeMeter")
            .accessibilityLabel("Quit")
            .accessibilityHint("Double tap to quit ClaudeMeter")
        }
        .frame(height: 22)
    }

    // MARK: - Usage Content

    private func usageContentView(data: UsageData) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if data.fiveHour == nil && data.sevenDay == nil && data.sevenDayOpus == nil {
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

                if let fiveHour = data.fiveHour {
                    UsageCardView(
                        title: "5-Hour Limit",
                        usage: fiveHour.utilization,
                        resetsAt: fiveHour.resetsAt
                    )
                }

                if let sevenDay = data.sevenDay {
                    UsageCardView(
                        title: "7-Day Limit",
                        usage: sevenDay.utilization,
                        resetsAt: sevenDay.resetsAt
                    )
                }

                if appState.settings.showSonnetLimit, let sonnet = data.sevenDaySonnet {
                    UsageCardView(
                        title: "Sonnet Only",
                        usage: sonnet.utilization,
                        resetsAt: sonnet.resetsAt
                    )
                }

                if appState.settings.showDesignLimit, let design = data.sevenDayDesign {
                    UsageCardView(
                        title: "Claude Design",
                        usage: design.utilization,
                        resetsAt: design.resetsAt
                    )
                }

                if appState.settings.showExtraUsage, let extra = data.extraUsage, extra.isEnabled {
                    extraUsageCardView(extra: extra)
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
                    await appState.refresh(reason: "retry_button")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }
            .buttonStyle(.bordered)
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

            Text("Click refresh to load your Claude Code usage.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh") {
                guard !isRefreshDisabled else { return }
                isRefreshDisabled = true
                Task {
                    await appState.refresh(reason: "empty_state_refresh")
                    try? await Task.sleep(nanoseconds: UInt64(Constants.RateLimit.manualRefreshDebounce * 1_000_000_000))
                    isRefreshDisabled = false
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshDisabled)

            Spacer()
        }
        .padding()
    }

    // MARK: - Footer

    private var footerView: some View {
        // Re-render once per second so the relative "Updated … ago" text stays
        // live while the popover is open (and refreshes on reopen). Without this,
        // SwiftUI only re-invokes the body when `lastUpdateTime` changes — i.e.
        // once per poll — leaving the timestamp frozen at "just now" in between.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
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
                    Text("Updated \(lastUpdate.relativeDescription). Next update: \(timeString)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
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
                return "Updated \(lastUpdate.relativeDescription). Next update: \(timeString) (rate limit)"
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

// MARK: - Preview

#Preview {
    PopoverView(appState: AppState())
}
