# Agent Meter multi-provider spec

## Mục tiêu

Agent Meter là macOS menu-bar app theo dõi subscription quota của nhiều coding
agent. v1 mở rộng từ phiên bản trước sang Agent Meter, giữ đầy đủ hành vi
Claude đã dùng và thêm Codex qua local app-server.

Thành công khi người dùng bật cả hai provider, chuyển provider trong popover,
xem quota/reset/health, pin tối đa hai metric lên menu bar, và một provider lỗi
không ảnh hưởng provider còn lại.

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

Yêu cầu model:

- `ProviderID` và metric ID là string ổn định, namespaced theo provider khi lưu.
- Không có enum subscription plan dùng chung; unknown plan giữ nguyên label.
- Metric percentage và value/limit đều optional vì provider capability khác nhau.
- Forecast chỉ chạy khi có percentage, reset và window duration hợp lệ.
- Mapper clamp presentation vào `0...100` nhưng giữ raw diagnostic đã redact để
  phát hiện upstream drift; không silently đổi `0.5` thành `50%` nếu provider
  contract nói đó đã là percent.

## Provider behavior

### Claude Code

- Cô lập credential reader, OAuth client, experimental web client và DTO mapper.
- Giữ OAuth-first, cache fallback và rate-limit cooldown hiện tại.
- Map mọi field đã biết thành metric; không làm toàn snapshot fail vì field lạ.
- Migrate web session secret sang Agent Meter-owned Keychain.
- Giữ Claude-specific settings cho Sonnet, Design và Extra Usage bằng metric
  visibility thay vì boolean hard-code trong global settings.

### Codex

- Resolve binary; minimum tested version `0.146.0`.
- Một long-lived `codex app-server` subprocess; stdio là transport mặc định.
- Handshake trước mọi account method.
- Fetch `account/read`, `account/rateLimits/read` và best-effort
  `account/usage/read`.
- Merge sparse rate-limit notifications hoặc refetch khi không chắc chắn.
- Không đọc auth file, không direct HTTP, không dùng write/action account methods.
- API key, Bedrock, OSS/local mode hiện “Subscription quota unavailable”.

## Coordinator và state

Coordinator giữ state keyed theo `ProviderID`:

```text
disabled | unavailable | loading | ready | stale | error
```

Mỗi provider có snapshot, error, last success, active fetch, auth gate,
rate-limit cooldown và retry/backoff độc lập. Refresh-all chạy song song. Partial
success được publish ngay; không xóa snapshot cũ khi refresh mới lỗi.

Provider selected chỉ điều khiển popover/menu bar, không ngăn provider khác poll.
Khi app ở background, cadence có thể chậm hơn nhưng vẫn độc lập. Notification key:

```text
<provider-id>:<metric-id>:<threshold>
```

để không collision giữa provider/window.

## UX

### Popover

- Header “Agent Meter”.
- Provider picker hiển thị icon, tên, health dot và last-updated state.
- Nội dung là danh sách metric card động của provider đang chọn.
- Percentage window hiển thị usage, reset countdown và forecast.
- Value/limit metric hiển thị số, unit và progress nếu tính được.
- Stale snapshot vẫn hiển thị với timestamp và lỗi không che mất dữ liệu cũ.
- Empty/unsupported/auth states có copy riêng, không gộp thành “not logged in”.

### Menu bar

Giữ ba mode Icon, Compact và Detailed. Menu bar dùng selected provider và tối đa
hai pinned metric:

- nếu pin còn tồn tại, render theo thứ tự setting;
- nếu metric biến mất, fallback sang hai percentage metric đầu tiên;
- nếu không có metric, hiển thị provider icon và trạng thái `--`;
- countdown lấy window duration/reset từ metric, không hard-code theo provider.

### Settings

Global: launch at login, Dock, appearance, polling, notifications và custom
colors.

Provider section: enabled, binary/path hoặc experimental configuration, metric
visibility và pinning. Secret field không round-trip qua `AppSettings`.

## Persistence và migration

Settings/cache schema tăng lên v2:

```text
enabledProviderIDs
selectedProviderID
metricVisibility[providerID][metricID]
pinnedMetricIDs[providerID]       // max 2
provider cache[providerID]
```

One-time migration từ phiên bản trước:

1. Import display mode/style, color scheme, Dock/login, polling, notification và
   custom color settings.
2. Bật Claude provider và chọn Claude nếu chưa có lựa chọn.
3. Map Sonnet/Design/Extra Usage toggles thành metric visibility.
4. Import Claude cache v1 nếu decode được; lỗi migration không crash launch.
5. Ghi `webSessionKey` vào Agent Meter-owned Keychain, xác nhận write thành
   công, sau đó xóa secret khỏi settings/UserDefaults.
6. Không copy OAuth token hoặc refresh token của Claude Code.

Migration idempotent và ghi version chỉ sau khi các bước bắt buộc hoàn tất.

## Error và security requirements

- User-facing error phân biệt: binary missing, unsupported version, not signed
  in, quota unavailable for auth mode, rate-limited, network, protocol, decode.
- Diagnostic có provider/method/request ID nhưng redact secret, email, account ID,
  cookie, header và raw response chứa PII.
- Cache file không chứa credential; sensitive Keychain item chỉ app được đọc.
- Subprocess path phải là file executable đã resolve; không xây shell command từ
  user input.
- Không dùng `sh -c`; truyền executable URL và argv trực tiếp.
- App không thực hiện login/logout, purchase, email nudge hay credit redemption.

## Acceptance criteria

1. Claude UI/menu bar/notification/cache hiện có không regression.
2. ChatGPT-authenticated Codex trả quota card với percent, duration và reset qua
   app-server.
3. Claude và Codex cùng enabled; một bên lỗi, bên kia vẫn poll/refresh/display.
4. Restart app phục hồi per-provider cache và cooldown đúng namespace.
5. Unknown plan/metric/notification không crash và không bị giả thành giá trị
   mặc định sai.
6. Không còn Claude web secret trong UserDefaults, log hoặc cache.
7. Không có direct OpenAI private endpoint hay read `~/.codex/auth.json`.
8. Unit, integration và critical UI flow pass; coverage tối thiểu 80%.
