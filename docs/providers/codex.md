# Codex provider

## Integration verdict

Codex supports a feasible quota integration through `codex app-server`. This
is the local interface OpenAI uses to build rich clients like the VS Code
extension. The app-server exchanges bidirectional JSON-RPC over JSONL on
stdio and publishes the account methods Agent Meter needs.

Primary sources:

- [OpenAI Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Codex app-server protocol types](https://github.com/openai/codex/tree/main/codex-rs/app-server-protocol/src/protocol)

A local assessment on 2026-07-29 confirmed `codex-cli 0.146.0` has
`codex app-server`, stdio is the default transport, and the CLI still labels
this command `experimental`. This is therefore an **official local contract
with medium stability risk**, not a public HTTP API with independent
versioning.

## Security boundary

Agent Meter runs the Codex binary the user already installed and
communicates with it as a subprocess:

```text
Agent Meter ⇄ stdin/stdout JSONL ⇄ codex app-server ⇄ OpenAI
```

Agent Meter does not:

- read or parse `~/.codex/auth.json`;
- copy the OAuth/API key into settings, logs, or cache;
- call OpenAI's private backend endpoint directly;
- initiate login, logout, or account switching;
- call `account/rateLimitResetCredit/consume`;
- send email nudges or perform any action that changes the account.

Codex owns credential storage, token refresh, and backend authentication.
Agent Meter only uses read methods.

## Process lifecycle

1. Resolve the binary from the user-configured path, `PATH`, then common
   Homebrew/NVM install locations.
2. Run `codex app-server`; stdio is the default transport.
3. Send `initialize`, wait for a successful response, then send the
   `initialized` notification.
4. Keep one long-lived subprocess per provider; use a monotonically
   increasing request ID to match responses to pending requests.
5. Read each stdout line as one JSON message. Stderr is used only for
   redacted diagnostics, never mixed into the protocol parser.
6. When the process exits or the protocol breaks, fail pending requests,
   keep the cached snapshot, and restart with bounded exponential backoff.

Every request must have a timeout. Unknown notifications or fields must be
safely ignored so the app-server can evolve without crashing the client.

## Read methods

### `account/read`

```json
{"method":"account/read","id":1,"params":{"refreshToken":false}}
```

Used to determine:

- whether an account exists;
- whether Codex requires OpenAI auth;
- the auth mode;
- the plan type when the backend provides it.

Agent Meter sets `refreshToken: false`: a quota viewer should not proactively
change auth state. `account/updated` invalidates the provider and triggers a
refetch.

The auth modes published by the protocol include ChatGPT managed, API key,
personal access token, and Amazon Bedrock (experimental). Subscription quota
only makes sense when the app-server returns ChatGPT rate limits. API-key-only,
Bedrock, or local/OSS mode must show "Subscription quota unavailable" rather
than a fake login error.

### `account/rateLimits/read`

```json
{"method":"account/rateLimits/read","id":2}
```

The response may contain:

- `rateLimits` for backward compatibility;
- multiple limits under `rateLimitsByLimitId`;
- `primary` and `secondary` windows;
- `usedPercent`, `windowDurationMins`, `resetsAt` in Unix seconds;
- plan/limit identifiers;
- credit balance or effective monthly limit when available;
- `spendControlReached`;
- an earned reset-credit snapshot.

Mapping:

```text
usedPercent         → UsageMetric.usedPercent
windowDurationMins  → UsageMetric.windowDuration
resetsAt            → UsageMetric.resetsAt
limit id + window   → provider-local stable metric ID
credit fields       → value/limit metric or provider status
```

Prefer `rateLimitsByLimitId`; only fall back to `rateLimits` if the newer
collection has no data. Don't hard-code "5 hours" or "7 days": the label is
derived from the window duration/metadata returned.

### `account/rateLimits/updated`

This is a **sparse** notification, not a full snapshot. The provider must
merge present fields into the latest snapshot; `null` metadata in an update
must not automatically clear known values. When the merge isn't certain to
be correct, or the limit set changes, call `account/rateLimits/read` again.

Reset-credit data is snapshot-only. Agent Meter may display the amount if a
future product spec requires it, but v1 does not redeem it.

### `account/usage/read`

This method returns a token-activity summary and daily buckets at the
account level. This is supplementary data, not a replacement for the
subscription rate limit. v1 fetches it to prove the capability and prepare
the model, but the quota UI prioritizes `account/rateLimits/read`. If the
method isn't supported on the current binary/account, the provider still
works with rate limits alone.

## Stability and compatibility

| Risk | Level | Handling |
|---|---|---|
| `app-server` still marked experimental in CLI help | Medium | Pin a minimum tested version, schema fixtures, clear capability errors |
| Protocol adds fields/notifications | Low | Tolerant decode, ignore unknown |
| Method missing on an older CLI | Medium | Version preflight and an unsupported-method state |
| Sparse update loses metadata | High if merged incorrectly | Merge present fields or refetch the snapshot |
| Subprocess hangs/dies | Medium | Timeout, cancel pending calls, capped restart backoff |
| API-key/Bedrock has no ChatGPT quota | Expected | Provider available but subscription quota unavailable |

The minimum tested version for v1 is `0.146.0`. This does not claim older
versions can't work; the app only rejects untested versions to avoid
depending on an unknown schema.

## Capability audit

| Capability | Source | v1 status |
|---|---|---|
| Account/auth/plan | `account/read` | Implemented |
| Quota windows/reset | `account/rateLimits/read` | Implemented |
| Live quota changes | `account/rateLimits/updated` | Implemented |
| Credits/spend control | Rate-limit snapshot | Parsed and shown when available |
| Token activity/daily buckets | `account/usage/read` | Parsed; detailed UI is out of v1 scope |
| Earned reset redemption | consume method | Out of scope; never called |
| Direct backend HTTP | Not needed | Forbidden |
