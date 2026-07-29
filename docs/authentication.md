# Authentication

AgentMeter never runs its own login flow. It has no OAuth client, no browser
redirect, no password field. Instead it reads the credentials that the
**Claude Code CLI** already wrote to the macOS keychain when you ran
`claude login`, and reuses them to call the same usage endpoint the CLI uses.

If you're logged in to Claude Code, AgentMeter works. If you're not, it shows a
"no credentials" state and there's nothing to configure — you log in through the
CLI, not the app.

There is also an optional **web session fallback** against `claude.ai` for cases
where the OAuth path fails. It's off unless you fill in two fields in Settings.

## The two credential sources

| Source | Origin | Used when | Configured by |
|--------|--------|-----------|---------------|
| OAuth access token | keychain item written by `claude login` | always, first | Claude Code CLI |
| `claude.ai` session cookie | copied from a browser session | only if the OAuth call fails | you, in Settings |

Data flows `KeychainService → UsageManager → APIService → api.anthropic.com`.
The web fallback flows `AppSettings → UsageManager → APIService → claude.ai`.

## Primary path: OAuth token from the keychain

### 1. Locating the keychain item

Claude Code stores its credentials as a generic-password item under the service
name **`Claude Code-credentials`** (`Constants.Keychain.serviceName`,
`Constants.swift:98`). AgentMeter looks for that exact service name.

The catch: reading *another* app's keychain item through the Security framework
(`SecItemCopyMatching`) triggers the macOS "AgentMeter wants to use your
confidential information" password dialog every time. To avoid nagging the user,
`KeychainService` shells out to the system `security` binary instead:

```
/usr/bin/security find-generic-password -s "Claude Code-credentials" -w
```

See `readCredentialsViaShell()` (`KeychainService.swift:137`). The `-w` flag
prints just the raw password payload. Because the CLI created the item, the
`security` tool returns it without a prompt. The output is trimmed of its
trailing newline and returned as `Data`.

> `KeychainService` still implements Security-framework `save`/`read`/`delete`
> methods (`KeychainService.swift:51`–`130`), but the live credential read for
> Claude Code goes through the shell path.

### 2. Decoding the payload

The keychain payload is JSON. `getCredentials()` (`KeychainService.swift:178`)
tries three shapes, in order, to be tolerant of format drift:

1. **Wrapped** — `{ "claudeAiOauth": { accessToken, refreshToken, expiresAt, subscriptionType } }` — the format Claude Code actually writes (`ClaudeKeychainData`, `KeychainService.swift:22`).
2. **Bare** — the same object without the `claudeAiOauth` wrapper (`ClaudeOAuthData`, `KeychainService.swift:31`).
3. **Direct** — decode straight into `ClaudeCredentials`.

Everything normalizes into a single `ClaudeCredentials` value
(`Credentials.swift:11`):

```swift
struct ClaudeCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let subscriptionType: String   // "pro", "max", "free"
}
```

One conversion detail worth knowing: Claude Code stores `expiresAt` as a
**millisecond** Unix timestamp, so the decoder divides by 1000 to get seconds
(`KeychainService.swift:189`). `ClaudeCredentials` itself also accepts either an
encoded `Date` or a `TimeInterval` for `expiresAt` (`Credentials.swift:37`), so
both cache-persisted and keychain-sourced values decode cleanly.

### 3. Checking validity before the call

`UsageManager.fetchUsage()` (`UsageManager.swift:55`) gates every request on the
credentials:

```swift
guard let credentials = try keychainService.getCredentials() else {
    throw AppError.noCredentials
}
guard credentials.isValid else {          // Date() < expiresAt
    throw AppError.credentialsExpired
}
```

`isValid` is just `Date() < expiresAt` (`Credentials.swift:17`). There's also
`isExpiringSoon`, which trips 5 minutes before expiry
(`Constants.Credentials.expirationWarningThreshold`, `Constants.swift:116`).

**AgentMeter does not refresh tokens.** The `refreshToken` is read and carried
around, but never exchanged. When the access token expires, the app surfaces
`credentialsExpired` and waits for the Claude Code CLI to refresh the keychain
item on its own next use. The refresh responsibility stays with the tool that
owns the login.

### 4. Making the authenticated request

`APIService.fetchUsage(token:)` (`APIService.swift:78`) does a plain
`GET https://api.anthropic.com/api/oauth/usage` with a Bearer token
(`headers(token:)`, `APIService.swift:355`):

```
Authorization: Bearer <accessToken>
User-Agent:    claude-code/<installed version>   e.g. claude-code/2.1.201
anthropic-beta: oauth-2025-04-20
Accept:        application/json
Content-Type:  application/json
```

