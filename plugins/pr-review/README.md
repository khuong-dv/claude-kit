# pr-review

A plugin in the `claude-kit` local marketplace. Bundles a preflight wrapper
around the official `code-review` plugin plus a guarded update-check workflow
for the pinned upstream version.

What's included:

- **Skill `pr-review:review`** — Preflight wrapper around the official `code-review` plugin. Collects review rules + requirement/ticket context (via `AskUserQuestion`) and asks whether to forward `--comment` to upstream, then dispatches `/code-review:code-review` with the enriched input.
- **Command `/pr-review:check-code-review-updates`** — Compares the pinned upstream `code-review` plugin against the latest version on GitHub. Spawns an agent to review breaking changes and prints manual re-pin steps. Never updates anything on its own.
- **SessionStart hook** — One-line warning when the pinned upstream version drifts from the official marketplace. Silent on match, silent on network failure. Opt-out via env var.

## Layout

```
plugins/pr-review/
├── .claude-plugin/plugin.json          # pin block lives here
├── README.md
├── skills/review/
│   ├── SKILL.md                        # pr-review:review
│   └── references/review.md            # default rule set
├── commands/
│   └── check-code-review-updates.md    # /pr-review:check-code-review-updates
├── agents/
│   └── code-review-update-reviewer.md  # spawned by the command above
├── hooks/
│   ├── hooks.json                      # SessionStart entry
│   └── check-update.sh                 # warn-only script
└── state/code-review-pinned/
    ├── MANIFEST.json
    └── commands/code-review.md         # snapshot at pinned version
```

## Install (local marketplace)

The `claude-kit` repo is the marketplace; this plugin lives under it. To make
Claude Code load it, register the repo as a local marketplace and enable the
plugin.

```bash
# In Claude Code
/plugin marketplace add /home/khuongdv/Documents/claude-kit
/plugin install pr-review
```

If you prefer file-based config instead, point your user-level Claude Code
settings (`~/.claude/settings.json`) at the local marketplace. The shape and
exact keys evolve — when in doubt use `/plugin` and let it write the config.

To pick up edits without restarting, run `/plugin reload pr-review` (or
reload the session).

## Usage

### Run a code review

Just say what you want to review — a PR URL, PR number, commit SHA, or branch:

> `review PR #142, ticket PROJ-558 — add validation for email and phone`

The `pr-review:review` skill triggers automatically, collects context, then
dispatches `/code-review:code-review` from the official plugin. You do not
need to invoke the skill explicitly.

The skill asks **at most two questions** via the `AskUserQuestion` tool:

1. **Ticket context** — paste description, ticket link, extract from PR
   description, or skip. Skipped if you already provided ticket info inline.
2. **Post comments?** — print findings to terminal only (default), or pass
   `--comment` to the upstream command so it posts inline comments on the PR.
   Only asked when the input is a PR; skipped for commits/branches. Also
   skipped if you said so in your original message (e.g. "and post comments"
   or "just print, don't comment").

To avoid both prompts, include the answers in your initial message:

> `review PR #142, ticket PROJ-558 — add validation for email/phone. Post the comments.`

If you haven't installed the official `code-review` plugin, this chain will
not work — install it from the bundled marketplace:

```
/plugin install code-review
```

#### Supported upstream flags

These flags are interpreted by the upstream `/code-review:code-review` command.
`pr-review:review` only asks and forwards them — it does not change semantics.

- **No flag (default)** — Print summary of findings to the terminal. Nothing is posted to GitHub.
- **`--comment`** — If issues are found, upstream posts inline comments on the PR. If no issues are found, upstream posts a single summary comment via `gh pr comment`. Only meaningful when the input is a PR.

The list above reflects the **pinned** upstream version. When upstream gains
or removes flags, `/pr-review:check-code-review-updates` surfaces the diff;
update `skills/review/SKILL.md` and this README in lockstep.

### Check for upstream updates

```
/pr-review:check-code-review-updates
```

This:

1. Reads the pinned version from `.claude-plugin/plugin.json`.
2. Fetches the latest version from the official marketplace.
3. If the versions differ, fetches the current upstream files, diffs against
   the local snapshot, and spawns a sub-agent to report breaking changes.
4. Prints manual re-pin steps. It will **not** update anything itself.

### Silence the SessionStart warning

If the warning is noisy and you don't want to update right now:

```bash
export PR_REVIEW_DISABLE_UPDATE_WARN=1
```

Add it to your shell rc (`~/.bashrc` / `~/.zshrc`) to make it permanent.

## How the pin works

`plugin.json` has a `pinned` block:

```json
{
  "pinned": {
    "code-review": {
      "version": "1.0.0",
      "source": "https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json"
    }
  }
}
```

The SessionStart hook reads this, fetches the marketplace JSON, and warns if
any pinned `version` differs from upstream.

`state/code-review-pinned/MANIFEST.json` tracks which upstream files were
snapshotted at pin time. The check command diffs against that snapshot.

When accepting an upstream update, three things must move together:
1. `plugin.json` — bump `pinned["code-review"].version`.
2. `state/code-review-pinned/MANIFEST.json` — bump `pinnedVersion`, update
   `pinnedAt`.
3. `state/code-review-pinned/commands/code-review.md` (and any other tracked
   files) — replace with the new upstream content.

The check command prints these exact steps after a review.

## Extending

**Within this plugin** (more review-flavored skills, e.g. design review, doc
review):

- Add `skills/<name>/SKILL.md` → invocable as `pr-review:<name>`.
- Add `commands/<name>.md` → invocable as `/pr-review:<name>`.
- Add `agents/<name>.md` if a sub-agent is needed.

**As a separate plugin** (non-review domains, e.g. commit workflow, deploy
preflight):

- Create `claude-kit/plugins/<other-plugin>/` with its own `.claude-plugin/plugin.json`.

**To track another official plugin as a pinned dependency** (same pattern as
`code-review`):

1. Add an entry under `pinned` in `plugin.json`.
2. Add the relevant files (paths + remote URLs) to `state/<plugin>-pinned/MANIFEST.json`.
3. Snapshot the files under `state/<plugin>-pinned/`.
4. Generalize the check command to loop over multiple pinned plugins.
