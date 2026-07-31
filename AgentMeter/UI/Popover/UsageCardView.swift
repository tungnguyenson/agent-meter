//
//  UsageCardView.swift
//  AgentMeter
//
//  Copyright (c) 2026 puq.ai. All rights reserved.
//  Licensed under the MIT License. See LICENSE file.
//

import SwiftUI

struct UsageCardView: View {
    let title: String
    let usage: Double // Percentage 0-100
    let resetsAt: Date?
    /// Fixed length of this window (5h / 7d). When provided alongside `resetsAt`
    /// the card colours by a time-aware forecast instead of a static percentage.
    var windowDuration: TimeInterval? = nil

    private var forecast: WindowForecast? {
        guard let windowDuration else { return nil }
        return WindowForecast.make(utilization: usage, resetsAt: resetsAt, duration: windowDuration)
    }

    private var progressColor: Color {
        ColorTheme.color(for: forecast, fallbackUsage: usage)
    }

    private var isCritical: Bool {
        if let forecast { return forecast.status == .critical }
        return usage >= 90
    }

    private var usageLevel: String {
        switch usage {
        case 0..<50: return "low"
        case 50..<75: return "moderate"
        case 75..<90: return "high"
        default: return "critical"
        }
    }

    private var accessibilityDescription: String {
        var description = "\(title): \(Int(usage)) percent, \(usageLevel) usage"
        if let date = resetsAt {
            description += ". Resets in \(date.timeRemainingFormatted(style: .accessibilityFriendly))"
        }
        if let forecast, forecast.willExhaust, let eta = forecast.timeToExhaust {
            let etaText = Date(timeIntervalSinceNow: eta).timeRemainingFormatted(style: .medium)
            description += ". At the current pace, runs out in \(etaText)"
        }
        return description
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                AnimatedPercentage(value: usage, color: progressColor)
            }

            // Progress Ring and Details
            HStack(spacing: 16) {
                // Progress Ring with pulse effect for critical usage
                ProgressRingView(
                    progress: usage / 100.0,
                    color: progressColor,
                    lineWidth: 6,
                    size: 50
                )
                .glowEffect(isActive: isCritical, color: progressColor)

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    // Linear progress bar
                    ProgressBarView(
                        progress: usage / 100.0,
                        showPercentage: false,
                        height: 6,
                        color: progressColor
                    )
                    .frame(maxWidth: .infinity)

                    // Reset countdown
                    if let date = resetsAt {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption2)
                            Text("Resets: \(date.timeRemainingFormatted())")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }

                    // Pace warning: at the current rate the window runs out
                    // before it resets. This is the whole point of the
                    // time-aware colour — spell out how long is left.
                    if let forecast, forecast.willExhaust, let eta = forecast.timeToExhaust {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Runs out in \(Date(timeIntervalSinceNow: eta).timeRemainingFormatted())")
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(progressColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorTheme.cardBorder, lineWidth: 0.5)
        )
        .shadow(color: isCritical ? progressColor.opacity(0.3) : .clear, radius: isCritical ? 8 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue("\(Int(usage)) percent")
    }
}

// MARK: - Compact Card Variant

struct CompactUsageCardView: View {
    let title: String
    let usage: Double
    let resetsAt: Date?
    var windowDuration: TimeInterval? = nil

    private var forecast: WindowForecast? {
        guard let windowDuration else { return nil }
        return WindowForecast.make(utilization: usage, resetsAt: resetsAt, duration: windowDuration)
    }

    private var progressColor: Color {
        ColorTheme.color(for: forecast, fallbackUsage: usage)
    }

    var body: some View {
        HStack {
            // Progress circle
            CircularProgressBar(
                progress: usage / 100.0,
                lineWidth: 4,
                size: 36,
                showLabel: false,
                color: progressColor
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(Int(usage))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(progressColor)
                }

                if let date = resetsAt {
                    Text(date.timeRemainingFormatted())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ColorTheme.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        UsageCardView(
            title: "5-Hour Limit",
            usage: 45,
            resetsAt: Date().addingTimeInterval(3600),
            windowDuration: Constants.Window.fiveHourDuration
        )

        UsageCardView(
            title: "7-Day Limit",
            usage: 78,
            resetsAt: Date().addingTimeInterval(86400 * 3),
            windowDuration: Constants.Window.sevenDayDuration
        )

        UsageCardView(
            title: "Opus Limit",
            usage: 95,
            resetsAt: Date().addingTimeInterval(86400 * 5),
            windowDuration: Constants.Window.sevenDayDuration
        )

        Divider()

        CompactUsageCardView(
            title: "5-Hour",
            usage: 45,
            resetsAt: Date().addingTimeInterval(3600),
            windowDuration: Constants.Window.fiveHourDuration
        )
    }
    .padding()
    .frame(width: 320)
}
