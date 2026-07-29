# Feasibility: Agent Meter đa-provider

Ngày đánh giá: **2026-07-29**

## Verdict

**PASS.** Agent Meter đa-provider đã hoàn thành.

Hai provider đều có đường lấy subscription quota mà không cần screen scraping:

- Claude Code: implementation hiện tại đã vận hành qua OAuth usage endpoint và
  web fallback, nhưng cả hai là private contract.
- Codex: OpenAI công bố account/rate-limit methods qua local
  `codex app-server`; không cần đọc token hoặc gọi private HTTP endpoint.

PASS không có nghĩa hai provider có độ ổn định bằng nhau. Kiến trúc bắt buộc
cô lập adapter, schema và failure state theo provider.

## Capability matrix

| Capability | Claude Code | Codex |
|---|---|---|
| Account/plan | Credential có field plan nhưng chưa nối UI | `account/read`, plan khi có |
| Subscription quota % | `/api/oauth/usage` private | `account/rateLimits/read` official local protocol |
| Window duration | Suy từ tên field đã biết | `windowDurationMins` từ protocol |
| Reset time | ISO-8601 `resets_at` | Unix seconds `resetsAt` |
| Multiple/model limits | DTO có nhiều field Claude-specific | Collection theo limit ID, primary/secondary |
| Push update | Không | Sparse `account/rateLimits/updated` |
| Extra credit/spend | `extra_usage` | Credits, individual limit, spend control khi có |
| Token activity | Model rời, chưa có source runtime | `account/usage/read` |
| Credential ownership | Đọc keychain item của Claude Code | Codex app-server giữ toàn bộ auth |
| Contract stability | Thấp | Trung bình; official repo nhưng CLI command experimental |
| Offline cache | Đã có một snapshot | Cần cache keyed theo provider |

## Bằng chứng và giới hạn

### Claude

Code hiện tại chứng minh request, DTO, polling, cache, notification và UI chạy
với quota fields. Anthropic xác nhận subscription usage được chia sẻ giữa Claude
và Claude Code, có rolling/weekly limits và cung cấp `/usage`, nhưng không công
bố endpoint hoặc schema mà app đang gọi.

### Codex

OpenAI app-server README công bố:

- stdio JSONL lifecycle;
- `account/read`;
- `account/rateLimits/read`;
- sparse `account/rateLimits/updated`;
- `account/usage/read`;
- semantics của `usedPercent`, `windowDurationMins` và `resetsAt`.

Local CLI `0.146.0` xác nhận app-server command và stdio transport có mặt. Một
runtime account có thể không trả mọi optional field; đó là missing capability,
không phải bằng chứng toàn provider không khả thi.

## Điều kiện để giữ verdict PASS

Implementation phải dừng release nếu một trong các điều kiện sau không đạt:

1. Codex provider không đọc được ít nhất một rate-limit snapshot trên ChatGPT
   account được hỗ trợ qua app-server.
2. App cần đọc/copy credential Codex hoặc gọi private OpenAI HTTP endpoint.
3. Việc thêm Codex làm Claude regression hoặc lỗi một provider chặn provider kia.
4. Web session Claude vẫn nằm trong UserDefaults hay secret xuất hiện trong log.
5. Schema không chịu được optional/unknown fields hoặc sparse notifications.

Nếu upstream bỏ app-server rate-limit read API, Codex provider phải chuyển sang
unsupported/degraded; không thay bằng dashboard scraping.

## Quyết định sản phẩm

- v1 hỗ trợ macOS, Claude Code và Codex.
- UI chọn một provider tại một thời điểm; không làm dashboard tổng hợp.
- Core model dùng metric động, không dùng enum plan/window chung.
- Provider-specific capability được hiển thị có điều kiện.
- Web fallback Claude là Experimental và opt-in.
- Không deploy, publish release, redeem credit hay thay đổi account trong scope.

