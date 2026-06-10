# claude-kit

> [🇻🇳 Tiếng Việt](./README.md) · 🇬🇧 English

A local **Claude Code plugin marketplace** holding custom plugins for daily
workflow. This repo *is* the marketplace — not a plugin itself — and each
child plugin lives under `plugins/<name>/`.

## Layout

```
claude-kit/
├── .claude-plugin/
│   └── marketplace.json          # marketplace manifest (entry point for /plugin marketplace add)
├── plugins/
│   └── pr-review/                # child plugin — preflight for /code-review:code-review
│       ├── .claude-plugin/plugin.json
│       ├── README.md
│       ├── skills/review/        # pr-review:review skill
│       ├── commands/             # /pr-review:check-code-review-updates
│       ├── agents/               # sub-agent for update check
│       ├── hooks/                # SessionStart warning hook
│       └── state/code-review-pinned/   # snapshot of upstream at the pinned version
├── README.md                     # Vietnamese version
└── README.en.md                  # ← this file (English)
```

The root `marketplace.json` lists every child plugin; each entry points at a
subdirectory via `source: "./plugins/<name>"`. Adding a new plugin = adding a
subdirectory + appending an entry to the `plugins` array.

## Install

Two ways to use this marketplace inside Claude Code.

### Option 1 — Install directly from GitHub (recommended)

No clone needed; Claude Code fetches and caches the repo for you. Run the
**two commands below one at a time** — do not paste them together.

**Step 1 — add the marketplace:**

```
/plugin marketplace add https://github.com/khuong-dv/claude-kit
```

Wait for `Added marketplace ...` before running step 2. ⚠️ If you paste both
lines at once, `/plugin marketplace add` will swallow the next line as part
of the URL and the clone fails with `Malformed input to a URL function`.

**Step 2 — install the plugin:**

```
/plugin install claude-kit/pr-review
```

Pull updates later:

```
/plugin marketplace update claude-kit
```

### Option 2 — Clone locally, then add the path

Useful when you want to edit plugins and test them immediately (the
filesystem points straight at your local repo, no push required):

```bash
git clone https://github.com/khuong-dv/claude-kit.git ~/Documents/claude-kit
```

Then in Claude Code, run the **two commands one at a time** (same caveat as
Option 1):

**Step 1 — add the marketplace:**

```
/plugin marketplace add ~/Documents/claude-kit
```

**Step 2 — install the plugin:**

```
/plugin install claude-kit/pr-review
```

After editing plugin files, no session restart needed:

```
/plugin reload pr-review
```

### Verify

```
/plugin list
```

## Plugins

### pr-review (v0.1.0)

Preflight wrapper around the official `code-review` plugin
(`anthropics/claude-code`).

- **Skill `pr-review:review`** — auto-triggers when the user pastes a PR
  URL/SHA/branch or says "review/code review/check this PR". Gathers review
  rules + ticket context via `AskUserQuestion`, asks how findings should be
  surfaced (terminal / `--comment` / submit as PR review), then dispatches
  `/code-review:code-review`. The "Submit as PR review" mode is wrapper-side:
  it bundles upstream's findings into one
  `POST /repos/.../pulls/.../reviews` call via `gh api`.
- **Command `/pr-review:check-code-review-updates`** — compares the pinned
  version of `code-review` against upstream, spawns a sub-agent to diff and
  classify breaking changes, and prints manual re-pin steps. Never auto-updates.
- **SessionStart hook** — one-line warning when the pinned version drifts
  from the upstream marketplace. Silent on match or network error. Opt-out:
  `export PR_REVIEW_DISABLE_UPDATE_WARN=1`.

Full details: [`plugins/pr-review/README.md`](plugins/pr-review/README.md).

## Pattern: pinning an upstream plugin

`pr-review` tracks the official `code-review` plugin via a controlled pin:

1. `plugins/pr-review/.claude-plugin/plugin.json` has a `pinned` block
   recording the version + the upstream marketplace source.
2. `plugins/pr-review/state/code-review-pinned/MANIFEST.json` lists which
   upstream files were snapshotted + their source URLs.
3. The actual file copies live under
   `plugins/pr-review/state/code-review-pinned/<relpath>`.

When accepting an upstream update, three things must move together:

- Bump `pinned["<name>"].version` in `plugin.json`.
- Bump `pinnedVersion` + `pinnedAt` in `MANIFEST.json`.
- Replace the snapshot files under `state/<plugin>-pinned/` with the new
  upstream content.

`/pr-review:check-code-review-updates` prints exactly these steps after
running the diff — it never applies them itself.

Reuse this pattern for other official plugins: add an entry under `pinned`
in the child plugin, snapshot the files under `state/<plugin>-pinned/`, and
generalize the check command to the same shape.

## Adding a new plugin

1. `mkdir -p plugins/<name>/.claude-plugin`
2. Create `plugins/<name>/.claude-plugin/plugin.json` (at minimum: `name`,
   `version`, `description`).
3. Append an entry to `.claude-plugin/marketplace.json`:
   ```json
   {
     "name": "<name>",
     "source": "./plugins/<name>",
     "description": "...",
     "version": "0.1.0",
     "author": { "name": "khuongdv" }
   }
   ```
4. Reload the marketplace in Claude Code:
   `/plugin marketplace update claude-kit`.
5. Install: `/plugin install claude-kit/<name>`.

Layout inside a plugin (all optional — declare only what you use):

- `skills/<skill>/SKILL.md` → invocable as `<plugin>:<skill>`
- `commands/<cmd>.md` → invocable as `/<plugin>:<cmd>`
- `agents/<agent>.md` → spawned via the `Agent` tool
- `hooks/hooks.json` (+ scripts) → SessionStart / PreToolUse / etc.
- `state/` → snapshots, manifests, plugin-managed data

## Quick references

- Official plugin marketplace schema:
  `https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json`
- The upstream `code-review` plugin is tracked at pin `1.0.0` (see
  `plugins/pr-review/state/code-review-pinned/MANIFEST.json` for the
  snapshotted file list).
