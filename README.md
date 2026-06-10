# claude-kit

> 🇻🇳 Tiếng Việt · [🇬🇧 English](./README.en.md)

Local **Claude Code plugin marketplace** chứa các plugin tự viết phục vụ
workflow hằng ngày. Repo này tự bản thân nó là marketplace — không phải plugin
— và mỗi plugin con sống dưới `plugins/<name>/`.

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

## Install

Có hai cách dùng marketplace này trong Claude Code.

### Cách 1 — Cài trực tiếp từ GitHub (khuyên dùng)

Không cần clone, Claude Code tự fetch và cache repo. Chạy **hai lệnh dưới đây
lần lượt**, không paste cả hai cùng lúc.

**Bước 1 — add marketplace:**

```
/plugin marketplace add https://github.com/khuong-dv/claude-kit
```

Chờ thông báo `Added marketplace ...` rồi mới sang bước 2. ⚠️ Nếu paste cả
hai dòng cùng lúc, `/plugin marketplace add` sẽ nuốt dòng kế tiếp làm một
phần URL và clone fail với `Malformed input to a URL function`.

**Bước 2 — install plugin:**

```
/plugin install claude-kit/pr-review
```

Update về sau:

```
/plugin marketplace update claude-kit
```

### Cách 2 — Clone về máy rồi add path local

Hợp khi bạn muốn sửa plugin và test ngay (file system trỏ thẳng tới repo
local, không cần push):

```bash
git clone https://github.com/khuong-dv/claude-kit.git ~/Documents/claude-kit
```

Rồi trong Claude Code, chạy **hai lệnh dưới đây lần lượt** (xem cảnh báo ở
Cách 1):

**Bước 1 — add marketplace:**

```
/plugin marketplace add ~/Documents/claude-kit
```

**Bước 2 — install plugin:**

```
/plugin install claude-kit/pr-review
```

Sau khi sửa file plugin, không cần restart session:

```
/plugin reload pr-review
```

### Kiểm tra

```
/plugin list
```

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
