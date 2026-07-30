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

    var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        }
    }

    var symbolName: String {
        switch self {
        case .claudeCode: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow"
        }
    }

    /// Official brand mark, bundled as a template-rendered SVG in
    /// `Assets.xcassets` (sourced from Simple Icons, CC0) so provider rows show
    /// the real logo instead of a generic SF Symbol stand-in. Codex has no mark
    /// of its own on Simple Icons, so it borrows the OpenAI glyph.
    var iconAssetName: String {
        switch self {
        case .claudeCode: return "ProviderIcon-ClaudeCode"
        case .codex: return "ProviderIcon-Codex"
        case .cursor: return "ProviderIcon-Cursor"
        }
    }

    /// SF Symbol shown next to API Log entries to distinguish how the fetch
    /// was made — an HTTP call out to the provider's web API vs. a local
    /// JSON-RPC call to a CLI process. Purely a debug-UI hint.
    var debugTransportSymbol: String {
        switch self {
        case .claudeCode, .cursor: return "network"
        case .codex: return "terminal"
        }
    }

    /// Where the provider's own dashboard shows detailed usage — linked from
    /// the popover so the user can drill past what Agent Meter surfaces.
    var usageDashboardURL: URL {
        switch self {
        case .claudeCode: return URL(string: "https://claude.ai/settings/usage")!
        case .codex: return URL(string: "https://chatgpt.com/#settings/Usage")!
        case .cursor: return URL(string: "https://cursor.com/dashboard/spending")!
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

    /// Metrics for the compact surfaces — the menu bar title and the
    /// all-providers overview. The user's pins come first; any remaining
    /// percentage metrics backfill so a provider whose pins no longer exist in
    /// the response still shows something useful.
    func pinnedPercentageMetrics(
        pinnedIDs: [String],
        limit: Int = Constants.Overview.pinnedMetricLimit
    ) -> [UsageMetric] {
        let pinned = pinnedIDs
            .compactMap { metric(id: $0) }
            .filter { $0.usedPercent != nil }
        let backfill = percentageMetrics.filter { candidate in
            !pinned.contains { $0.id == candidate.id }
        }
        return Array((pinned + backfill).prefix(limit))
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
    /// The real network/IPC call `fetchSnapshot()` makes (e.g. "GET
    /// api.anthropic.com/api/oauth/usage"), surfaced in the debug API Logs so
    /// entries are distinguishable instead of every provider showing the same
    /// generic "fetchSnapshot" call name.
    var debugEndpoint: String { get }
    func configurationStatus() async -> ProviderConfigurationStatus
    func fetchSnapshot() async throws -> UsageSnapshot
    func shutdown() async
}

extension UsageProvider {
    var metadata: ProviderMetadata {
        ProviderMetadata(
            id: id,
            displayName: id.displayName,
            shortName: id.shortName,
            symbolName: id.symbolName
        )
    }

    var debugEndpoint: String {
        metadata.displayName
    }

    func configurationStatus() async -> ProviderConfigurationStatus {
        .ready
    }

    func shutdown() async {}
}
