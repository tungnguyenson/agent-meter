//
//  ProviderSummaryCard.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// One provider's row on the all-providers overview: identity, plan, health and
/// its pinned metrics. Tapping the card drills into that provider's detail;
/// the pin badge next to the name moves the menu bar to this provider without
/// navigating.
struct ProviderSummaryCard: View {
    let providerID: ProviderID
    let state: ProviderUsageState
    let metrics: [UsageMetric]
    let isMenuBarProvider: Bool
    let onSetMenuBarProvider: () -> Void
    let onOpenDetail: () -> Void

    @State private var isHovering = false

    private var hasMetrics: Bool {
        !metrics.isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                titleRow
                statusBody
            }
            Spacer(minLength: 4)
            trailingIndicators
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ColorTheme.cardBorder, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onOpenDetail)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(providerID.displayName), \(healthDescription)")
        .accessibilityHint("Open \(providerID.displayName) details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(providerID.iconAssetName)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)

            Text(providerID.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            menuBarPinBadge
        }
    }

    /// A quiet pin next to the name: filled and tinted only for the provider
    /// currently shown in the menu bar, an outline elsewhere. Tapping an
    /// outline pin switches the menu bar to that provider.
    private var menuBarPinBadge: some View {
        Button(action: onSetMenuBarProvider) {
            Image(systemName: isMenuBarProvider ? "pin.fill" : "pin")
                .font(.caption2)
                .foregroundColor(isMenuBarProvider ? ColorTheme.accent : .secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(isMenuBarProvider)
        .help(
            isMenuBarProvider
                ? "\(providerID.displayName) is shown in the menu bar"
                : "Show \(providerID.displayName) in the menu bar"
        )
        .accessibilityLabel(
            isMenuBarProvider
                ? "\(providerID.displayName) is shown in the menu bar"
                : "Show \(providerID.displayName) in the menu bar"
        )
    }

    // MARK: - Trailing Indicators

    /// Health status and the drill-in chevron, centred against the card's
    /// full height (including the metrics below) rather than pinned to the
    /// title row.
    private var trailingIndicators: some View {
        HStack(spacing: 6) {
            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: healthSymbol)
                    .font(.caption2)
                    .foregroundColor(healthColor)
                    .help(healthDescription)
            }

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Status Body

    /// A preserved snapshot outranks a fresh error: showing the last known
    /// numbers plus a warning line is more useful than replacing them with the
    /// error text, which is what `UsageCoordinator` keeps the snapshot for.
    @ViewBuilder
    private var statusBody: some View {
        if hasMetrics {
            VStack(alignment: .leading, spacing: 6) {
                metricsLayout
                if let message = staleWarningMessage {
                    inlineNotice(
                        symbol: "exclamationmark.triangle.fill",
                        message: message,
                        color: ColorTheme.orange
                    )
                }
            }
        } else if let error = state.error {
            inlineNotice(
                symbol: "exclamationmark.triangle.fill",
                message: error.localizedDescription,
                color: ColorTheme.orange
            )
        } else if state.isLoading {
            inlineNotice(
                symbol: "arrow.triangle.2.circlepath",
                message: "Loading usage…",
                color: .secondary
            )
        } else {
            inlineNotice(
                symbol: "circle.dotted",
                message: "No usage data yet",
                color: .secondary
            )
        }
    }

    /// Metrics as fixed-width columns, so a provider with one pinned metric
    /// (Codex) lines up ring-for-ring with one that has two (Claude, Cursor)
    /// instead of switching to a different, smaller row style.
    private var metricsLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(metrics) { metric in
                ProviderMetricRow(metric: metric)
            }
        }
    }

    private func inlineNotice(
        symbol: String,
        message: String,
        color: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
            Text(message)
                .font(.caption2)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundColor(color)
    }

    private var staleWarningMessage: String? {
        guard let error = state.error else { return nil }
        return "Last known values — \(error.localizedDescription)"
    }

    // MARK: - Health

    private var healthSymbol: String {
        if state.error != nil { return "exclamationmark.circle.fill" }
        if state.snapshot != nil { return "checkmark.circle.fill" }
        return "circle.dotted"
    }

    private var healthColor: Color {
        if state.error != nil { return ColorTheme.orange }
        if state.snapshot != nil { return ColorTheme.green }
        return .secondary
    }

    private var healthDescription: String {
        if let error = state.error {
            return "unavailable: \(error.localizedDescription)"
        }
        if state.snapshot != nil { return "connected" }
        return "not checked yet"
    }
}
