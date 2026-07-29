# Claude Code provider

Tài liệu này mô tả đúng implementation Agent Meter tại thời điểm
2026-07-29. Đây không phải tài liệu về Anthropic API công khai: hai endpoint
quota đang dùng là contract nội bộ, có thể thay đổi mà không báo trước.

## Phạm vi quota

Claude tính usage limit trên nhiều bề mặt dùng chung một tài khoản, không riêng
Claude Code. Anthropic xác nhận hoạt động trên Claude, Claude Code và các bề mặt
khác cùng tính vào usage limit; quota phụ thuộc plan, model, độ dài và độ phức
tạp của phiên làm việc. Claude Code cũng có lệnh `/usage` để xem trạng thái
rate-limit của plan.

Nguồn chính thức:

- [Claude usage and length limits](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work)
- [Use Claude Code with a Pro or Max plan](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan)
- [Claude Code cheatsheet](https://support.claude.com/en/articles/14553413-claude-code-cheatsheet)

Vì quota được dùng chung, nhãn provider trong Agent Meter là **Claude Code**
nhưng số liệu thực chất là quota của tài khoản Claude.

## Luồng đang được dùng

### 1. Đọc OAuth credential của Claude Code

Agent Meter không thực hiện login. Trên macOS, nó chạy:

```text
/usr/bin/security find-generic-password -s "Claude Code-credentials" -w
```

Payload JSON được decode theo ba shape, theo thứ tự:

1. `{ "claudeAiOauth": { ... } }`;
2. OAuth object không có wrapper;
3. `ClaudeCredentials` trực tiếp.

Các trường được giữ lại gồm access token, refresh token, thời điểm hết hạn và
subscription type. `expiresAt` từ payload CLI được hiểu là Unix milliseconds.
App chỉ kiểm tra access token còn hạn; app **không** dùng refresh token và không
tự refresh credential. Claude Code vẫn là chủ sở hữu login lifecycle.

Anthropic công khai rằng Claude Code hỗ trợ đăng nhập bằng Claude subscription
và lưu credential an toàn, nhưng không công bố keychain service name hay payload
schema nói trên. Xem [Claude Code getting started](https://code.claude.com/docs/en/getting-started).

### 2. Gọi OAuth usage endpoint

Request hiện tại:

```http
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer [REDACTED_SECRET]
User-Agent: claude-code/<installed-cli-version>
anthropic-beta: oauth-2025-04-20
Accept: application/json
Content-Type: application/json
```

`ClaudeCodeVersionResolver` tìm version mà không phụ thuộc `PATH`: symlink native,
thư mục version native, kết quả auto-update, rồi các binary path phổ biến. Nếu
không tìm thấy, nó dùng version fallback đã pin.

Response được decode với ISO-8601 có hoặc không có fractional seconds. Giá trị
`utilization` trong khoảng `(0, 1)` được chuyển sang phần trăm; các giá trị khác
được giữ nguyên. HTTP behavior:

| Status | Xử lý |
|---|---|
| `200` | Decode snapshot |
| `401` | Unauthorized |
| `429` | Rate-limited; đọc `Retry-After` từ header, JSON hoặc text |
| `5xx` và status khác | Server error |

### 3. Web fallback tùy chọn

Nếu OAuth request ném `APIError`, app thử fallback khi người dùng đã nhập đủ
organization ID và `sessionKey`:

```http
GET https://claude.ai/api/organizations/<organization-id>/usage
Cookie: sessionKey=[REDACTED_SECRET]
```

Nếu response có `Set-Cookie` mới, app lấy `sessionKey` mới và ghi lại settings.
`401` và `403` đều được coi là unauthorized. Đây cũng là private web contract,
không phải API được Anthropic cam kết cho third-party client.

## Capability audit

Các nhãn dưới đây quan trọng khi tổng quát hóa: field tồn tại trong DTO không có
nghĩa là người dùng đã thấy tính năng đó.

### Đang được implement và dùng

| Capability | Runtime behavior |
|---|---|
| `five_hour` | Hiển thị card; menu bar; forecast; polling; notification/reset |
| `seven_day` | Hiển thị card; detailed menu bar; forecast; polling; notification/reset |
| `seven_day_sonnet` | Hiển thị khi bật setting; polling; notification/reset |
| `seven_day_omelette` | Map thành Claude Design; hiển thị khi bật setting; notification/reset |
| `extra_usage` | Hiển thị credit usage khi enabled và setting được bật |
| OAuth error/cooldown | Cache fallback, auth gate và persisted `429` cooldown |
| Offline cache | Một snapshot Claude, TTL 24 giờ |
| Web fallback | Opt-in; chạy sau mọi `APIError` của OAuth path |

`seven_day_opus` không có card riêng nhưng được dùng trong adaptive polling,
notification và reset detection. Vì vậy nó là **được xử lý nhưng chỉ hiển thị
gián tiếp**, không phải hoàn toàn unused.

### Đã parse nhưng chưa dùng vào sản phẩm

| Field/model | Hiện trạng |
|---|---|
| `seven_day_oauth_apps` | Decode và cache; không card, menu bar, polling hay notification |
| `seven_day_cowork` | Decode và cache; không card, menu bar, polling hay notification |
| `TokenUsage` | Có model và component mẫu, không được nối vào fetch/runtime |
| `subscriptionType` | Decode từ credential nhưng không nối vào app state hoặc badge |
| `SubscriptionBadgeView` | Có component preview, không xuất hiện trong popover thực |

### Chỉ được tuyên bố hoặc chưa được chứng minh

- README nói “plan detection” cho Free, Pro, Max, Max 5x, Team, Enterprise.
  Runtime hiện tại không render plan và unknown plan còn fallback thành Pro.
- README nói “token consumption in real-time”. Provider hiện tại chỉ fetch
  utilization quota; không thu thập token ledger theo thời gian thực.
- Không có bằng chứng public contract cho `/api/oauth/usage`,
  `/api/organizations/<id>/usage`, keychain payload hay beta header. Những phần
  này chỉ được chứng minh bằng implementation và test của repo.

## Stability và security

| Rủi ro | Mức | Quyết định |
|---|---|---|
| Private OAuth/web schema thay đổi | Cao | DTO tolerant, provider-local mapper, test fixtures, lỗi không làm hỏng provider khác |
| Đọc keychain item do app khác sở hữu | Cao | Chỉ đọc; không ghi/xóa/refresh token; không log payload |
| Web session trong UserDefaults | Critical cần sửa | Migrate sang Keychain do Agent Meter sở hữu, rồi xóa bản settings |
| Raw DEBUG response có thể chứa dữ liệu tài khoản | Cao | Redact hoặc loại bỏ raw body logging trước release đa-provider |
| Hardcoded CLI fallback version | Trung bình | Giữ resolver động; báo lỗi rõ nếu endpoint từ chối version |

Web fallback phải được ghi nhãn **Experimental**, mặc định tắt. App không được
hiển thị access token, refresh token, cookie, email hay organization/account ID
trong log, cache, fixture hoặc tài liệu.

## Mapping sang model chung

Mỗi window có dữ liệu được map thành một metric động:

```text
providerID    = "claude-code"
metric.id     = raw field name ổn định theo provider
usedPercent   = normalized utilization
resetsAt      = resets_at
windowDuration = known duration khi semantics đã xác định
```

`extra_usage` map thành metric value/limit, không ép thành rate-limit window nếu
thiếu utilization. Unknown field không được làm fail toàn snapshot; provider
có thể bổ sung mapping khi semantics đã được xác nhận.

