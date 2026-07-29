import Foundation

enum ProviderID: String, Codable, CaseIterable, Hashable, Identifiable {
    case claudeCode = "claude-code"
    case codex

    var id: String { rawValue }
}

struct ProviderMetadata: Equatable {
    let id: ProviderID
    let displayName: String
    let shortName: String
    let symbolName: String
}

enum UsageMetricCategory: String, Codable {
    case rateLimit
    case model
    case credits
    case activity
}

struct UsageMetric: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let shortLabel: String
    let category: UsageMetricCategory
    let usedPercent: Double?
    let resetsAt: Date?
    let windowDuration: TimeInterval?
    let usedValue: Double?
    let limitValue: Double?
    let unit: String?

    init(
        id: String,
        title: String,
        shortLabel: String,
        category: UsageMetricCategory,
        usedPercent: Double? = nil,
        resetsAt: Date? = nil,
        windowDuration: TimeInterval? = nil,
        usedValue: Double? = nil,
        limitValue: Double? = nil,
        unit: String? = nil
    ) {
        self.id = id
        self.title = title
        self.shortLabel = shortLabel
        self.category = category
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDuration = windowDuration
        self.usedValue = usedValue
        self.limitValue = limitValue
        self.unit = unit
    }
}

struct UsageSnapshot: Codable, Equatable {
    let providerID: ProviderID
    let accountLabel: String?
    let planLabel: String?
    let fetchedAt: Date
    let metrics: [UsageMetric]

    init(
        providerID: ProviderID,
        accountLabel: String? = nil,
        planLabel: String? = nil,
        fetchedAt: Date,
        metrics: [UsageMetric]
    ) {
        self.providerID = providerID
        self.accountLabel = accountLabel
        self.planLabel = planLabel
        self.fetchedAt = fetchedAt
        self.metrics = metrics
    }

    var percentageMetrics: [UsageMetric] {
        metrics.filter { $0.usedPercent != nil }
    }

    func metric(id: String) -> UsageMetric? {
        metrics.first { $0.id == id }
    }
}

enum ProviderConfigurationStatus: Equatable {
    case ready
    case unavailable(String)
    case authenticationRequired(String)
}

protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var metadata: ProviderMetadata { get }
    func configurationStatus() async -> ProviderConfigurationStatus
    func fetchSnapshot() async throws -> UsageSnapshot
    func shutdown() async
}

extension UsageProvider {
    var metadata: ProviderMetadata {
        ProviderMetadata(
            id: id,
            displayName: id == .claudeCode ? "Claude Code" : "Codex",
            shortName: id == .claudeCode ? "Claude" : "Codex",
            symbolName: id == .claudeCode ? "sparkles" : "chevron.left.forwardslash.chevron.right"
        )
    }

    func configurationStatus() async -> ProviderConfigurationStatus {
        .ready
    }

    func shutdown() async {}
}
