//
//  ProviderMetricRow.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

/// One metric inside a provider summary card on the all-providers overview: a
/// ring above its label and percentage/countdown, sized as a fixed-width
/// column so a provider with one pinned metric lines up with one that has
/// two — same ring size, same left edge, regardless of count.
struct ProviderMetricRow: View {
    let metric: UsageMetric

    private var usage: Double {
        metric.usedPercent ?? 0
    }

    private var forecast: WindowForecast? {
        guard let windowDuration = metric.windowDuration else { return nil }
        return WindowForecast.make(
            utilization: usage,
            resetsAt: metric.resetsAt,
            duration: windowDuration
        )
    }

    private var progressColor: Color {
        ColorTheme.color(for: forecast, fallbackUsage: usage)
    }

    private var accessibilityDescription: String {
        var description = "\(metric.title): \(Int(usage)) percent"
        if let resetsAt = metric.resetsAt {
            description += ", resets in \(resetsAt.timeRemainingFormatted(style: .accessibilityFriendly))"
        }
        return description
    }

    var body: some View {
        VStack(spacing: 4) {
            CircularProgressBar(
                progress: min(max(usage / 100, 0), 1),
                lineWidth: Constants.Overview.metricRingLineWidth,
                size: Constants.Overview.metricRingSize,
                showLabel: false,
                color: progressColor
            )

            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(metric.title)

            HStack(spacing: 6) {
                Text("\(Int(usage))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundColor(progressColor)

                if let resetsAt = metric.resetsAt {
                    Text(resetsAt.timeRemainingFormatted())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(width: Constants.Overview.metricColumnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue("\(Int(usage)) percent")
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 12) {
        ProviderMetricRow(
            metric: UsageMetric(
                id: "claude.five-hour",
                title: "5-Hour Limit",
                shortLabel: "5h",
                category: .rateLimit,
                usedPercent: 47,
                resetsAt: Date().addingTimeInterval(2 * 3600),
                windowDuration: Constants.Window.fiveHourDuration
            )
        )
        ProviderMetricRow(
            metric: UsageMetric(
                id: "claude.seven-day",
                title: "7-Day Limit",
                shortLabel: "7d",
                category: .rateLimit,
                usedPercent: 94,
                resetsAt: Date().addingTimeInterval(4 * 86400),
                windowDuration: Constants.Window.sevenDayDuration
            )
        )
    }
    .padding()
    .frame(width: 320)
}
