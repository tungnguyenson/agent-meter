# Cursor provider

This document records field investigation results from 2026-07-30 on a dev
machine (`nstung@gmail.com`, Cursor Pro, `cursor-agent` CLI logged in). This
is **not** documentation of Cursor's public API: every endpoint described
below is a private contract used by the `cursor.com` web dashboard, inferred
by probing directly, and not found in official docs. No code implements this
provider yet; this document is input for that work.

## Feasibility conclusion

Personal usage data can be fetched, complete and matching the Spending page
UI 1:1 (`cursor.com/dashboard` → Spending). But this is an **internal API
with no stable contract**, a risk equal to or higher than the Claude Code web
fallback.

Per [cursor.com/docs/api](https://cursor.com/docs/api), the official
usage/spend API (Admin API, Analytics API, specifically `api.cursor.com/teams/*`
and `api.cursor.com/analytics`) is only available for **Enterprise/Team**,
authenticated with Basic Auth using a dedicated API key. Personal accounts
**have no official usage API**. The Cloud Agents API is open to every plan
but does not expose usage/spend.

## Credentials

Cursor Desktop/CLI stores an access token + refresh token in the macOS
Keychain:

```text
security find-generic-password -s cursor-access-token -a cursor-user -w
security find-generic-password -s cursor-refresh-token -a cursor-user -w
```

The token is a JWT issued by WorkOS:

```json
{
  "sub": "google-oauth2|user_01JNRDXH3VAJ20W3XQW2NX8AD4",
  "iss": "https://authentication.cursor.sh",
  "aud": "https://cursor.com",
  "scope": "openid profile email offline_access",
  "type": "session",
  "iat": 1781787980,
  "exp": 1786971980
}
```

Observed lifecycle: reissued roughly every ~60 days (test case: issued →
expires = exactly 60.0 days). A refresh token is included so refreshing is
possible, but the specific refresh flow hasn't been verified yet.

**Important trap**: the correct userId for API calls is the JWT's `sub`
claim (`google-oauth2|user_...`), **not** the integer `authInfo.userId`
stored in `~/.cursor/cli-config.json`. Using that integer by mistake, the
`/api/usage` call still returns `200` but with every field `0`: a silent
failure with no clear error to catch.

## Auth header

```http
Cookie: WorkosCursorSessionToken=<sub URL-encoded>::<jwt>
```

A Bearer token (`Authorization: Bearer <jwt>`) **does not work** against
`cursor.com` (returns `401 not_authenticated`), but does work against
`api2.cursor.sh` (the legacy backend used by the desktop app/CLI).

Every `POST` request to `cursor.com/api/dashboard/*` requires:

```http
Origin: https://cursor.com
```

Without this header, the response is `403 {"error":"Invalid origin for
state-changing request"}` even with a valid cookie.

## Verified endpoints

### `GET /api/usage-summary` (main endpoint, used for the menu bar)

```json
{
  "billingCycleStart": "2026-07-18T10:44:30.000Z",
  "billingCycleEnd": "2026-08-18T10:44:30.000Z",
  "membershipType": "pro",
  "limitType": "user",
  "isUnlimited": false,
  "individualUsage": {
    "plan": {
      "enabled": true,
      "used": 2000,
      "limit": 2000,
      "remaining": 0,
      "breakdown": { "included": 2000, "bonus": 32047, "total": 34047 },
      "autoPercentUsed": 100,
      "apiPercentUsed": 88.888888888888,
      "totalPercentUsed": 98.686956521739
    },
    "onDemand": { "enabled": true, "used": 0, "limit": 500, "remaining": 500 }
  }
}
```

Cross-checked directly against the Spending page UI, matching every number:

| UI Spending | Field | Test value |
|---|---|---|
| "Cursor Models, 100% used" | `plan.autoPercentUsed` | `100` |
| "Other Models, 89% used" | `plan.apiPercentUsed` | `88.89` → rounds to 89 |
| "plan includes at least $20 of API usage" | `plan.breakdown.included` | `2000` |
| "On-Demand: $0.00 / $5" | `onDemand.used` / `onDemand.limit` | `0` / `500` |

**Unit: cents.** `500` = $5.00, `2000` = $20.00. The `used`/`limit`/`remaining`
fields at the top level of `plan` are the total amount spent from the
included quota, **not** a limit — the field names are misleading.

`breakdown` is a breakdown of what's already **been spent** in the cycle,
not a limit:

```text
breakdown.included = spent from the plan's included quota (2000 = $20, matches the Pro price exactly)
breakdown.bonus     = spent from bonus/credit outside the included amount
breakdown.total     = included + bonus
```

Cross-verified: calling `get-aggregated-usage-events` for the exact window
`billingCycleStart → now` gives `totalCostCents = 34046.91`, matching
`breakdown.total = 34047` with a 0.09-cent difference from rounding. This
implies a hidden total limit of `34047 / 0.98687 ≈ 34500` cents = $345, but
this number **is not present in the payload** — it has to be inferred.
Don't hard-code it; only show the percent that's actually available.

**`autoModelSelectedDisplayMessage`/`namedModelSelectedDisplayMessage`**
(strings like "You've used 99% of..."): this is display copy shown in the
editor's model picker, and it **does not exactly match the number on the
Spending page** (99% vs. a progress bar showing 100% due to different
rounding). Don't use this string to render UI — use the numbers only.

### `POST /api/dashboard/get-hard-limit`

```json
{ "hardLimit": 5 }
```

**Unit: dollars**, not cents — a different unit than `usage-summary`.
Matches "Monthly Limit: Fixed, 5" on the On-Demand UI. Trap: adding this
field directly to a cents value from another endpoint will be off by a
factor of 100.

### `GET /api/auth/me`

```json
{
  "email": "nstung@gmail.com",
  "sub": "user_01JNRDXH3VAJ20W3XQW2NX8AD4",
  "id": 167714721
}
```

Used to get display info; the `id` here is exactly the integer
`authInfo.userId` in `cli-config.json`, confirming that number is **not**
the value needed for the `?user=` query param on `/api/usage` (an old
endpoint, see "Not used" below).

### `GET /api/auth/stripe` (or `api2.cursor.sh/auth/full_stripe_profile` with Bearer)

```json
{
  "membershipType": "pro",
  "subscriptionStatus": "active",
  "individualMembershipType": "pro",
  "isTeamMember": false,
  "pendingCancellationDate": "2026-08-18T10:44:30.000Z",
  "isYearlyPlan": false
}
```

Used for plan label/badge, similar to `subscriptionType` in Claude Code.

### `POST /api/dashboard/get-aggregated-usage-events` (optional, detail panel)

Params: `{"teamId":0,"startDate":"<ms>","endDate":"<ms>"}` (epoch
milliseconds as a **string**, not a number).

```json
{
  "aggregations": [
    {
      "modelIntent": "cursor-grok-4.5-high-fast",
      "inputTokens": "31544002",
      "outputTokens": "4211773",
      "cacheReadTokens": "461610432",
      "totalCents": 41535.384075,
      "tier": 2
    }
  ],
  "totalInputTokens": "36880431",
  "totalOutputTokens": "6025594",
  "totalCacheReadTokens": "724476908",
  "totalCostCents": 52892.241682
}
```

Token count fields are **strings**, not numbers — decoding must be
tolerant. Per-model `totalCents` is a `Double`. Useful for a per-model
breakdown if a detail panel is built later; not needed for the menu bar
summary.

### `POST /api/dashboard/get-filtered-usage-events` (optional, per-request log)

Params: `{"teamId":0,"page":1,"pageSize":N}`. Returns
`totalUsageEventsCount` and an array of events with `timestamp` (ms
string), `model`, `tokenUsage`, `chargedCents`, `conversationId`. Not
needed for v1.

## Endpoints not used

`GET /api/usage?user=<id>`: legacy premium-request endpoint (pre
token-based pricing), always returns `gpt-4: {numRequests: 0, numTokens: 0}`
regardless of a correct or incorrect userId, since pricing has moved to
token-based. Don't use it.

`POST /api/dashboard/get-user-hard-limit`, `get-current-usage-limit`: return
the Next.js app-shell HTML instead of JSON, meaning the route either
doesn't exist as an API or requires different, unidentified parameters. Do
not use until re-verified.

`api.cursor.com/teams/*`: 404/405 when called without a Basic Auth team API
key, matching the docs — not applicable to personal accounts.

## Local data that isn't sufficient

`~/.cursor/ai-tracking/ai-code-tracking.db` (SQLite) only contains
AI-code-authorship data per commit (`scored_commits`: lines added/deleted,
% AI per commit), with no token/request/quota data.
`~/.cursor/cli-config.json` has `authInfo.email`, `authInfo.displayName`,
`serverConfigCache.backendUrl` (`https://api2.cursor.sh`), which can be used
to show the account label without a network call, but **do not use
`authInfo.userId`** (see the JWT `sub` trap above). No local file can
replace calling the API for usage data.

## Stability and risk

| Risk | Level | Suggested handling |
|---|---|---|
| No public contract; endpoints can change anytime | High | Tolerant DTO decode, provider-local mapper, a failure doesn't break other providers, following the existing `ClaudeUsageMapper`/`CodexUsageMapper` pattern |
| Two different currency units between `usage-summary` (cents) and `get-hard-limit` (dollars) | High if implemented wrong | Name fields with the unit explicit right at the mapper; never pass a raw float across the boundary unlabeled |
| Wrong `userId` (using `authInfo.userId` instead of JWT `sub`) fails silently, returns `200` with all-zero data | High | Always decode `sub` from the JWT in the provider; never read `cli-config.json` for this |
| JWT expires ~60 days, refresh flow unverified | Medium | v1 treats expiry as `authenticationRequired`; don't auto-refresh until the refresh flow is verified separately |
| Token counts are strings in JSON, not numbers | Low | Tolerant decode with something like `LosslessStringConvertible`, as Codex already does for numeric fields |
| Reading a Keychain item owned by Cursor (not created by this app) | High, same as Claude Code | Read-only; never write/delete/refresh Cursor's token; never log the payload |

## Proposed mapping to the shared model (not yet implemented)

Following the same `UsageSnapshot`/`UsageMetric` pattern used for Claude
Code and Codex:

```text
providerID     = .cursor (needs a new case added to ProviderID)
metric cents   → auto/api/on-demand should all be normalized to usedValue
                 in dollars before entering UsageMetric (unit: "USD"), to
                 avoid leaking the cents unit into the UI layer
usedPercent    = plan.autoPercentUsed / plan.apiPercentUsed / on-demand
                 computed from used/limit (no ready-made percent field for
                 on-demand)
resetsAt       = billingCycleEnd
windowDuration = billingCycleEnd - billingCycleStart
```

`onDemand` has no ready-made percent field in the payload. If a percent is
shown, it must be computed from `used/limit` and clearly marked as derived,
not a raw field from Cursor.

## Not yet done

- `CursorProvider` (conforming to `UsageProvider`) is not implemented,
  `ProviderID.cursor` is not added, there is no mapper, and no test
  fixture.
- The JWT refresh flow hasn't been verified when the access token expires.
- It's not yet determined why `get-user-hard-limit`/`get-current-usage-limit`
  return HTML instead of JSON; a different header or method may be needed.
- The UX for a user who hasn't installed Cursor or isn't logged in hasn't
  been decided yet (similar to Codex/Claude's `configurationStatus()`).
