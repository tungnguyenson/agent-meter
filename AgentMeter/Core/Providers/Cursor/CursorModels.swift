import Foundation

struct CursorUsageSummaryResponse: Decodable, Equatable {
    let billingCycleStart: Date?
    let billingCycleEnd: Date?
    let membershipType: String?
    let individualUsage: CursorIndividualUsage?
}

struct CursorIndividualUsage: Decodable, Equatable {
    let plan: CursorPlanUsage?
    let onDemand: CursorOnDemandUsage?
}

struct CursorPlanUsage: Decodable, Equatable {
    let enabled: Bool?
    let breakdown: CursorUsageBreakdown?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
    let totalPercentUsed: Double?
}

struct CursorUsageBreakdown: Decodable, Equatable {
    let included: Double?
    let bonus: Double?
    let total: Double?
}

struct CursorOnDemandUsage: Decodable, Equatable {
    let enabled: Bool
    let used: Double
    let limit: Double
}

enum CursorUsageMapper {
    static func map(
        _ response: CursorUsageSummaryResponse,
        fetchedAt: Date = Date()
    ) -> UsageSnapshot {
        UsageSnapshot(
            providerID: .cursor,
            accountLabel: nil,
            planLabel: response.membershipType,
            fetchedAt: fetchedAt,
            metrics: metrics(from: response)
        )
    }

    private static func metrics(from response: CursorUsageSummaryResponse) -> [UsageMetric] {
        planMetrics(from: response) + onDemandMetric(from: response)
    }

    private static func planMetrics(from response: CursorUsageSummaryResponse) -> [UsageMetric] {
        guard let plan = response.individualUsage?.plan else { return [] }
        let resetsAt = response.billingCycleEnd
        let duration = windowDuration(from: response)

        var result: [UsageMetric] = []
        if let autoPercent = plan.autoPercentUsed {
            result.append(UsageMetric(
                id: "cursor.plan.auto",
                title: "Cursor Models",
                shortLabel: "Cursor",
                category: .rateLimit,
                usedPercent: autoPercent,
                resetsAt: resetsAt,
                windowDuration: duration
            ))
        }
        if let apiPercent = plan.apiPercentUsed {
            result.append(UsageMetric(
                id: "cursor.plan.api",
                title: "Other Models",
                shortLabel: "Other",
                category: .rateLimit,
                usedPercent: apiPercent,
                resetsAt: resetsAt,
                windowDuration: duration
            ))
        }
        return result
    }

    /// `used`/`limit` are cents; converted to dollars so `UsageMetric.unit`
    /// ("USD") stays truthful across provider boundaries.
    private static func onDemandMetric(from response: CursorUsageSummaryResponse) -> [UsageMetric] {
        guard let onDemand = response.individualUsage?.onDemand, onDemand.enabled else {
            return []
        }
        let usedDollars = onDemand.used / 100
        let limitDollars = onDemand.limit / 100
        let percent = limitDollars > 0 ? (usedDollars / limitDollars) * 100 : nil
        return [
            UsageMetric(
                id: "cursor.on-demand",
                title: "On-Demand",
                shortLabel: "On-Demand",
                category: .credits,
                usedPercent: percent,
                usedValue: usedDollars,
                limitValue: limitDollars,
                unit: "USD"
            )
        ]
    }

    private static func windowDuration(from response: CursorUsageSummaryResponse) -> TimeInterval? {
        guard let start = response.billingCycleStart, let end = response.billingCycleEnd else {
            return nil
        }
        return end.timeIntervalSince(start)
    }
}
