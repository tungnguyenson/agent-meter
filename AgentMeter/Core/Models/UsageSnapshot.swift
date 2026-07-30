import Foundation

enum ProviderID: String, Codable, CaseIterable, Hashable, Identifiable {
    case claudeCode = "claude-code"
    case codex
    case cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }
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
        switch id {
        case .claudeCode:
            return ProviderMetadata(
                id: id,
                displayName: id.displayName,
                shortName: "Claude",
                symbolName: "sparkles"
            )
        case .codex:
            return ProviderMetadata(
                id: id,
                displayName: id.displayName,
                shortName: "Codex",
                symbolName: "chevron.left.forwardslash.chevron.right"
            )
        case .cursor:
            return ProviderMetadata(
                id: id,
                displayName: id.displayName,
                shortName: "Cursor",
                symbolName: "cursorarrow"
            )
        }
    }

    func configurationStatus() async -> ProviderConfigurationStatus {
        .ready
    }

    func shutdown() async {}
}
