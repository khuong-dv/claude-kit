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
