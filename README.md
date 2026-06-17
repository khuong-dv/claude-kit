# claude-kit

> 🇻🇳 Tiếng Việt · [🇬🇧 English](./README.en.md)

Bộ kit customize các plugin, extension phục vụ cho Claude Code.

## Layout

```
claude-kit/
├── .claude-plugin/
│   └── marketplace.json          # manifest marketplace (entry point cho /plugin marketplace add)
├── plugins/
│   └── pr-review/                # plugin con — preflight cho /code-review:code-review
│       ├── .claude-plugin/plugin.json
│       ├── README.md
│       ├── skills/review/        # skill pr-review:review
│       ├── commands/             # /pr-review:check-code-review-updates
│       ├── agents/               # sub-agent cho update check
│       ├── hooks/                # SessionStart warning hook
│       └── state/code-review-pinned/   # snapshot của upstream tại version đã pin
├── README.md                     # ← file này (tiếng Việt)
└── README.en.md                  # bản tiếng Anh
```

`marketplace.json` ở root liệt kê tất cả plugin con; mỗi entry trỏ tới một thư
mục con qua `source: "./plugins/<name>"`. Thêm plugin mới = thêm thư mục con +
append entry vào mảng `plugins`.

## Plugins

Mỗi plugin có mục riêng bên dưới với tóm tắt, hướng dẫn cài, và danh sách
tính năng. Khi thêm plugin mới, copy template section này (xem
[Thêm plugin mới](#thêm-plugin-mới)).

## Plugin: pr-review (v0.2.0)

Preflight wrapper quanh plugin chính thức `code-review`
(`anthropics/claude-code`). Tự thu thập rule review + ticket context, rồi
chạy snapshot đã pin của `code-review` inline; có thể gom findings thành 1
unified GitHub PR review.

### Cài đặt

Có hai cách dùng marketplace này trong Claude Code.

#### Cách 1 — Cài trực tiếp từ GitHub (khuyên dùng)

Không cần clone, Claude Code tự fetch và cache repo. Chạy **hai lệnh dưới đây
lần lượt**, không paste cả hai cùng lúc.

**Bước 1 — add marketplace:**

```
/plugin marketplace add https://github.com/khuong-dv/claude-kit
```

**Bước 2 — install plugin:**

```
/plugin install claude-kit/pr-review
```

Update về sau:

```
/plugin marketplace update claude-kit
```

#### Cách 2 — Clone về máy rồi add path local

Hợp khi bạn muốn sửa plugin và test ngay (file system trỏ thẳng tới repo
local, không cần push):

```bash
git clone https://github.com/khuong-dv/claude-kit.git
```

(clone vào path tuỳ ý — ví dụ thư mục hiện tại sẽ tạo ra `./claude-kit`)

Rồi trong Claude Code, chạy **hai lệnh dưới đây lần lượt**:

**Bước 1 — add marketplace:** (thay `<path/to/claude-kit>` bằng đường dẫn
tuyệt đối tới repo vừa clone)

```
/plugin marketplace add <path/to/claude-kit>
```

**Bước 2 — install plugin:**

```
/plugin install claude-kit/pr-review
```

Sau khi sửa file plugin, không cần restart session:

```
/plugin reload pr-review
```

#### Kiểm tra

```
/plugin list
```

### Tính năng

- **Skill `pr-review:review`** — auto-trigger khi user paste PR URL/SHA/branch
  hoặc nói "review/code review/check this PR". Thu thập rule review + ticket
  context qua `AskUserQuestion`, hỏi cách surface findings (terminal /
  `--comment` / submit PR review), rồi dispatch `/code-review:code-review`.
  Mode "Submit as PR review" là wrapper-side: gom findings của upstream thành
  một `POST /repos/.../pulls/.../reviews` qua `gh api`.
- **Ticket providers (optional, opt-in)** — fetch requirement context trực
  tiếp từ **Backlog / Jira Cloud / GitHub Issues / Linear** (REST hoặc MCP),
  luôn hỏi xác nhận trước khi gọi API ngoài; fetch fail thì fallback ghi link
  as-is. Không config thì flow review giữ nguyên 100% (không thêm prompt,
  không tốn token load spec). Setup qua `/pr-review:setup-tickets` (config
  chỉ chứa tên env var, không chứa secret).
- **Command `/pr-review:check-code-review-updates`** — so phiên bản pinned của
  `code-review` với upstream, spawn sub-agent diff & phân loại breaking change,
  in ra các bước re-pin thủ công. Không tự update.
- **SessionStart hook** — cảnh báo một dòng nếu pinned version drift khỏi
  marketplace upstream. Im lặng khi match hoặc lỗi network. Opt-out:
  `export PR_REVIEW_DISABLE_UPDATE_WARN=1`.

Chi tiết đầy đủ: [`plugins/pr-review/README.md`](plugins/pr-review/README.md).

## Pattern: pin upstream plugin

`pr-review` track plugin chính thức `code-review` theo kiểu pin có kiểm soát:

1. `plugins/pr-review/.claude-plugin/plugin.json` có block `pinned` ghi version
   + nguồn marketplace của upstream.
2. `plugins/pr-review/state/code-review-pinned/MANIFEST.json` ghi danh sách
   file upstream được snapshot + URL gốc.
3. Bản copy thực tế của các file đó nằm dưới
   `plugins/pr-review/state/code-review-pinned/<relpath>`.

Khi accept một upstream update, ba thứ phải move cùng nhau:

- Bump `pinned["<name>"].version` trong `plugin.json`.
- Bump `pinnedVersion` + `pinnedAt` trong `MANIFEST.json`.
- Replace các file snapshot trong `state/<plugin>-pinned/` bằng nội dung mới.

`/pr-review:check-code-review-updates` in ra đúng các bước này sau khi chạy
diff — không tự áp dụng.

Reuse pattern này cho plugin chính thức khác: thêm entry vào `pinned` của
plugin con, snapshot file dưới `state/<plugin>-pinned/`, và generalize lệnh
check theo cùng shape.

## Thêm plugin mới

1. `mkdir -p plugins/<name>/.claude-plugin`
2. Tạo `plugins/<name>/.claude-plugin/plugin.json` (tối thiểu: `name`,
   `version`, `description`).
3. Append entry vào `.claude-plugin/marketplace.json`:
   ```json
   {
     "name": "<name>",
     "source": "./plugins/<name>",
     "description": "...",
     "version": "0.1.0",
     "author": { "name": "khuongdv" }
   }
   ```
4. Reload marketplace trong Claude Code: `/plugin marketplace update claude-kit`.
5. Install: `/plugin install claude-kit/<name>`.

Bố cục bên trong plugin (tất cả optional, có gì khai báo nấy):

- `skills/<skill>/SKILL.md` → invocable là `<plugin>:<skill>`
- `commands/<cmd>.md` → invocable là `/<plugin>:<cmd>`
- `agents/<agent>.md` → spawn qua tool `Agent`
- `hooks/hooks.json` (+ scripts) → SessionStart / PreToolUse / v.v.
- `state/` → snapshot, manifest, dữ liệu plugin tự quản

## Tham chiếu nhanh

- Plugin marketplace schema chính thức:
  `https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json`
- Plugin `code-review` upstream được track ở pin `1.0.0` (xem
  `plugins/pr-review/state/code-review-pinned/MANIFEST.json` để biết file nào
  được snapshot).
