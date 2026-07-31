# Agent Meter multi-provider spec

## Goal

Agent Meter is a macOS menu-bar app that tracks subscription quota across
multiple coding agents. v1 extends the previous version into Agent Meter,
preserving all existing Claude behavior and adding Codex via the local
app-server.

Success means a user can enable both providers, switch providers in the
popover, view quota/reset/health, pin up to two metrics to the menu bar, and
have a failure in one provider not affect the other.

## Domain model

```swift
struct ProviderID: RawRepresentable, Hashable, Codable

struct ProviderMetadata {
    let id: ProviderID
    let displayName: String
    let iconName: String
}

struct UsageSnapshot {
    let providerID: ProviderID
    let accountLabel: String?
    let planLabel: String?
    let fetchedAt: Date
    let metrics: [UsageMetric]
}

struct UsageMetric {
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
}

protocol UsageProvider {
    var metadata: ProviderMetadata { get }
    func configurationStatus() async -> ProviderConfigurationStatus
    func fetchSnapshot() async throws -> UsageSnapshot
}
```

Model requirements:

- `ProviderID` and metric IDs are stable strings, namespaced by provider when
  stored.
- There is no shared subscription-plan enum; an unknown plan keeps its raw
  label.
- Both percentage and value/limit metrics are optional, since provider
  capabilities differ.
- Forecast only runs when percentage, reset, and window duration are all
  valid.
- The mapper clamps the presentation value to `0...100` but keeps a redacted
  raw diagnostic to catch upstream drift; it must not silently turn `0.5`
  into `50%` if the provider contract says that value is already a percent.

## Provider behavior

### Claude Code

- Isolate the credential reader, OAuth client, experimental web client, and
  DTO mapper.
- Keep the current OAuth-first flow, cache fallback, and rate-limit cooldown.
- Map every known field to a metric; an unknown field must not fail the
  whole snapshot.
- Migrate the web session secret to an Agent Meter-owned Keychain.
- Keep Claude-specific settings for Sonnet, Design, and Extra Usage via
  metric visibility instead of hard-coded booleans in global settings.

### Codex

- Resolve the binary; minimum tested version `0.146.0`.
- One long-lived `codex app-server` subprocess; stdio is the default
  transport.
- Handshake before any account method call.
- Fetch `account/read`, `account/rateLimits/read`, and best-effort
  `account/usage/read`.
- Merge sparse rate-limit notifications, or refetch when uncertain.
- No reading of auth files, no direct HTTP, no write/action account methods.
- API key, Bedrock, and OSS/local mode show "Subscription quota unavailable".

## Coordinator and state

The coordinator keeps state keyed by `ProviderID`:

```text
disabled | unavailable | loading | ready | stale | error
```

Each provider has its own snapshot, error, last success, active fetch, auth
gate, rate-limit cooldown, and retry/backoff. Refresh-all runs in parallel.
Partial success is published immediately; a failed refresh does not clear the
previous snapshot.

The selected provider only controls the popover/menu bar; it does not stop
other providers from polling. When the app is in the background, cadence may
slow down but stays independent per provider. Notification key:

```text
<provider-id>:<metric-id>:<threshold>
```

to avoid collisions across providers/windows.

## UX

### Popover

- Header "Agent Meter".
- Provider picker shows icon, name, health dot, and last-updated state.
- Content is a dynamic list of metric cards for the selected provider.
- Percentage windows show usage, reset countdown, and forecast.
- Value/limit metrics show the number, unit, and progress if computable.
- Stale snapshots still display with a timestamp; errors don't hide old data.
- Empty/unsupported/auth states have their own copy, not merged into a
  generic "not logged in".

### Menu bar

Keep the three modes Icon, Compact, and Detailed. The menu bar uses the
selected provider and up to two pinned metrics:

- if the pinned metrics still exist, render them in the configured order;
- if a metric disappears, fall back to the first two percentage metrics;
- if there are no metrics, show the provider icon and a `--` state;
- countdown uses window duration/reset from the metric, not hard-coded per
  provider.

### Settings

Global: launch at login, Dock, appearance, polling, notifications, and
custom colors.

Provider section: enabled, binary/path or experimental configuration, metric
visibility, and pinning. Secret fields do not round-trip through
`AppSettings`.

## Persistence and migration

Settings/cache schema bumps to v2:

```text
enabledProviderIDs
selectedProviderID
metricVisibility[providerID][metricID]
pinnedMetricIDs[providerID]       // max 2
provider cache[providerID]
```

One-time migration from the previous version:

1. Import display mode/style, color scheme, Dock/login, polling,
   notification, and custom color settings.
2. Enable the Claude provider and select it if nothing is selected yet.
3. Map the Sonnet/Design/Extra Usage toggles to metric visibility.
4. Import the Claude v1 cache if it decodes successfully; a migration failure
   must not crash launch.
5. Write `webSessionKey` into the Agent Meter-owned Keychain, confirm the
   write succeeded, then remove the secret from settings/UserDefaults.
6. Do not copy Claude Code's OAuth token or refresh token.

Migration is idempotent and only writes the new version after all required
steps complete.

## Error and security requirements

- User-facing errors distinguish: binary missing, unsupported version, not
  signed in, quota unavailable for the auth mode, rate-limited, network,
  protocol, decode.
- Diagnostics include provider/method/request ID but redact secrets, email,
  account ID, cookies, headers, and any raw response containing PII.
- Cache files contain no credentials; sensitive Keychain items are readable
  only by this app.
- The subprocess path must be a resolved executable file; never build a
  shell command from user input.
- No `sh -c`; pass the executable URL and argv directly.
- The app never performs login/logout, purchases, email nudges, or credit
  redemption.

## Acceptance criteria

1. Existing Claude UI/menu bar/notification/cache behavior has no
   regression.
2. A ChatGPT-authenticated Codex account returns a quota card with percent,
   duration, and reset via app-server.
3. With Claude and Codex both enabled, a failure in one still lets the other
   poll/refresh/display.
4. Restarting the app restores per-provider cache and cooldown with correct
   namespacing.
5. Unknown plan/metric/notification values do not crash and are not silently
   defaulted to the wrong value.
6. No Claude web secret remains in UserDefaults, logs, or cache.
7. No direct OpenAI private endpoint calls and no reading of
   `~/.codex/auth.json`.
8. Unit, integration, and critical UI flow tests pass; coverage is at least
   80%.
