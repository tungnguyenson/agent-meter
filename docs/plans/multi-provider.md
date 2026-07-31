# Implementation plan: multi-provider Agent Meter

## Execution principles

Follow TDD phase by phase: write a failing test, minimal implementation to
pass, refactor, then rerun the suite. No release publishing within this plan.
Preserve existing Git history when changing remote/rebranding, and never put
secrets/PII into fixtures.

## Phase 1. Core contract and Claude adapter

1. Write tests for normalized models, unknown provider/metric values,
   percentage, and value/limit metrics.
2. Create the provider protocol, metadata, snapshot/metric model, and error
   taxonomy.
3. Write mapper tests from the current `UsageData` to the dynamic snapshot,
   including missing fields, fractional utilization, ISO dates, and extra
   usage.
4. Wrap the existing Claude keychain/OAuth/web/cache behind
   `ClaudeCodeProvider` without changing UX yet.
5. Run the regression suite to prove Claude behavior is unchanged.

Exit criteria: all Claude fetches go through the provider contract; the app
still displays the same data as before.

## Phase 2. Codex app-server client

1. Build a fake JSONL process harness and test handshake, request IDs,
   concurrent responses, notifications, malformed lines, stderr, timeout, and
   process exit.
2. Implement the binary resolver and version preflight without going through
   a shell.
3. Implement the long-lived process, `initialize`/`initialized`, a
   pending-call table, and cancellation-safe shutdown.
4. Write DTO/mapper tests for:
   - account/auth/plan;
   - single and multi-limit collections;
   - primary/secondary windows;
   - Unix-second reset;
   - credits, individual limit, and spend control;
   - missing/unknown fields.
5. Implement the read calls; `account/usage/read` is best-effort.
6. Test sparse update merging: absent/null metadata does not clear the
   snapshot; ambiguous updates trigger a refetch.
7. Implement bounded exponential restart backoff.

Exit criteria: fixture integration tests return a Codex snapshot; a live smoke
test on a ChatGPT-authenticated CLI `>=0.146.0` returns at least one quota
window. If the live smoke test fails, halt the Codex rollout and record the
exact blocker; do not fall back to dashboard scraping.

## Phase 3. Multi-provider coordinator

1. Write tests for parallel refresh, partial success, provider-isolated
   cache, stale state, auth gate, `429` cooldown, and subprocess backoff.
2. Replace the singleton Claude usage state with a coordinator keyed by
   provider.
3. Cache v2 snapshot/cooldown per provider; a decode failure in one entry
   must not lose other entries.
4. Namespace notification state by provider + metric + threshold.
5. Forecast only applies to metrics with sufficient data.

Exit criteria: one provider fails continuously while the other keeps
refreshing, notifying, and rendering from its own state.

## Phase 4. Settings migration and security hardening

1. Write migration tests from settings/cache v1, including rerun idempotency
   and partial Keychain failure.
2. Implement settings v2: enabled/selected providers, visibility, max two
   pins.
3. Migrate global Claude preferences and the legacy cache.
4. Move Claude's `sessionKey` to an Agent Meter-owned Keychain; only remove
   the legacy value after a successful write.
5. Redact diagnostics; remove raw credential/PII response logging.
6. Security tests for executable path/argv, log redaction, and
   cache/settings serialization containing no secrets.

Exit criteria: searching UserDefaults/cache/log fixtures finds no token,
cookie, email, or account ID; migration does not lose a secret if the
Keychain write fails.

## Phase 5. UX and rebrand

1. Write view-model tests for the picker, dynamic cards,
   unsupported/auth/error/stale states, and pin fallback.
2. Rework the popover into Agent Meter with a provider picker and
   health/last-updated indicators.
3. Rework the menu bar for the selected provider and up to two dynamic pinned
   metrics; keep Icon, Compact, and Detailed, and fixed/countdown style.
4. Split Settings into global and provider sections; the Claude web fallback
   is labeled Experimental.
5. Rebrand target/scheme/app/cache/defaults/DMG/docs to Agent Meter, bundle
   ID `com.agentmeter.app`; keep compatibility migration for legacy
   keys/paths.
6. Preserve Git history; change `origin` to
   `git@github.com:tungnguyenson/agent-meter.git` once code/tests are
   stable.

Exit criteria: the critical UI flow works with both Claude and Codex enabled;
ClaudeMeter branding is removed, keeping only migration/legacy compatibility
code.

## Verification and review

Run at minimum:

```bash
xcodebuild test -project AgentMeter.xcodeproj \
  -scheme AgentMeter \
  -destination 'platform=macOS'
```

If the rebrand is not yet complete in the phase being run, use the old
project/scheme but note the boundary clearly. Then:

1. Report coverage and add tests to reach at least 80%.
2. Run a general code review and a Swift-specific review.
3. A security review is mandatory because credential, filesystem, subprocess,
   and external API boundaries are involved.
4. Fix all CRITICAL/HIGH issues; fix MEDIUM issues when it doesn't expand
   scope.
5. Check for no hardcoded secrets, no debug print/raw response, no deep
   nesting, no function >50 lines, and no new file >800 lines.
6. Live smoke test both Claude and Codex; static tests do not replace runtime
   acceptance.

## Rollout boundary

- No deploy, notarize, GitHub release creation, or credit redemption.
- Only open a draft PR once tests, coverage, and review pass.
- The Codex provider may ship under a feature flag if app-server
  compatibility needs more soak time; the Claude provider remains the
  default after migration.
- If an upstream contract fails, disable that provider individually and keep
  the cached snapshot in a degraded state; do not switch to another private
  endpoint outside the spec.
