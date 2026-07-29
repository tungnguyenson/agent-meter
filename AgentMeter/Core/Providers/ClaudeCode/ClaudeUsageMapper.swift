import Foundation

enum ClaudeUsageMapper {
    static func map(_ data: UsageData, planLabel: String? = nil) -> UsageSnapshot {
        snapshot(from: data, planLabel: planLabel)
    }

    static func snapshot(from data: UsageData, planLabel: String? = nil) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .claudeCode,
            accountLabel: nil,
            planLabel: planLabel,
            fetchedAt: data.fetchedAt,
            metrics: metrics(from: data)
        )
    }

    private static func metrics(from data: UsageData) -> [UsageMetric] {
        [
            metric(id: "claude.five-hour", title: "5-Hour Limit", shortLabel: "5h", category: .rateLimit, window: data.fiveHour, duration: 5 * 3600),
            metric(id: "claude.seven-day", title: "7-Day Limit", shortLabel: "7d", category: .rateLimit, window: data.sevenDay, duration: 7 * 86400),
            metric(id: "claude.seven-day-opus", title: "Opus", shortLabel: "Opus", category: .model, window: data.sevenDayOpus, duration: 7 * 86400),
            metric(id: "claude.seven-day-sonnet", title: "Sonnet", shortLabel: "Sonnet", category: .model, window: data.sevenDaySonnet, duration: 7 * 86400),
            metric(id: "claude.seven-day-oauth-apps", title: "OAuth Apps", shortLabel: "Apps", category: .rateLimit, window: data.sevenDayOauthApps, duration: 7 * 86400),
            metric(id: "claude.seven-day-cowork", title: "Cowork", shortLabel: "Cowork", category: .rateLimit, window: data.sevenDayCowork, duration: 7 * 86400),
            metric(id: "claude.seven-day-design", title: "Claude Design", shortLabel: "Design", category: .rateLimit, window: data.sevenDayDesign, duration: 7 * 86400)
        ].compactMap { $0 } + extraUsageMetric(from: data.extraUsage)
    }

    private static func metric(
        id: String,
        title: String,
        shortLabel: String,
        category: UsageMetricCategory,
        window: UsageWindow?,
        duration: TimeInterval
    ) -> UsageMetric? {
        guard let window else { return nil }
        return UsageMetric(
            id: id,
            title: title,
            shortLabel: shortLabel,
            category: category,
            usedPercent: window.utilization,
            resetsAt: window.resetsAt,
            windowDuration: duration
        )
    }

    private static func extraUsageMetric(from extraUsage: ExtraUsage?) -> [UsageMetric] {
        guard let extraUsage, extraUsage.isEnabled else { return [] }
        return [
            UsageMetric(
                id: "claude.extra-usage",
                title: "Extra Usage",
                shortLabel: "Extra",
                category: .credits,
                usedPercent: extraUsage.utilization,
                usedValue: extraUsage.usedCredits,
                limitValue: extraUsage.monthlyLimit,
                unit: "USD"
            )
        ]
    }

}
