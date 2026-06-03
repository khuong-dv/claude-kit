# claude-kit

Local **Claude Code plugin marketplace** chứa các plugin tự viết phục vụ workflow
hằng ngày. Repo này tự bản thân nó là marketplace — không phải plugin — và mỗi
plugin con sống dưới `plugins/<name>/`.

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
└── README.md                     # ← file này
```

`marketplace.json` ở root liệt kê tất cả plugin con; mỗi entry trỏ tới một thư
mục con qua `source: "./plugins/<name>"`. Thêm plugin mới = thêm thư mục con +
append entry vào mảng `plugins`.

## Install marketplace

Trong Claude Code:

```
/plugin marketplace add /home/khuongdv/Documents/claude-kit
/plugin install pr-review@claude-kit
```

Sau khi cài, kiểm tra:

```
/plugin list
```

Để pick up edits không cần restart session: `/plugin reload <name>`.

## Plugins

### pr-review (v0.1.0)

Preflight wrapper quanh plugin chính thức `code-review` (`anthropics/claude-code`).

- **Skill `pr-review:review`** — auto-trigger khi user paste PR URL/SHA/branch
  hoặc nói "review/code review/check this PR". Thu thập rule review + ticket
  context qua `AskUserQuestion`, hỏi cách surface findings (terminal /
  `--comment` / submit PR review), rồi dispatch `/code-review:code-review`.
  Mode "Submit as PR review" là wrapper-side: gom findings của upstream thành
  một `POST /repos/.../pulls/.../reviews` qua `gh api`.
- **Command `/pr-review:check-code-review-updates`** — so phiên bản pinned của
  `code-review` với upstream, spawn sub-agent diff & phân loại breaking change,
  in ra các bước re-pin thủ công. Không tự update.
- **SessionStart hook** — cảnh báo một dòng nếu pinned version drift khỏi
  marketplace upstream. Im lặng khi match hoặc lỗi network. Opt-out:
  `export PR_REVIEW_DISABLE_UPDATE_WARN=1`.

Chi tiết đầy đủ: [`plugins/pr-review/README.md`](plugins/pr-review/README.md).

## Pattern: pinning upstream plugins

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
4. Reload marketplace trong Claude Code: `/plugin marketplace update claude-kit`
   (hoặc `/plugin marketplace remove` + `add` lại).
5. Install: `/plugin install <name>@claude-kit`.

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
