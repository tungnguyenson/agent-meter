# Cursor provider

Tài liệu này ghi lại kết quả điều tra thực địa ngày 2026-07-30 trên máy dev
(`nstung@gmail.com`, Cursor Pro, `cursor-agent` CLI đã login). Đây **không phải**
tài liệu về API công khai của Cursor: mọi endpoint mô tả dưới đây là contract
nội bộ mà web dashboard `cursor.com` dùng, được suy ra bằng cách probe trực
tiếp, không có trong doc chính thức. Chưa có dòng code nào implement provider
này; tài liệu này là input cho việc đó.

## Kết luận khả thi

Lấy được usage cá nhân, đầy đủ và khớp 1:1 với UI trang Spending
(`cursor.com/dashboard` → Spending). Nhưng đây là **API nội bộ không có hợp
đồng ổn định**, rủi ro tương đương hoặc cao hơn phần Claude Code web fallback.

Theo [cursor.com/docs/api](https://cursor.com/docs/api), API usage/spend chính
thức (Admin API, Analytics API, cụ thể là `api.cursor.com/teams/*` và
`api.cursor.com/analytics`) chỉ dành cho **Enterprise/Team**, auth bằng Basic
Auth với API key riêng. Tài khoản cá nhân **không có API usage chính thức**.
Cloud Agents API mở cho mọi plan nhưng không expose usage/spend.

## Credential

Cursor Desktop/CLI lưu access token + refresh token trong macOS Keychain:

```text
security find-generic-password -s cursor-access-token -a cursor-user -w
security find-generic-password -s cursor-refresh-token -a cursor-user -w
```

Token là JWT do WorkOS cấp:

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

Vòng đời quan sát được: cấp lại mỗi ~60 ngày (test case: issued → expires =
đúng 60.0 ngày). Có refresh token đi kèm nên refresh được, nhưng chưa verify
luồng refresh cụ thể.

**Bẫy quan trọng**: userId đúng để gọi API là claim `sub` của JWT
(`google-oauth2|user_...`), **không phải** số nguyên `authInfo.userId` lưu
trong `~/.cursor/cli-config.json`. Dùng nhầm số nguyên đó, `/api/usage` vẫn trả
`200` nhưng toàn field `0`: fail silent, không có lỗi rõ để bắt.

## Auth header

```http
Cookie: WorkosCursorSessionToken=<sub URL-encoded>::<jwt>
```

Bearer token (`Authorization: Bearer <jwt>`) **không hoạt động** với
`cursor.com` (trả `401 not_authenticated`), nhưng hoạt động với
`api2.cursor.sh` (backend legacy mà desktop app/CLI dùng).

Mọi request `POST` tới `cursor.com/api/dashboard/*` bắt buộc thêm:

```http
Origin: https://cursor.com
```

Thiếu header này, response là `403 {"error":"Invalid origin for
state-changing request"}` dù cookie hợp lệ.

## Endpoint đã verify

### `GET /api/usage-summary` (endpoint chính, dùng cho menu bar)

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

Đã đối chiếu trực tiếp với UI trang Spending, khớp từng số:

| UI Spending | Field | Giá trị test |
|---|---|---|
| "Cursor Models, 100% used" | `plan.autoPercentUsed` | `100` |
| "Other Models, 89% used" | `plan.apiPercentUsed` | `88.89` → làm tròn 89 |
| "plan includes at least $20 of API usage" | `plan.breakdown.included` | `2000` |
| "On-Demand: $0.00 / $5" | `onDemand.used` / `onDemand.limit` | `0` / `500` |

**Đơn vị: cents.** `500` = $5.00, `2000` = $20.00. Field `used`/`limit`/`remaining`
ở top level `plan` là tổng số tiêu từ quota included, **không phải** hạn mức,
tên field gây hiểu lầm.

`breakdown` là phân rã số **đã tiêu** trong chu kỳ, không phải limit:

```text
breakdown.included = tiêu từ quota included trong gói (2000 = $20, đúng bằng giá Pro)
breakdown.bonus     = tiêu từ bonus/credit ngoài included
breakdown.total     = included + bonus
```

Verify chéo: gọi `get-aggregated-usage-events` đúng cửa sổ
`billingCycleStart → now` cho `totalCostCents = 34046.91`, khớp
`breakdown.total = 34047` sai lệch 0.09 cent do làm tròn. Suy ra hạn mức tổng
ẩn = `34047 / 0.98687 ≈ 34500` cents = $345, nhưng con số này **không có sẵn
trong payload**, phải tự suy. Đừng hard-code, chỉ hiển thị percent có sẵn.

**`autoModelSelectedDisplayMessage`/`namedModelSelectedDisplayMessage`** (chuỗi
"You've used 99% of..."): đây là copy hiển thị trong editor khi chọn model,
**không khớp chính xác với số trên trang Spending** (99% vs progress bar 100%
do làm tròn khác nhau). Không dùng chuỗi này để render UI, chỉ dùng số.

### `POST /api/dashboard/get-hard-limit`

```json
{ "hardLimit": 5 }
```

**Đơn vị: dollars**, không phải cents, khác đơn vị với `usage-summary`. Khớp
"Monthly Limit: Fixed, 5" trên UI On-Demand. Bẫy: nếu cộng thẳng field này với
số cents ở endpoint khác sẽ sai lệch 100 lần.

### `GET /api/auth/me`

```json
{
  "email": "nstung@gmail.com",
  "sub": "user_01JNRDXH3VAJ20W3XQW2NX8AD4",
  "id": 167714721
}
```

Dùng để lấy display info; `id` ở đây chính là số `authInfo.userId` trong
`cli-config.json`, xác nhận số đó **không phải** giá trị cần cho query param
`?user=` của `/api/usage` (endpoint cũ, xem phần "Không dùng" bên dưới).

### `GET /api/auth/stripe` (hoặc `api2.cursor.sh/auth/full_stripe_profile` với Bearer)

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

Dùng cho plan label / badge, tương tự `subscriptionType` ở Claude Code.

### `POST /api/dashboard/get-aggregated-usage-events` (optional, panel chi tiết)

Params: `{"teamId":0,"startDate":"<ms>","endDate":"<ms>"}` (epoch millisecond
dạng **string**, không phải number).

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

Token count field là **string**, không phải number, decode phải tolerant.
`totalCents` per-model là `Double`. Hữu ích cho breakdown theo model nếu sau
này làm panel chi tiết; không cần cho menu bar summary.

### `POST /api/dashboard/get-filtered-usage-events` (optional, log từng request)

Params: `{"teamId":0,"page":1,"pageSize":N}`. Trả `totalUsageEventsCount` và
mảng event có `timestamp` (ms string), `model`, `tokenUsage`, `chargedCents`,
`conversationId`. Không cần cho v1.

## Endpoint không dùng

`GET /api/usage?user=<id>`: endpoint premium-request đời cũ (pre token-based
pricing), luôn trả `gpt-4: {numRequests: 0, numTokens: 0}` bất kể userId đúng
hay sai vì model tính phí đã đổi sang token-based. Đừng dùng.

`POST /api/dashboard/get-user-hard-limit`, `get-current-usage-limit`: trả về
HTML của Next.js app shell thay vì JSON, tức route không tồn tại dưới dạng API
hoặc yêu cầu tham số khác chưa xác định. Không dùng cho tới khi verify lại.

`api.cursor.com/teams/*`: 404/405 khi gọi không có Basic Auth team API key,
đúng như doc, không áp dụng cho tài khoản cá nhân.

## Dữ liệu local không đủ dùng

`~/.cursor/ai-tracking/ai-code-tracking.db` (SQLite) chỉ chứa AI
code-authorship theo commit (`scored_commits`: lines added/deleted, % AI per
commit), không có token/request/quota. `~/.cursor/cli-config.json` có sẵn
`authInfo.email`, `authInfo.displayName`, `serverConfigCache.backendUrl`
(`https://api2.cursor.sh`), dùng được để hiển thị account label mà không cần
gọi network, nhưng **không dùng `authInfo.userId`** (xem bẫy JWT `sub` ở trên).
Không có file local nào thay thế được việc gọi API cho usage.

## Stability và rủi ro

| Rủi ro | Mức | Cách xử lý đề xuất |
|---|---|---|
| Không có public contract, endpoint có thể đổi bất kỳ lúc nào | Cao | DTO tolerant decode, provider-local mapper, lỗi không làm hỏng provider khác, theo đúng pattern `ClaudeUsageMapper`/`CodexUsageMapper` hiện tại |
| Hai đơn vị tiền khác nhau giữa `usage-summary` (cents) và `get-hard-limit` (dollars) | Cao nếu implement sai | Đặt tên field rõ đơn vị ngay từ mapper, không truyền float thô qua boundary mà không gắn nhãn |
| `userId` sai (dùng `authInfo.userId` thay vì JWT `sub`) fail silent, trả `200` với data toàn 0 | Cao | Luôn tự decode `sub` từ JWT tại provider, không đọc `cli-config.json` cho việc này |
| JWT hết hạn ~60 ngày, chưa verify refresh flow | Trung bình | v1 coi hết hạn là `authenticationRequired`, không tự refresh cho tới khi luồng refresh được verify riêng |
| Token count là string trong JSON, không phải number | Thấp | Decode tolerant kiểu `LosslessStringConvertible` như Codex đã làm với field số |
| Đọc Keychain item do Cursor sở hữu (không phải app tự tạo) | Cao, giống Claude Code | Chỉ đọc, không ghi/xóa/refresh token của Cursor; không log payload |

## Mapping đề xuất sang model chung (chưa implement)

Theo đúng pattern `UsageSnapshot`/`UsageMetric` đang dùng cho Claude Code và
Codex:

```text
providerID     = .cursor (cần thêm case mới vào ProviderID)
metric cents   → auto/api/on-demand đều nên chuẩn hoá về usedValue tính theo
                 dollar trước khi vào UsageMetric (unit: "USD"), tránh rò rỉ
                 đơn vị cents ra UI layer
usedPercent    = plan.autoPercentUsed / plan.apiPercentUsed / on-demand tự tính
                 từ used/limit (không có percent field sẵn cho on-demand)
resetsAt       = billingCycleEnd
windowDuration = billingCycleEnd - billingCycleStart
```

`onDemand` không có percent field có sẵn trong payload. Nếu hiển thị percent,
phải tự tính `used/limit` và làm rõ đây là suy ra, không phải field gốc từ
Cursor.

## Việc chưa làm

- Chưa implement `CursorProvider` (theo `UsageProvider` protocol), chưa thêm
  `ProviderID.cursor`, chưa có mapper, chưa có test fixture.
- Chưa verify JWT refresh flow khi access token hết hạn.
- Chưa xác định vì sao `get-user-hard-limit`/`get-current-usage-limit` trả
  HTML thay vì JSON, có thể cần header hoặc method khác.
- Chưa quyết định UX khi user không cài Cursor hoặc chưa login (tương tự
  `configurationStatus()` của Codex/Claude).
