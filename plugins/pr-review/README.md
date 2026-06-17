# pr-review

A plugin in the `claude-kit` local marketplace. Self-contained PR review
workflow: bundles a pinned snapshot of the official `code-review` workflow
and executes it inline (no chain to a separately-installed plugin), and adds
a "submit as a unified GitHub PR review" mode on top. Ships with a guarded
drift-check workflow so the pinned snapshot can be re-pinned deliberately
when upstream changes.

What's included:

- **Skill `pr-review:review`** — Self-contained PR review entrypoint. Collects review rules + requirement/ticket context (via `AskUserQuestion`) and asks how to surface findings: **terminal only**, **`--comment` (inline + summary)**, or **submit as a unified GitHub PR review** (wrapper-side, via `gh api`). Then executes the bundled pinned snapshot of the code-review workflow inline; in submit-review mode, posts the batched review after findings are produced. Auto-triggers on natural language (e.g. "review PR #142").
- **Command `/pr-review:review`** — Thin slash-command wrapper around the skill above. Same behavior; exists so the entrypoint also shows in the `/` menu when you prefer explicit invocation over auto-trigger.
- **Ticket-provider fetching** — Step 2 of the review skill can pull requirement context straight from **Backlog, Jira Cloud, GitHub Issues, or Linear** (REST or MCP), always after an explicit confirmation prompt. Configure via `/pr-review:setup-tickets`; spec in `skills/review/references/ticket-providers.md`.
- **Command `/pr-review:setup-tickets`** — Interactive wizard that writes `pr-review.config.json` (user- or project-level) with provider base URLs + env var names (never secrets) and prints env var / MCP setup instructions.
- **Command `/pr-review:check-code-review-updates`** — Compares the pinned `code-review` snapshot under `state/` against the latest version on GitHub. Spawns an agent to review breaking changes and prints manual re-pin steps. Never updates anything on its own.
- **SessionStart hook** — One-line warning when the pinned snapshot version drifts from the official marketplace. Silent on match, silent on network failure. Opt-out via env var.

## Layout

```
plugins/pr-review/
├── .claude-plugin/plugin.json          # pin block lives here
├── README.md
├── skills/review/
│   ├── SKILL.md                        # pr-review:review
│   └── references/
│       ├── review.md                   # default rule set
│       └── ticket-providers.md         # Backlog/Jira/GitHub/Linear fetch spec
├── commands/
│   ├── review.md                       # /pr-review:review (wraps the skill)
│   ├── setup-tickets.md                # /pr-review:setup-tickets (provider config wizard)
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

## Install

`pr-review` ships as part of the [`claude-kit`](../../README.md) marketplace.
Two ways to install it in Claude Code.

### Option 1 — Install directly from GitHub (recommended)

No clone needed; Claude Code fetches and caches the repo for you. Run the
**two commands below one at a time** — do not paste them together.

**Step 1 — add the marketplace:**

```
/plugin marketplace add https://github.com/khuong-dv/claude-kit
```

**Step 2 — install the plugin:**

```
/plugin install claude-kit/pr-review
```

Pull updates later:

```
/plugin marketplace update claude-kit
```

### Option 2 — Clone locally, then add the path

Useful when you want to edit the plugin and test changes immediately (the
filesystem points straight at your local repo, no push required):

```bash
git clone https://github.com/khuong-dv/claude-kit.git
```

(clone into any path you like — running the command above in the current
directory creates `./claude-kit`)

Then in Claude Code, run the **two commands one at a time** (replace
`<path/to/claude-kit>` with the absolute path to the cloned repo):

**Step 1 — add the marketplace:**

```
/plugin marketplace add <path/to/claude-kit>
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

You should see `claude-kit/pr-review` listed as enabled.

## Usage

### Run a code review

Just say what you want to review — a PR URL, PR number, commit SHA, or branch:

> `review PR #142, ticket PROJ-558 — add validation for email and phone`

The `pr-review:review` skill triggers automatically, collects context, then
executes the **bundled pinned snapshot** of the official code-review
workflow inline. You do not need to invoke the skill explicitly, and you do
**not** need the official `code-review` plugin installed — pr-review embeds
its own pinned copy at `state/code-review-pinned/`.

The skill asks **at most two questions** via the `AskUserQuestion` tool
(plus a fetch confirmation when a configured ticket link is detected):

1. **Ticket context** — paste description, ticket link/key, extract from PR
   description, or skip. Skipped if you already provided ticket info inline.
   If your message contains a link/key matching a configured provider (see
   "Ticket providers" below), the skill asks to confirm, then fetches the
   ticket's title + description for you.
