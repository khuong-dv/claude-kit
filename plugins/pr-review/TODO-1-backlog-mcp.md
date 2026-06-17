# TODO 1 — Tích hợp Backlog MCP (`nulab/backlog-mcp-server`)

> Ưu tiên cao: công ty chủ yếu dùng Backlog → cần MCP-first cho provider
> `backlog` trong `pr-review:review`.

## Tham chiếu
- Repo: <https://github.com/nulab/backlog-mcp-server>
- Auth: `BACKLOG_DOMAIN` + `BACKLOG_API_KEY` (OAuth chỉ cần khi host remote — bỏ qua).
- Transport: stdio (default) — đúng cái Claude Code dùng.
- Tool cần cho review: `get_issue` (title + description). Toolset filter:
  `ENABLE_TOOLSETS="issue,project"` để giảm context.

## Phase 1 — Manual setup, chưa đụng code plugin
- [ ] Export env (user shell rc):
      `BACKLOG_DOMAIN`, `BACKLOG_API_KEY`.
- [ ] Register MCP user-scope (cả công ty 1 space):
      ```
      claude mcp add backlog --scope user \
        -e BACKLOG_DOMAIN="$BACKLOG_DOMAIN" \
        -e BACKLOG_API_KEY="$BACKLOG_API_KEY" \
        -e ENABLE_TOOLSETS="issue,project" \
        -- npx -y backlog-mcp-server
      ```
- [ ] Verify: session mới → `/mcp` thấy `backlog` Connected → thử
      "fetch issue PROJ-123" qua MCP.
- [ ] Note lại tool name pattern thực tế (dự đoán `mcp__backlog__get_issue`)
      để dùng ở Phase 2.

## Phase 2 — Update spec & skill để pr-review dùng MCP
Phụ thuộc design ở [TODO 2 — Config refactor](./TODO-2-config-refactor.md).

- [ ] Sửa `skills/review/references/ticket-providers.md`:
      Backlog có MCP path (`prefer: "mcp"`), tool pattern `mcp__backlog__*`,
      REST làm fallback (mirror cấu trúc Jira/Linear).
- [ ] Mở rộng schema config (theo TODO 2):
      ```
      PR_REVIEW_BACKLOG_BASE_URL=https://yourspace.backlog.com
      PR_REVIEW_BACKLOG_PREFER=mcp        # mcp | rest
      PR_REVIEW_BACKLOG_API_KEY=          # chỉ cần khi prefer=rest hoặc MCP fail
      ```
- [ ] Wizard `/pr-review:setup-tickets`: hỏi "Backlog REST hay MCP?";
      chọn MCP → in lệnh `claude mcp add backlog ...` (không tự chạy).
- [ ] Skill Step 2a: nếu `mcp__backlog__get_issue` available và
      `prefer=mcp` → gọi MCP; fail → REST fallback nếu có.

## Phase 3 — Optional
- [ ] `/pr-review:doctor` in trạng thái MCP/REST cho từng provider.

## Open questions cần KhuongDV chốt trước Phase 1
- [ ] `npx` hay `Docker`? (npx đơn giản, Docker isolation tốt hơn.)
- [ ] User-scope MCP đủ chưa, hay có dự án client dùng Backlog space khác
      → cần project-scope override?
- [ ] Env Backlog nên ở `~/.bashrc` (share cho terminal khác) hay nhét
      thẳng vào MCP config (Claude-only, gọn hơn)?
