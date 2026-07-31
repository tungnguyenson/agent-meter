# Claude Code provider

This document describes the exact Agent Meter implementation as of
2026-07-29. This is not documentation of a public Anthropic API: the two
quota endpoints in use are private contracts that can change without notice.

## Quota scope

Claude counts usage limits across multiple surfaces sharing the same
account, not just Claude Code. Anthropic confirms that activity on Claude,
Claude Code, and other surfaces all counts toward the same usage limit;
quota depends on plan, model, and the length/complexity of the session.
Claude Code also has a `/usage` command to view the plan's rate-limit status.

Official sources:

- [Claude usage and length limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)
- [Use Claude Code with a Pro or Max plan](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- [Claude Code cheatsheet](https://support.claude.com/en/articles/14553413-claude-code-cheatsheet)

Because the quota is shared, the provider label in Agent Meter is **Claude
Code**, but the numbers are really the Claude account's quota.

## Current flow

### 1. Read Claude Code's OAuth credential

Agent Meter never performs login. On macOS it runs:

```text
/usr/bin/security find-generic-password -s "Claude Code-credentials" -w
```

The JSON payload is decoded against three shapes, in order:

1. `{ "claudeAiOauth": { ... } }`;
2. an OAuth object with no wrapper;
3. `ClaudeCredentials` directly.

Fields kept include access token, refresh token, expiry time, and
subscription type. `expiresAt` from the CLI payload is interpreted as Unix
milliseconds. The app only checks whether the access token is still valid;
it **never** uses the refresh token and never refreshes credentials itself.
Claude Code remains the owner of the login lifecycle.

Anthropic publicly states that Claude Code supports logging in with a Claude
subscription and stores credentials securely, but does not publish the
keychain service name or the payload schema above. See
[Claude Code getting started](https://code.claude.com/docs/en/getting-started).

### 2. Call the OAuth usage endpoint

Current request:

```http
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer [REDACTED_SECRET]
User-Agent: claude-code/<installed-cli-version>
anthropic-beta: oauth-2025-04-20
Accept: application/json
Content-Type: application/json
```

`ClaudeCodeVersionResolver` finds the version without depending on `PATH`:
native symlink, native version directory, auto-update result, then common
binary paths. If none is found, it falls back to a pinned version.

The response is decoded with ISO-8601 timestamps, with or without fractional
seconds. `utilization` values in the `(0, 1)` range are converted to a
percentage; other values are kept as-is. HTTP behavior:

| Status | Handling |
|---|---|
| `200` | Decode snapshot |
| `401` | Unauthorized |
| `429` | Rate-limited; read `Retry-After` from header, JSON, or text |
| `5xx` and other statuses | Server error |

### 3. Optional web fallback

If the OAuth request throws an `APIError`, the app tries a fallback when the
user has entered both an organization ID and `sessionKey`:

```http
GET https://claude.ai/api/organizations/<organization-id>/usage
Cookie: sessionKey=[REDACTED_SECRET]
```

If the response includes a new `Set-Cookie`, the app picks up the new
`sessionKey` and writes it back to settings. Both `401` and `403` are
treated as unauthorized. This is also a private web contract, not an API
Anthropic commits to for third-party clients.

## Capability audit

The labels below matter when generalizing: a field existing in the DTO does
not mean the user has ever seen that feature.

### Implemented and in use

| Capability | Runtime behavior |
|---|---|
| `five_hour` | Shown as a card; menu bar; forecast; polling; notification/reset |
| `seven_day` | Shown as a card; detailed menu bar; forecast; polling; notification/reset |
| `seven_day_sonnet` | Shown when the setting is enabled; polling; notification/reset |
| `seven_day_omelette` | Mapped to Claude Design; shown when the setting is enabled; notification/reset |
| `extra_usage` | Shows credit usage when enabled and the setting is on |
| OAuth error/cooldown | Cache fallback, auth gate, and persisted `429` cooldown |
| Offline cache | One Claude snapshot, 24-hour TTL |
| Web fallback | Opt-in; runs after any OAuth-path `APIError` |

`seven_day_opus` has no dedicated card but is used in adaptive polling,
notification, and reset detection. It is therefore **handled but only shown
indirectly**, not fully unused.

### Parsed but not wired into the product

| Field/model | Current status |
|---|---|
| `seven_day_oauth_apps` | Decoded and cached; no card, menu bar, polling, or notification |
| `seven_day_cowork` | Decoded and cached; no card, menu bar, polling, or notification |
| `TokenUsage` | Has a model and a sample component, not wired into fetch/runtime |
| `subscriptionType` | Decoded from credentials but not wired into app state or badge |
| `SubscriptionBadgeView` | Has a preview component, does not appear in the real popover |

### Claimed only, or unproven

- The README says "plan detection" for Free, Pro, Max, Max 5x, Team,
  Enterprise. The current runtime does not render a plan, and an unknown
  plan still falls back to Pro.
- The README says "token consumption in real-time". The current provider
  only fetches utilization quota; it does not collect a real-time token
  ledger.
- There is no public contract evidence for `/api/oauth/usage`,
  `/api/organizations/<id>/usage`, the keychain payload, or the beta header.
  These are proven only by this repo's implementation and tests.

## Stability and security

| Risk | Level | Decision |
|---|---|---|
| Private OAuth/web schema changes | High | Tolerant DTO, provider-local mapper, test fixtures, a failure doesn't break other providers |
| Reading a keychain item owned by another app | High | Read-only; never write/delete/refresh the token; never log the payload |
| Web session stored in UserDefaults | Critical, needs fixing | Migrate to an Agent Meter-owned Keychain, then delete the settings copy |
| Raw DEBUG response may contain account data | High | Redact or remove raw body logging before the multi-provider release |
| Hardcoded CLI fallback version | Medium | Keep the resolver dynamic; report a clear error if the endpoint rejects the version |

The web fallback must be labeled **Experimental** and off by default. The
app must never show an access token, refresh token, cookie, email, or
organization/account ID in logs, cache, fixtures, or documentation.

## Mapping to the shared model

Each window's data is mapped to a dynamic metric:

```text
providerID    = "claude-code"
metric.id     = stable raw field name per provider
usedPercent   = normalized utilization
resetsAt      = resets_at
windowDuration = known duration once semantics are confirmed
```

`extra_usage` maps to a value/limit metric and is not forced into a
rate-limit window when utilization is missing. Unknown fields must not fail
the whole snapshot; the provider can add mappings later once semantics are
confirmed.
