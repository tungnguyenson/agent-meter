# Implementation plan: multi-provider Agent Meter

## Nguyên tắc thực hiện

Thực hiện TDD theo từng phase: viết test fail, implementation tối thiểu để pass,
refactor, rồi chạy lại suite. Không publish release trong plan này. Giữ Git
history hiện tại khi đổi remote/rebrand và không đưa secret/PII vào fixture.

## Phase 1. Core contract và Claude adapter

1. Viết test cho normalized models, unknown provider/metric values, percentage
   và value/limit metric.
2. Tạo provider protocol, metadata, snapshot/metric model và error taxonomy.
3. Viết mapper tests từ `UsageData` hiện tại sang snapshot động, gồm missing
   fields, fractional utilization, ISO dates và extra usage.
4. Bọc Claude keychain/OAuth/web/cache hiện tại sau `ClaudeCodeProvider`, chưa đổi
   UX.
5. Chạy regression suite để chứng minh Claude behavior không đổi.

Exit criteria: toàn bộ Claude fetch đi qua provider contract; app vẫn hiển thị
đúng dữ liệu hiện tại.

## Phase 2. Codex app-server client

1. Tạo fake JSONL process harness và test handshake, request IDs, concurrent
   responses, notification, malformed line, stderr, timeout và process exit.
2. Implement binary resolver và version preflight, không qua shell.
3. Implement long-lived process, `initialize`/`initialized`, pending-call table
   và cancellation-safe shutdown.
4. Viết DTO/mapper tests cho:
   - account/auth/plan;
   - single và multi-limit collections;
   - primary/secondary windows;
   - Unix-second reset;
   - credits, individual limit và spend control;
   - missing/unknown fields.
5. Implement read calls; `account/usage/read` là best-effort.
6. Test sparse update merge: absent/null metadata không xóa snapshot; ambiguous
   update kích hoạt refetch.
7. Implement bounded exponential restart backoff.

Exit criteria: fixture integration test trả Codex snapshot; live smoke trên
ChatGPT-authenticated CLI `>=0.146.0` trả ít nhất một quota window. Nếu live smoke
không đạt, dừng Codex rollout và ghi exact blocker; không scrape dashboard.

## Phase 3. Multi-provider coordinator

1. Viết tests cho refresh song song, partial success, provider-isolated cache,
   stale state, auth gate, `429` cooldown và subprocess backoff.
2. Thay singleton Claude usage state bằng coordinator keyed theo provider.
3. Cache v2 snapshot/cooldown theo provider; decode failure của một entry không
   làm mất entry khác.
4. Namespace notification state bằng provider + metric + threshold.
5. Forecast chỉ áp dụng cho metric đủ dữ liệu.

Exit criteria: một provider liên tục lỗi nhưng provider còn lại vẫn refresh,
notify và render từ state riêng.

## Phase 4. Settings migration và security hardening

1. Viết migration tests từ settings/cache v1, gồm rerun idempotency và partial
   Keychain failure.
2. Implement settings v2: enabled/selected providers, visibility, tối đa hai pin.
3. Migrate global Claude preferences và legacy cache.
4. Chuyển Claude `sessionKey` sang Agent Meter-owned Keychain; chỉ xóa legacy
   value sau write thành công.
5. Redact diagnostic; loại raw credential/PII response logging.
6. Security tests cho executable path/argv, log redaction và cache/settings
   serialization không chứa secret.

Exit criteria: tìm kiếm UserDefaults/cache/log fixture không thấy token, cookie,
email hoặc account ID; migration không làm mất secret nếu Keychain write fail.

## Phase 5. UX và rebrand

1. Viết view-model tests cho picker, dynamic cards, unsupported/auth/error/stale
   states và pin fallback.
2. Rework popover thành Agent Meter với provider picker và health/last updated.
3. Rework menu bar cho selected provider và tối đa hai metric động; giữ Icon,
   Compact, Detailed và fixed/countdown style.
4. Chia Settings thành global và provider sections; web fallback Claude mang
   nhãn Experimental.
5. Rebrand target/scheme/app/cache/defaults/DMG/docs sang Agent Meter, bundle ID
   `com.agentmeter.app`; giữ compatibility migration với legacy keys/path.
6. Giữ Git history, đổi `origin` sang
   `git@github.com:tungnguyenson/agent-meter.git` sau khi code/tests ổn định.

Exit criteria: critical UI flow dùng được với Claude và Codex cùng enabled;
đã loại bỏ ClaudeMeter branding, giữ lại chỉ migration/legacy compatibility code.

## Verification và review

Chạy tối thiểu:

```bash
xcodebuild test -project AgentMeter.xcodeproj \
  -scheme AgentMeter \
  -destination 'platform=macOS'
```

Nếu rebrand chưa hoàn tất ở phase đang chạy, dùng project/scheme cũ nhưng ghi rõ
boundary. Sau đó:

1. Báo coverage và bổ sung test để đạt tối thiểu 80%.
2. Chạy general code review và Swift-specific review.
3. Bắt buộc security review vì có credential, filesystem, subprocess và external
   API boundary.
4. Sửa mọi CRITICAL/HIGH; sửa MEDIUM khi không làm rộng scope.
5. Kiểm tra không có hardcoded secret, debug print/raw response, deep nesting,
   function >50 dòng hoặc file >800 dòng mới.
6. Live smoke cả Claude và Codex; static test không thay thế runtime acceptance.

## Rollout boundary

- Không deploy, notarize, tạo GitHub release hay redeem credit.
- Chỉ tạo draft PR sau khi test, coverage và review đạt yêu cầu.
- Codex provider có thể ship dưới feature flag nếu app-server compatibility cần
  thêm soak time; Claude provider vẫn là default sau migration.
- Nếu upstream contract fail, disable riêng provider và giữ cached snapshot với
  trạng thái degraded; không đổi sang private endpoint khác ngoài spec.