2. **How should the review findings be surfaced?** — pick one of three modes
   (see below). Only asked when the input is a PR; skipped for commits/branches.
   Also skipped if you said so in your original message (e.g. "and post the
   comments", "submit as a PR review", "just print, don't comment").

#### The three modes

- **Print only** (default) — terminal summary, nothing posted to GitHub.
- **Post inline comments (`--comment`)** — the snapshot runs with
  `--comment`, posting *individual* inline comments via
  `mcp__github_inline_comment__create_inline_comment` plus a separate
  summary via `gh pr comment`. Multiple entries in the PR feed.
- **Submit as PR review** — wrapper-side. Snapshot runs without `--comment`,
  then `pr-review:review` bundles findings into one
  `POST /repos/.../pulls/.../reviews` call via `gh api`. One unified Review
  entry on the PR. See the next subsection for details.

To avoid both prompts, include the answers in your initial message:

> `review PR #142, ticket PROJ-558 — add validation for email/phone. Submit as a PR review.`

#### Submit PR review (via `gh api`)

Instead of letting upstream post individual inline comments, this mode lets
the wrapper submit a single, unified **GitHub PR Review** — the formal
"Review" entity with a top-level body, batched inline comments, and an event
type. Consolidates feedback into one entry on the PR.

How it works:

1. The pinned snapshot runs inline (no `--comment`), so it just produces a
   terminal-style findings summary in the same conversation.
2. `pr-review:review` reads those findings, resolves the PR's
   `(owner, repo, number)`, builds a payload, and submits via
   `gh api --method POST repos/<owner>/<repo>/pulls/<number>/reviews`.
3. Findings with a clear `path:line` become inline comments; findings without
   line refs go in the review body's "Additional notes" tail.
4. The wrapper prints the created review's `html_url` on success.

Constraints / requirements:

- **PR input only.** Skipped automatically for commits and branches.
- **`gh` authentication with write scope.** Run `gh auth status` and confirm
  you see `repo` scope. If not: `gh auth refresh -s repo`. The wrapper
  surfaces 401/403/404/422 errors verbatim with a hint, but it doesn't retry.
- **Event type is hardcoded to `COMMENT`.** APPROVE / REQUEST_CHANGES have
  policy traps (GitHub forbids the PR author from APPROVE/REQUEST_CHANGES on
  their own PR → 422). If you really need them, edit
  `skills/review/SKILL.md` Step 7d.
- **The snapshot is not modified at runtime.** Step 6 reads it as-is;
  re-pinning is a deliberate workflow via `/pr-review:check-code-review-updates`.

#### Snapshot surface modes

The pinned snapshot supports two surfaces; `pr-review:review` picks one
based on the mode you chose.

- **No flag (default)** — Snapshot prints findings to the terminal. Used by both `Print only` mode and `Submit as PR review` mode (the latter does its own posting in Step 7 of the skill).
- **`--comment`** — If issues are found, the snapshot posts inline comments. If no issues are found, it posts a single summary comment via `gh pr comment`. Used by `Post inline comments` mode.

`Submit as PR review` is a **wrapper-side** mode, not a snapshot flag.

The behaviour above reflects the **pinned** version of the snapshot. When
upstream changes, `/pr-review:check-code-review-updates` surfaces the diff;
update the snapshot under `state/code-review-pinned/`, the
`pinned.code-review.version` field in `plugin.json`, and this README in
lockstep.

### Ticket providers (Backlog / Jira / GitHub Issues / Linear)

The review skill can fetch requirement context directly from a ticket
system instead of you pasting it. Supported: **Backlog (Nulab)**,
**Jira Cloud**, **GitHub Issues**, **Linear** — via REST APIs, or via MCP
servers (Atlassian / Linear) when connected.

Setup once:

```
/pr-review:setup-tickets
```

The wizard writes a config file:

- `~/.claude/pr-review.config.json` — user-level (recommended)
- `.claude/pr-review.config.json` — project-level, overrides user-level
  per provider key

Example:

```json
{
  "ticketProviders": {
    "backlog": {
      "baseUrl": "https://yourspace.backlog.jp",
      "auth": { "type": "apiKey", "keyEnv": "BACKLOG_API_KEY" }
    },
    "jira": {
      "baseUrl": "https://yourorg.atlassian.net",
      "auth": { "type": "basic", "emailEnv": "JIRA_EMAIL", "tokenEnv": "JIRA_API_TOKEN" },
      "prefer": "mcp"
    }
  }
}
```

Key points:

- **Fully optional (opt-in).** No config file → the review flow is identical
  to before this feature existed: same prompts, no provider spec loaded (no
  extra token cost), no external calls, and ticket links are simply noted
  as-is. The skill never advertises this feature unprompted.
- **Secrets never live in the config** — it stores env var *names*; you
  export the actual values in your shell (`~/.bashrc`).
- **Fetch always asks first.** When your review request contains a matching
  ticket link/key, the skill confirms via `AskUserQuestion` before calling
  any external API.
- **Failures never block the review.** A failed fetch prints one warning
  line and falls back to recording the link as-is.
- **GitHub Issues needs no credentials** (reuses your `gh` CLI auth) but
  still requires opting in with a `"github": {"enabled": true}` block.
- **MCP**: with `prefer: "mcp"`, the skill uses connected Atlassian/Linear
  MCP tools first and falls back to REST. The wizard prints MCP setup steps.

Full spec (patterns, fetch commands, error rules):
[`skills/review/references/ticket-providers.md`](skills/review/references/ticket-providers.md).

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