The `User-Agent` and `anthropic-beta` values mimic the Claude Code client so the
OAuth usage endpoint accepts the request. Rather than pinning a version string
(which drifts out of date and risks rejection), the `User-Agent` is built at
runtime by `ClaudeCodeVersionResolver` from the version of the Claude Code CLI
actually installed on the machine — see
[Resolving the client version](#resolving-the-client-version) below. Response
handling:

- **200** → decode `UsageData` (with a custom ISO-8601 formatter that tolerates fractional seconds).
- **401** → `APIError.unauthorized`.
- **429** → `APIError.rateLimited`, with a `Retry-After` value parsed from the header, JSON body, or free-text message (`parseRetryAfter`, `APIService.swift:146`).
- **5xx** / other → `APIError.serverError`.

`validateToken(_:)` (`APIService.swift:227`) is a thin wrapper: it calls
`fetchUsage` and reports success/failure as a `Bool`, used by
`UsageManager.validateCredentials()`.

### Resolving the client version

The OAuth usage endpoint expects a `claude-code/<version>` User-Agent. A
hardcoded version goes stale as the real CLI updates, so
`ClaudeCodeVersionResolver` (`ClaudeCodeVersionResolver.swift`) detects the
version of the CLI installed on the machine and builds the header from it.
`APIService` takes the resolved value in its initializer (defaulting to
`ClaudeCodeVersionResolver.shared.userAgent`) and uses it for both the OAuth and
web requests.

Detection is **PATH-independent** — a menu-bar app does not inherit the shell's
`PATH` — and tries the cheapest strategies first, taking the first valid
`major.minor.patch` it finds:

1. The basename of the `~/.local/bin/claude` symlink target (native install points it at `.../versions/<version>`).
2. The highest version folder under `~/.local/share/claude/versions/` (numeric-aware comparison, so `2.1.10` beats `2.1.9`).
3. The `version_to` field of `~/.claude/.last-update-result.json`, written by the native auto-updater.
4. Running `claude --version` from known binary locations (covers npm / Homebrew installs) and parsing the leading version.

If every strategy fails (Claude Code not installed, or an unrecognized layout),
it falls back to `Constants.API.fallbackClientVersion`. The result is resolved
once and cached for the app's lifetime; a CLI that self-updates mid-session is
picked up on the next launch.

## Fallback path: claude.ai web session

If the OAuth call throws any `APIError`, `UsageManager` tries the web API before
giving up (`UsageManager.swift:89`, `tryWebAPIFallback()` at
`UsageManager.swift:129`). This path is **opt-in** and stays dormant unless both
of these are set:

- **Organization ID**
- **Session Key** — the `sessionKey` cookie from a signed-in `claude.ai` browser session

You enter them under Settings → General (`GeneralSettingsView.swift:72`,
`:75`), where they persist into `AppSettings.webSessionKey` /
`webOrganizationId` (`AppSettings.swift:62`) and get pushed onto `UsageManager`
by `AppState.applySettings()` (`AppState.swift:137`).

The request (`fetchUsageFromWeb`, `APIService.swift:238`) hits:

```
GET https://claude.ai/api/organizations/<organizationId>/usage
Cookie: sessionKey=<sessionKey>
```

Cookie-based instead of Bearer. If `claude.ai` returns a refreshed `sessionKey`
in a `Set-Cookie` header, the app extracts it (`APIService.swift:285`) and
writes it back through the `onSessionKeyRefreshed` callback
(`AppState.swift:139`) so the stored value stays current. Here `401` **and**
`403` both map to `unauthorized`.

## What happens when auth fails

| Situation | Error | User-visible effect |
|-----------|-------|---------------------|
| No keychain item found | `AppError.noCredentials` | "Not logged in" state; prompt to use Claude Code |
| Access token past `expiresAt` | `AppError.credentialsExpired` | Waits for CLI to refresh |
| OAuth 401 | `APIError.unauthorized` → web fallback, then cached data | Stale data or error |
| OAuth 429 | `APIError.rateLimited` | Backs off using `Retry-After` |
| OAuth fails but web fallback works | — | Fresh data via `claude.ai` |
| Everything fails | last error | Falls back to cached usage (`loadCachedData()`) |

On a hard failure the app degrades to the last cached usage snapshot rather than
blanking the UI.

## Security notes

- **No secrets are stored by AgentMeter.** The OAuth token lives in the keychain item that Claude Code owns; AgentMeter only reads it.
- **No keychain password prompt** in the normal flow, because reads go through the `security` CLI rather than a cross-app `SecItemCopyMatching`.
- **The web session key is sensitive** — it's a live `claude.ai` credential. It's entered through a `SecureField` and persisted in `AppSettings` (UserDefaults). Treat it like a password; leave it blank if you don't need the fallback.
- Tokens are sent only to `api.anthropic.com` and (if configured) `claude.ai` over HTTPS.
- In `DEBUG` builds, raw API responses are appended to `~/Library/Caches/claudemeter_debug.txt` with `0600` permissions (`APIService.swift:310`). This is compiled out of release builds.

## File map

| Concern | File |
|---------|------|
| Keychain read + credential decoding | `AgentMeter/Core/Services/KeychainService.swift` |
| Credential model, validity, expiry | `AgentMeter/Core/Models/Credentials.swift` |
| Authenticated requests, headers, fallback | `AgentMeter/Core/Services/APIService.swift` |
| Runtime `User-Agent` / CLI version detection | `AgentMeter/Core/Services/ClaudeCodeVersionResolver.swift` |
| Orchestration: fetch → validate → fallback → cache | `AgentMeter/Core/Managers/UsageManager.swift` |
| Endpoints, service name, headers, thresholds | `AgentMeter/Core/Constants.swift` |
| Web fallback settings + wiring | `AgentMeter/Core/Models/AppSettings.swift`, `AgentMeter/App/AppState.swift` |
| Settings UI for web fallback | `AgentMeter/UI/Settings/GeneralSettingsView.swift` |
