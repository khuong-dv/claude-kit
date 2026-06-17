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

| Plugin | Version | Mô tả |
|--------|---------|-------|
| [**pr-review**](plugins/pr-review/README.md) | v0.2.0 | Preflight wrapper quanh plugin chính thức `code-review`. Tự thu thập rule review + ticket context, chạy snapshot pinned của `code-review` inline; có thể gom findings thành 1 unified GitHub PR review. |

Click vào tên plugin để xem mô tả đầy đủ, hướng dẫn cài đặt, và cách dùng.

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
