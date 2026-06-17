# claude-kit

> [🇻🇳 Tiếng Việt](./README.md) · 🇬🇧 English

A kit of custom plugins and extensions for Claude Code.

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

## Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [**pr-review**](plugins/pr-review/README.md) | v0.2.0 | Preflight wrapper around the official `code-review` plugin. Gathers review rules + ticket context, runs the pinned `code-review` snapshot inline, and can bundle findings into one unified GitHub PR review. |

Click the plugin name for the full description, install instructions, and usage.

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
