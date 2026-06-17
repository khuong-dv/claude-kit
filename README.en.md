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
