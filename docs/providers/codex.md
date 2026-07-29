# Codex provider

## Kết luận tích hợp

Codex hỗ trợ tích hợp quota khả thi thông qua `codex app-server`. Đây là local
interface mà OpenAI dùng để xây rich client như VS Code extension. App-server
trao đổi JSON-RPC hai chiều qua JSONL trên stdio và công bố các account methods
cần thiết cho Agent Meter.

Nguồn chính:

- [OpenAI Codex app-server protocol](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)
- [Codex app-server protocol types](https://github.com/openai/codex/tree/main/codex-rs/app-server-protocol/src/protocol)

Đánh giá local ngày 2026-07-29 xác nhận `codex-cli 0.146.0` có
`codex app-server`, stdio là transport mặc định, và CLI vẫn gắn nhãn command này
là `experimental`. Vì vậy đây là **official local contract với stability risk
trung bình**, không phải public HTTP API có versioning độc lập.

## Security boundary

Agent Meter chạy binary Codex mà người dùng đã cài và giao tiếp với subprocess:

```text
Agent Meter ⇄ stdin/stdout JSONL ⇄ codex app-server ⇄ OpenAI
```

Agent Meter không:

- đọc hoặc parse `~/.codex/auth.json`;
- copy OAuth/API key vào settings, log hoặc cache;
- gọi trực tiếp private OpenAI backend endpoint;
- bắt đầu login, logout hoặc đổi account;
- gọi `account/rateLimitResetCredit/consume`;
- gửi email nudge hoặc thực hiện hành động làm thay đổi account.

Codex sở hữu credential storage, token refresh và backend authentication. Agent
Meter chỉ dùng read methods.

## Process lifecycle

1. Resolve binary từ path người dùng cấu hình, `PATH`, rồi các vị trí cài đặt
   Homebrew/NVM phổ biến.
2. Chạy `codex app-server`; stdio là transport mặc định.
3. Gửi `initialize`, đợi response thành công, rồi gửi notification
   `initialized`.
4. Giữ một subprocess sống lâu cho provider; dùng request ID tăng đơn điệu để
   ghép response với request đang chờ.
5. Đọc từng dòng stdout như một JSON message. Stderr chỉ dùng cho diagnostic đã
   redact, không trộn vào protocol parser.
6. Khi process exit hoặc protocol hỏng, fail các request đang chờ, giữ snapshot
   cache và restart với exponential backoff có giới hạn.

Mọi request phải có timeout. Unknown notification hoặc field phải được bỏ qua
an toàn để app-server có thể phát triển mà không làm crash client.

## Read methods

### `account/read`

```json
{"method":"account/read","id":1,"params":{"refreshToken":false}}
```

Dùng để xác định:

- có account hay không;
- Codex có yêu cầu OpenAI auth hay không;
- auth mode;
- plan type khi backend cung cấp.

Agent Meter đặt `refreshToken: false`: một quota viewer không nên chủ động thay
đổi auth state. `account/updated` làm provider invalidated và kích hoạt refetch.

Các auth mode được protocol công bố gồm ChatGPT managed, API key, personal access
token và Amazon Bedrock experimental. Subscription quota chỉ có ý nghĩa khi
app-server trả ChatGPT rate limits. API-key-only, Bedrock hoặc local/OSS mode
phải hiện trạng thái “Subscription quota unavailable”, không biến thành lỗi
đăng nhập giả.

### `account/rateLimits/read`

```json
{"method":"account/rateLimits/read","id":2}
```

Response có thể chứa:

- `rateLimits` tương thích ngược;
- nhiều limit trong `rateLimitsByLimitId`;
- `primary` và `secondary` window;
- `usedPercent`, `windowDurationMins`, `resetsAt` Unix seconds;
- plan/limit identifiers;
- credit balance hoặc effective monthly limit khi có;
- `spendControlReached`;
- earned reset-credit snapshot.

Mapping:

```text
usedPercent         → UsageMetric.usedPercent
windowDurationMins  → UsageMetric.windowDuration
resetsAt            → UsageMetric.resetsAt
limit id + window   → provider-local stable metric ID
credit fields       → value/limit metric hoặc provider status
```

Ưu tiên `rateLimitsByLimitId`; chỉ fallback `rateLimits` nếu collection mới
không có dữ liệu. Không hard-code “5 giờ” hoặc “7 ngày”: label được suy ra từ
window duration/metadata trả về.

### `account/rateLimits/updated`

Đây là notification **sparse**, không phải snapshot hoàn chỉnh. Provider phải
merge field có mặt vào snapshot gần nhất; `null` metadata trong update không
được tự động xóa giá trị đã biết. Khi merge không đảm bảo đúng hoặc limit set
thay đổi, gọi lại `account/rateLimits/read`.

Reset-credit data là snapshot-only. Agent Meter có thể hiển thị số lượng nếu
product spec sau này yêu cầu, nhưng v1 không redeem.

### `account/usage/read`

Method này trả token-activity summary và daily buckets ở cấp account. Đây là dữ
liệu bổ trợ, không thay thế subscription rate-limit. V1 fetch để chứng minh
capability và chuẩn bị model, nhưng UI quota ưu tiên `account/rateLimits/read`.
Nếu method không được hỗ trợ ở binary/account hiện tại, provider vẫn hoạt động
với rate limits.

## Stability và compatibility

| Rủi ro | Mức | Cách xử lý |
|---|---|---|
| `app-server` còn experimental trong CLI help | Trung bình | Pin minimum tested version, schema fixtures, capability errors rõ |
| Protocol thêm field/notification | Thấp | Tolerant decode, ignore unknown |
| Method thiếu ở CLI cũ | Trung bình | Preflight version và unsupported-method state |
| Sparse update làm mất metadata | Cao nếu merge sai | Merge present fields hoặc refetch snapshot |
| Subprocess treo/chết | Trung bình | Timeout, cancel pending calls, capped restart backoff |
| API-key/Bedrock không có ChatGPT quota | Dự kiến | Provider available nhưng subscription quota unavailable |

Minimum tested version cho v1 là `0.146.0`. Không tuyên bố version cũ hơn không
thể hoạt động; app chỉ từ chối version chưa được kiểm thử để tránh phụ thuộc
schema không xác định.

## Capability audit

| Capability | Nguồn | Trạng thái v1 |
|---|---|---|
| Account/auth/plan | `account/read` | Implement |
| Quota windows/reset | `account/rateLimits/read` | Implement |
| Live quota changes | `account/rateLimits/updated` | Implement |
| Credits/spend control | Rate-limit snapshot | Parse và hiển thị khi có |
| Token activity/daily buckets | `account/usage/read` | Parse; UI chi tiết ngoài v1 |
| Earned reset redemption | consume method | Ngoài phạm vi; không gọi |
| Direct backend HTTP | Không cần | Cấm |
