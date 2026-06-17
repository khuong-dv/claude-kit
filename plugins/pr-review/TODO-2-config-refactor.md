# TODO 2 — Refactor config pr-review (`.env` + scoped resolve)

## Mục tiêu
Hiện tại khi chạy review, `pr-review:review` dùng `AskUserQuestion` để hỏi
**cách** cung cấp requirement (paste mô tả / paste link / extract từ PR /
skip) — mỗi lần đều phải chọn lại.

Sau refactor: nếu đã có config provider phù hợp, skill chỉ hỏi **đúng 1
thứ — ID** (ticket key, gh issue number, Linear key…), rồi tự fetch
title + description từ Jira / Backlog / GitHub Issues / Linear. Không có
config → giữ nguyên flow hỏi cách cung cấp như cũ.

## Vấn đề hiện tại
- Config = `pr-review.config.json` (user `~/.claude/` hoặc project `.claude/`).
- Secrets sống tách rời ở shell rc (`~/.bashrc` export env var) — config chỉ
  giữ **tên** env var. Hai nguồn truth → setup lần đầu rối, dễ "config có mà
  fetch vẫn skip" do quên export.
- Scope merge là per-provider key (project override user theo từng provider),
  nhưng chưa có cơ chế **disable** một provider của user-level ở project cụ
  thể (vd: global bật GitHub repo A, project X muốn chỉ dùng Backlog, không
  muốn GitHub leak ra).

## Hướng đi đề xuất

### 1. Đổi storage: `.env` style thay vì `.config.json`
- Gộp baseUrl + token vào **1 file `.env`** duy nhất per scope:
  - User: `~/.claude/pr-review.env`
  - Project: `<repo>/.claude/pr-review.env` (gitignore mặc định)
- Format đơn giản, KHÔNG cần JSON parser, dễ verify bằng mắt:
  ```
  PR_REVIEW_JIRA_BASE_URL=https://org.atlassian.net
  PR_REVIEW_JIRA_EMAIL=me@x.com
  PR_REVIEW_JIRA_TOKEN=...
  PR_REVIEW_BACKLOG_BASE_URL=https://space.backlog.jp
  PR_REVIEW_BACKLOG_API_KEY=...
  PR_REVIEW_GITHUB_ENABLED=1
  PR_REVIEW_LINEAR_API_KEY=...
  PR_REVIEW_LINEAR_PREFER=mcp
  ```
- Skill source file này ở Step 2a (không export ra shell cha) → khắc phục
  vấn đề "quên `source ~/.bashrc`".

### 2. Scope rõ ràng — explicit, không implicit merge
Mô hình 3 tầng, ưu tiên từ cao xuống thấp:

- **Project** — `<repo>/.claude/pr-review.env` — override / khai báo provider riêng project.
- **User** — `~/.claude/pr-review.env` — default cá nhân, áp cho mọi repo.
- **Shell** — env var đã export sẵn — escape hatch / CI.

Quy tắc resolve cho **1 provider** (vd `jira`):
1. Project file có set `PR_REVIEW_JIRA_*` → dùng project.
2. Project file có `PR_REVIEW_JIRA_DISABLED=1` → tắt jira ở project này
   (kể cả khi user có config). ← giải quyết case "global GitHub, project
   chỉ Backlog".
3. Không có gì ở project → fallback user-level.
4. Shell env có sẵn → win nếu file không cover (CI / one-off).

Active provider list = union các provider có đủ env var **và** không bị
`*_DISABLED=1` ở scope cao hơn.

### 3. Migration từ `.config.json` cũ
- Wizard `/pr-review:setup-tickets` detect file `.config.json` cũ → hỏi user
  có muốn migrate sang `.env` không, dry-run in diff trước khi ghi.
- Giữ backward-compat đọc `.config.json` thêm 1 version rồi remove (note
  trong README + warning một dòng khi load).

## Open questions cần KhuongDV quyết
- [ ] `.env` ở project có nên auto-add vào `.gitignore` không? (Có secret → có.)
- [ ] Có muốn 1 lệnh `/pr-review:doctor` in bảng "scope nào set provider nào,
      env var nào thiếu" để debug nhanh không?
- [ ] Có cần hỗ trợ multiple Jira/Backlog instance per scope (vd company A +
      personal) hay 1 instance / provider là đủ?
- [ ] Có giữ `prefer: "mcp"` flag không, hay luôn "MCP trước nếu connected,
      REST sau"?

## Task list (sau khi chốt design)
- [ ] Cập nhật spec `skills/review/references/ticket-providers.md`:
      schema `.env`, rule scope 3 tầng, rule `*_DISABLED`.
- [ ] Sửa `commands/setup-tickets.md`: wizard ghi `.env`, hỗ trợ migrate từ
      `.config.json`, in hướng dẫn gitignore.
- [ ] Sửa `skills/review/SKILL.md` Step 2a: load `.env` (user + project),
      resolve theo scope, không touch shell env cha.
- [ ] Thêm `/pr-review:doctor` (nếu chốt làm) để in trạng thái resolve.
- [ ] Update README (root + plugin) phần "Ticket providers" + ví dụ scope.
- [ ] Smoke test: project-only Backlog, user-only GitHub, mixed với disable.
