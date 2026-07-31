# Feasibility: Agent Meter multi-provider

Assessment date: **2026-07-29**

## Verdict

**PASS.** Agent Meter multi-provider is complete.

Both providers have a path to fetch subscription quota without screen scraping:

- Claude Code: the current implementation already operates via the OAuth usage
  endpoint and a web fallback, but both are private contracts.
- Codex: OpenAI publishes account/rate-limit methods via the local
  `codex app-server`; no need to read tokens or call private HTTP endpoints.

PASS does not mean both providers have equal stability. The architecture
requires isolating adapter, schema, and failure state per provider.

## Capability matrix

| Capability | Claude Code | Codex |
|---|---|---|
| Account/plan | Credential has a plan field but not wired to UI | `account/read`, plan when available |
| Subscription quota % | `/api/oauth/usage` private | `account/rateLimits/read` official local protocol |
| Window duration | Inferred from known field names | `windowDurationMins` from protocol |
| Reset time | ISO-8601 `resets_at` | Unix seconds `resetsAt` |
| Multiple/model limits | DTO has several Claude-specific fields | Collection keyed by limit ID, primary/secondary |
| Push update | No | Sparse `account/rateLimits/updated` |
| Extra credit/spend | `extra_usage` | Credits, individual limit, spend control when available |
| Token activity | Model exists, no runtime source yet | `account/usage/read` |
| Credential ownership | Reads Claude Code's keychain item | Codex app-server owns all auth |
| Contract stability | Low | Medium; official repo but CLI command is experimental |
| Offline cache | One snapshot exists | Needs cache keyed by provider |

## Evidence and limits

### Claude

The current code proves that request, DTO, polling, cache, notification, and
UI work with quota fields. Anthropic confirms subscription usage is shared
between Claude and Claude Code, has rolling/weekly limits, and provides
`/usage`, but does not publish the endpoint or schema the app actually calls.

### Codex

The OpenAI app-server README publishes:

- stdio JSONL lifecycle;
- `account/read`;
- `account/rateLimits/read`;
- sparse `account/rateLimits/updated`;
- `account/usage/read`;
- semantics of `usedPercent`, `windowDurationMins`, and `resetsAt`.

Local CLI `0.146.0` confirms the app-server command and stdio transport are
present. A given runtime account may not return every optional field; that is
a missing capability, not evidence the whole provider is infeasible.

## Conditions to keep the PASS verdict

The implementation must halt release if any of the following conditions fail:

1. The Codex provider cannot read at least one rate-limit snapshot on a
   supported ChatGPT account via app-server.
2. The app needs to read/copy Codex credentials or call a private OpenAI HTTP
   endpoint.
3. Adding Codex causes a Claude regression, or a failure in one provider
   blocks the other.
4. The Claude web session remains in UserDefaults, or a secret shows up in
   logs.
5. The schema cannot tolerate optional/unknown fields or sparse
   notifications.

If upstream removes the app-server rate-limit read API, the Codex provider
must switch to unsupported/degraded; it must not be replaced with dashboard
scraping.

## Product decisions

- v1 supports macOS, Claude Code, and Codex.
- The UI selects one provider at a time; no aggregated dashboard.
- The core model uses dynamic metrics, not a shared plan/window enum.
- Provider-specific capabilities are shown conditionally.
- The Claude web fallback is Experimental and opt-in.
- No deploy, release publishing, credit redemption, or account changes are in
  scope.
