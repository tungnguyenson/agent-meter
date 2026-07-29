import Foundation

struct CodexRateLimitsResponse: Decodable, Equatable {
    let rateLimits: CodexRateLimitSnapshot?
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    let rateLimitResetCredits: CodexRateLimitResetCredits?
}

struct CodexRateLimitResetCredits: Decodable, Equatable {
    let availableCount: Int
}

struct CodexRateLimitSnapshot: Decodable, Equatable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let credits: CodexCreditsSnapshot?
    let individualLimit: CodexSpendControlLimit?
    let spendControlReached: Bool?
    let planType: String?
    let rateLimitReachedType: String?
}

struct CodexRateLimitWindow: Decodable, Equatable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int?
}

struct CodexCreditsSnapshot: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?
}

struct CodexSpendControlLimit: Decodable, Equatable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: Int
}

struct CodexAccountResponse: Decodable, Equatable {
    let account: CodexAccount?
    let requiresOpenaiAuth: Bool
}

struct CodexAccount: Decodable, Equatable {
    let type: String
    let email: String?
    let planType: String?
}

struct CodexTokenUsageResponse: Decodable, Equatable {
    let summary: CodexTokenUsageSummary
    let dailyUsageBuckets: [CodexDailyUsageBucket]?
}

struct CodexTokenUsageSummary: Decodable, Equatable {
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let longestRunningTurnSec: Int?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
}

struct CodexDailyUsageBucket: Decodable, Equatable {
    let startDate: String
    let tokens: Int
}

enum CodexUsageMapper {
    static func map(
        _ rateLimits: CodexRateLimitsResponse,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        snapshot(rateLimits: rateLimits, fetchedAt: fetchedAt)
    }

    static func snapshot(
        rateLimits: CodexRateLimitsResponse,
        account: CodexAccount? = nil,
        tokenUsage: CodexTokenUsageResponse? = nil,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        var metrics = quotaMetrics(from: rateLimits)
        metrics += creditMetrics(from: rateLimits)
        let plan = account?.planType ?? primarySnapshot(from: rateLimits)?.planType

        return UsageSnapshot(
            providerID: .codex,
            accountLabel: nil,
            planLabel: plan,
            fetchedAt: fetchedAt,
            metrics: metrics
        )
    }

    private static func quotaMetrics(from response: CodexRateLimitsResponse) -> [UsageMetric] {
        selectedBuckets(from: response).flatMap { key, snapshot in
            [
                windowMetric(bucketKey: key, snapshot: snapshot, kind: "primary", window: snapshot.primary),
                windowMetric(bucketKey: key, snapshot: snapshot, kind: "secondary", window: snapshot.secondary),
                spendMetric(bucketKey: key, snapshot: snapshot)
            ].compactMap { $0 }
        }
    }

    private static func selectedBuckets(from response: CodexRateLimitsResponse) -> [(String, CodexRateLimitSnapshot)] {
        if let buckets = response.rateLimitsByLimitId, !buckets.isEmpty {
            return buckets.sorted { $0.key < $1.key }
        }
        guard let legacy = response.rateLimits else { return [] }
        return [("default", legacy)]
    }

    private static func primarySnapshot(from response: CodexRateLimitsResponse) -> CodexRateLimitSnapshot? {
        selectedBuckets(from: response).first?.1 ?? response.rateLimits
    }

    private static func windowMetric(
        bucketKey: String,
        snapshot: CodexRateLimitSnapshot,
        kind: String,
        window: CodexRateLimitWindow?
    ) -> UsageMetric? {
        guard let window else { return nil }
        let bucketName = snapshot.limitName ?? snapshot.limitId ?? bucketKey
        let duration = window.windowDurationMins.map { TimeInterval($0 * 60) }
        return UsageMetric(
            id: "codex.\(bucketKey).\(kind)",
            title: windowTitle(bucketName: bucketName, kind: kind, duration: duration),
            shortLabel: shortLabel(kind: kind, duration: duration),
            category: .rateLimit,
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowDuration: duration
        )
    }

    private static func windowTitle(bucketName: String, kind: String, duration: TimeInterval?) -> String {
        let windowLabel = duration.map(formatDuration) ?? kind.capitalized
        return "\(bucketName) · \(windowLabel)"
    }

    private static func shortLabel(kind: String, duration: TimeInterval?) -> String {
        duration.map(formatDuration) ?? kind.prefix(1).uppercased()
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes % 10_080 == 0 { return "\(minutes / 10_080)w" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func spendMetric(bucketKey: String, snapshot: CodexRateLimitSnapshot) -> UsageMetric? {
        guard let spend = snapshot.individualLimit else { return nil }
        return UsageMetric(
            id: "codex.\(bucketKey).spend",
            title: "Monthly Spend",
            shortLabel: "Spend",
            category: .credits,
            usedPercent: Double(100 - spend.remainingPercent),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(spend.resetsAt)),
            usedValue: Double(spend.used),
            limitValue: Double(spend.limit),
            unit: "credits"
        )
    }

    private static func creditMetrics(from response: CodexRateLimitsResponse) -> [UsageMetric] {
        guard let credits = primarySnapshot(from: response)?.credits else { return [] }
        let value = credits.unlimited ? nil : credits.balance.flatMap(Double.init)
        return [
            UsageMetric(
                id: "credits",
                title: "Credits balance",
                shortLabel: "Credits",
                category: .credits,
                usedValue: value,
                unit: "credits"
            )
        ]
    }

}
