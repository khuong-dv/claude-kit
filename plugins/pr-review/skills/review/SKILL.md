---
name: review
description: Self-contained PR/commit/branch review wrapper. Gathers review rules + requirement/ticket context, then executes the bundled pinned snapshot of the official code-review workflow inline (no slash-command chain), and can submit the findings as a single unified GitHub PR review. Use this skill whenever the user wants to review a PR, commit, or branch — especially when they paste a PR URL/number, commit SHA, branch name, or say "review", "code review", "check this PR", "review this commit".
---

# pr-review:review

Preflight context preparation **and** in-place execution of the pinned `code-review` workflow. Job: gather context (review rules, ticket/requirement info), run the embedded review snapshot inline, and optionally submit findings as one unified PR review.

The pinned snapshot lives at `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/commands/code-review.md`. It's the canonical execution source — this skill does NOT chain to a separately-installed `/code-review:code-review` slash command. The drift-check workflow (`/pr-review:check-code-review-updates` + the SessionStart hook) tells you when the snapshot has fallen behind upstream so you can re-pin deliberately.

## Trigger conditions

User provides one of:
- PR URL (e.g. `https://github.com/org/repo/pull/123`)
- PR number (`#123`, `PR 123`)
- Commit SHA (hex string, 7-40 chars)
- Branch name (`feature/login-v2`)
- A phrasing like "review PR X", "check commit Y", "code review branch Z"

If input is ambiguous, do **not** guess — see Step 1.

All user-facing questions in this skill MUST go through the `AskUserQuestion` tool. Never embed a question in free-text output and wait for a reply.

## Workflow

### Step 1: Classify input

Classify the user's input as one of:
- `pr` — PR URL or number
- `commit` — commit SHA
- `branch` — branch name
- `unclear` — must ask via `AskUserQuestion`

If `unclear`, call `AskUserQuestion`:

> Question: "Which PR/commit/branch do you want to review?"
>
> Options:
> - **PR (URL or number)** — e.g. `https://github.com/org/repo/pull/142` or `#142`.
> - **Commit (SHA)** — e.g. `abc1234`.
> - **Branch (name)** — e.g. `feature/login-v2`.

Use the user's selection to re-classify. Do not proceed until classification is one of `pr` / `commit` / `branch`.

### Step 2: Gather requirement / ticket context

If the user already provided the full ticket *content* in their original message (e.g. "review PR #142, ticket PROJ-558 — add email validation"), skip this step entirely and use what they gave. A bare link or key alone is NOT full content — that goes through 2b/2c below.

#### 2a. Load provider config (opt-in gate)

Ticket fetching is **strictly opt-in**. Check (one cheap `ls`) whether either config file exists:
- `.claude/pr-review.config.json` (repo root, project-level)
- `~/.claude/pr-review.config.json` (user-level)

**Neither file exists → `providers = {}`. Skip 2b and 2c entirely, do NOT read `references/ticket-providers.md`, and go straight to 2d.** The flow is then byte-for-byte the pre-fetch behavior: no extra prompts, no extra file reads, no external calls. This includes GitHub issue URLs — without a config opting in, they are just noted as-is like any other link.

If at least one file exists: read it/them, merge per provider key under `ticketProviders` (project overrides user) → `providers`.

#### 2b. Detect a fetchable ticket reference (only when `providers` is non-empty)

Now (and only now) read `references/ticket-providers.md`. Scan the user's original message for a ticket link or bare key matching its detection patterns, restricted to providers present in `providers`. A bare key (`ABC-123`) matching multiple configured providers → ask via `AskUserQuestion` which provider it belongs to.

No match → go to 2d.

#### 2c. Confirm, then fetch

Never call an external API without confirmation. Call `AskUserQuestion`:

> Question: "Fetch ticket content from <provider> (<key>)?"
>
> Options:
> - **Fetch** — pull title + description via the provider's API (or MCP tools when connected — see `references/ticket-providers.md`).
> - **No, use the link as-is** — record the reference without fetching.

On **Fetch**: follow the fetch method, MCP rules, and error rules in `references/ticket-providers.md`. On success, the ticket's title + description (truncated per the spec) become the requirement context. On failure, print the single warning line from the spec, fall back to the link as-is, and continue. Then skip 2d.

#### 2d. Ask where context comes from (no fetchable reference found)

Call `AskUserQuestion`:

> Question: "Where does the requirement / ticket context for this review come from?"
>
> Options:
> - **Paste description directly** — user types requirement/acceptance criteria in their next reply.
> - **Ticket link or key** — user pastes a URL or ticket key (e.g. `PROJ-123`). Only when `providers` is non-empty and it matches a configured provider, loop back to 2c (confirm + fetch); otherwise note it as-is (the pre-fetch behavior).
> - **Extract from PR description** — for PR inputs, read PR body via `gh pr view <pr> --json body,title` and parse any ticket references. Only when `providers` is non-empty and the body contains a matching link/key, offer 2c on it.
> - **None / skip** — review on code + review.md alone.

If the user picks "Paste description" but hasn't pasted yet, make a second `AskUserQuestion` call (or accept the free-text follow-up if they paste it on their own).

Do not advertise ticket fetching unprompted. Only if the user *asks* how to auto-fetch ticket content, point them at `/pr-review:setup-tickets`.

### Step 3: Decide how to surface findings (PR only)

There are three modes for delivering the review back to the user. **Only ask this step when the input is a PR.** For `commit` and `branch` inputs, force `submit_mode = "terminal"` — there's no PR to write to.

If the user explicitly stated a preference in their original message (e.g. "review and post comments", "submit as a PR review", "just print, don't comment"), skip this step and honor what they said.

Otherwise call `AskUserQuestion`:

> Question: "How should the review findings be surfaced?"
>
> Options:
> - **Print only (default)** — show findings in the terminal. Nothing posted to GitHub. Sets `submit_mode = "terminal"`.
> - **Post inline comments (`--comment`)** — runs the pinned snapshot with `--comment` so it posts individual inline comments via `mcp__github_inline_comment__create_inline_comment` and a separate summary via `gh pr comment`. Sets `submit_mode = "comment"`.
> - **Submit as PR review** — wrapper-side mode. The pinned snapshot runs without `--comment` (terminal summary only), then this skill (Step 7) bundles findings into one `POST /repos/.../pulls/.../reviews` call via `gh api` — a single unified Review entry on the PR. Sets `submit_mode = "submit-review"`.

Record the choice as `submit_mode ∈ {"terminal", "comment", "submit-review"}`.

### Step 4: Load review rules

Read `references/review.md` from this skill's directory. That is the default rule set.

Additionally, if the working directory contains `.claude/review.md` or `review.md` at repo root, read it too and include it as a separate section in the context block. The bundled `references/review.md` is always loaded.

### Step 5: Build the context block

Assemble a text block:

```
## Input
<type>: <raw value from user>

## Review rules (from pr-review:review)
<contents of references/review.md>

## Project-specific review rules (if present)
<contents of repo's .claude/review.md or review.md, or omit section>

## Requirement / ticket
<content from step 2, or "None provided">
```

### Step 6: Execute the pinned code-review snapshot inline

Print a short confirmation that names the input and the chosen `submit_mode`, e.g.:

> "Preflight done. Running the pinned code-review workflow for PR #142 (terminal-only)…"
> "Preflight done. Running the pinned code-review workflow for PR #142 (with --comment)…"
> "Preflight done. Running the pinned code-review workflow for PR #142 (will submit as a unified PR review after findings are produced)…"

Then **execute the embedded snapshot directly in this conversation**. Do not dispatch any slash command, do not chain to `/code-review:code-review`, and do not spawn a top-level agent to "run" the review for you — the steps below run in *this* assistant turn (subagents launched inside those steps are part of the snapshot itself).

#### 6a. Load the snapshot

Read `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/commands/code-review.md` with the `Read` tool. Treat the body (everything after the YAML frontmatter) as the workflow you are about to perform. The frontmatter `allowed-tools` line is informational — the tools you actually have are whatever the host has granted to this skill's invocation context.

If the snapshot file is missing or unreadable, abort with: "pr-review: pinned code-review snapshot not found at <path> — re-install the plugin." Do not try to fetch it from the network.

#### 6b. Bind the inputs

Before executing, fix these bindings in your head (and restate them briefly in your next message so the user can see them):

- `<target>` — the raw input from Step 1 (PR URL / number / commit SHA / branch). The snapshot is written assuming a PR; for `commit` or `branch` inputs, substitute as follows:
  - `commit`: pass the SHA to `gh pr list --search "<sha>"` to find the associated PR. If exactly one match, use that PR. If zero or multiple, abort with a clear message — `submit-review` and `--comment` only make sense for a single PR.
  - `branch`: same, via `gh pr list --head <branch>`.
- `--comment` flag — **set only when `submit_mode == "comment"`**. For `"terminal"` and `"submit-review"`, the snapshot's Step 7 must stop at the terminal summary (do not post inline comments, do not call `gh pr comment`). For `submit-review` specifically: also skip the snapshot's Steps 8–9 entirely — Step 7 of *this* skill will do the GitHub submission instead.
- Extra context from Step 5 (review rules + requirement/ticket) — treat this as **additional CLAUDE.md-equivalent guidance** for the snapshot's reviewer agents. When the snapshot's Step 4 says "Audit changes for CLAUDE.md compliance", the agents must also check against the review rules and ticket criteria you assembled in Step 5. Pass the context block verbatim to each reviewer subagent alongside its other instructions.

#### 6c. Run the snapshot

Follow the snapshot's numbered steps in order. The snapshot will spawn its own subagents (haiku / sonnet / opus) — that is part of the snapshot, not this skill. Do not skip steps, do not reorder them, and do not "improve" the workflow inline. The point of pinning is that the workflow is frozen at a known version until the user explicitly re-pins via `/pr-review:check-code-review-updates`.

When the snapshot finishes (its own Step 7 / 9, depending on `--comment`), continue with this skill:

- If `submit_mode ∈ {"terminal", "comment"}` — **stop**. The snapshot already produced the right surface (terminal summary, or inline comments + summary). Do not also submit a PR review.
- If `submit_mode == "submit-review"` — proceed to **Step 7** below. The snapshot's terminal summary (findings list, or "No issues found") is what Step 7 reads.

### Step 7: Submit as PR review (`submit_mode == "submit-review"` only)

Only runs when the user chose **Submit as PR review** at Step 3. This step never executes for `"terminal"` or `"comment"` modes.

The goal: convert the snapshot's terminal-summary output (produced in Step 6c above) into one batched GitHub PR Review and submit it via `gh api`. Hardcoded `event: "COMMENT"` — APPROVE/REQUEST_CHANGES has policy traps (GH blocks the PR author on their own PR) and is intentionally not exposed here.

#### 7a. Resolve PR identity

You need `owner`, `repo`, and `number`.

- **Input was a PR URL** (`https://github.com/<owner>/<repo>/pull/<n>`): regex-parse those three fields directly.
- **Input was `#N`, `PR N`, or bare `N`**: run
  ```
  gh pr view <N> --json url,number,state,isDraft
  ```
  Parse `.url` for `owner` and `repo`. Keep `state` and `isDraft` from the same call for 7b.

If either parsing or `gh pr view` fails, abort Step 7 with a clear error. Do **not** fall back to guessing.

#### 7b. Short-circuit detection

Inspect the snapshot's output produced in Step 6c (visible directly in this conversation as your own prior messages this turn) and the `gh pr view` JSON from 7a.

Abort the submission (no `gh api` call) when any of these holds:

- PR is closed (`state == "CLOSED"` or `"MERGED"`).
- PR is a draft (`isDraft == true`).
- The snapshot's own Step 1 short-circuited (e.g., "skipping — PR is draft", "already reviewed by Claude", "automated PR, no review needed").

When aborting, print a one-line reason and stop. Do not write the JSON or call `gh api`.

#### 7c. Extract findings from the snapshot's output

Read the snapshot's terminal-summary section (its own Step 7 output) from your prior messages in this turn. For each issue:

- If the text gives a clear file path + line (or line range), record `{path, line, body}`. Use `side: "RIGHT"` (the head ref, which is what `code-review` reviews).
- For line ranges, use the end line as `line` and add `start_line` + `start_side: "RIGHT"`.
- Findings without a parseable file:line (e.g. "missing test coverage in module X", architectural notes) — collect into an **overflow** list. They'll go in the review body, not as inline comments.

If the snapshot's output explicitly says "No issues found", treat that as zero inline comments and use the "No issues found" line as the body.

#### 7d. Build the payload

Write to `/tmp/pr-review-submit-<unix-timestamp>.json` using the Write tool. Shape:

```json
{
  "body": "<top-level summary from the snapshot's Step 7 output, plus a `\n\n## Additional notes\n` section listing overflow findings if any>",
  "event": "COMMENT",
  "comments": [
    {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "<finding body>"}
  ]
}
```

Notes on the shape:
- Omit `comments` entirely (or use `[]`) when there are zero inline findings — body-only is fine.
- For a multi-line range: include `start_line` and `start_side` alongside `line` and `side`. `line` is the **end** line.
- `body` per comment should be terse — the snapshot's validation step (its own Step 5) already de-duplicated.

Validate the JSON with `python3 -m json.tool /tmp/pr-review-submit-<ts>.json` before submitting.

#### 7e. Submit

```
gh api --method POST repos/<owner>/<repo>/pulls/<number>/reviews \
  --input /tmp/pr-review-submit-<ts>.json
```

Capture both stdout (the created review JSON) and stderr (errors), and the exit code.

#### 7f. Report

- On success (exit 0): parse `.html_url` from `gh api`'s stdout JSON. Print:
  > Submitted PR review: `<html_url>`
- On non-zero exit: print the full stderr and add a hint based on the HTTP status visible in the error:
  - 401 / 403 → `gh auth refresh -s repo` (write scope is required to create reviews).
  - 404 → repo / PR not found, or the token can't see it.
  - 422 → payload-level validation error (likely a missing or invalid `line`/`path`, or trying to APPROVE/REQUEST_CHANGES your own PR). Print the API's `message`/`errors` fields verbatim.
  - Anything else → surface as-is, no speculation.

Do not retry automatically. Let the user re-invoke after fixing auth/permissions.

#### 7g. Cleanup

Best-effort: `rm -f /tmp/pr-review-submit-<ts>.json`. If removal fails, ignore — `/tmp/` will be reaped by the OS.

## Snapshot flag behaviour

These flags govern how the pinned snapshot (executed in Step 6) surfaces findings. This skill chooses which one to apply based on `submit_mode` from Step 3.

- **No flag (default)** — Snapshot prints summary of findings to the terminal. Nothing is posted to GitHub. Used by `submit_mode == "terminal"` **and** `submit_mode == "submit-review"` (the latter does its own posting in Step 7 of this skill).
- **`--comment`** — If issues are found, the snapshot posts inline comments via `mcp__github_inline_comment__create_inline_comment`. If no issues are found, it posts a single summary comment via `gh pr comment`. Used by `submit_mode == "comment"`.

Notes:
- The **Submit as PR review** option (`submit_mode == "submit-review"`) is wrapper-side, not a snapshot flag. The snapshot runs in default mode and this skill's Step 7 submits the bundled review afterward.
- All three modes are only meaningful when the input is a PR. Skip the question for `commit` / `branch` inputs.
- The snapshot's behaviour reflects the pinned version (see `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/MANIFEST.json`). When upstream changes, `/pr-review:check-code-review-updates` will surface it; revisit this table when accepting a new pin.

## Important notes

- **All user-facing questions must use the `AskUserQuestion` tool.** Never ask in free text. Skip a question only when the user already gave the answer in their original message.
- **Ticket fetching is optional and opt-in.** With no `pr-review.config.json` present, Step 2 must behave exactly as it did before this feature existed: same menu, same prompts, no reads of `references/ticket-providers.md`, no external calls. Never push the user to configure providers mid-review — at most, mention `/pr-review:setup-tickets` once in 2d.
- **Don't fetch PR diff during preflight.** Fetching the diff and reviewing is the snapshot's job in Step 6. Fetching **ticket content** is allowed — but only after the user confirms at 2c, and only via the methods in `references/ticket-providers.md`.
- **The snapshot is the reviewer.** Steps 1–5 of this skill prepare context, Step 6 executes the snapshot inline, Step 7 optionally submits. Do not "review" the code yourself outside the snapshot's structured steps.
- **Don't fabricate ticket info.** If user picked "None / skip", write "None provided". Don't guess. If a ticket fetch fails, use the link as-is — never invent a summary for it.
- **Never expose secrets.** Ticket API credentials live in env vars (names come from the config). Don't print their values, and redact them from any echoed URLs or error output.
- **Bundled `references/review.md` is canonical.** Project-specific rules (`.claude/review.md`) layer on top, not replace.
- **Snapshot is pinned, not chained.** This skill executes the bundled snapshot at `state/code-review-pinned/commands/code-review.md`. It does **not** dispatch a `/code-review:code-review` slash command, and does not require the official `code-review` plugin to be installed. If upstream changes, `/pr-review:check-code-review-updates` surfaces the drift so the snapshot can be re-pinned deliberately.
- **Don't modify the snapshot at runtime.** Step 6 reads it as-is. Re-pinning is a deliberate workflow via `/pr-review:check-code-review-updates`, not something to do inline.
- **`submit-review` requires PR input + `gh auth` with write scope.** Skip the option entirely for commit/branch inputs (no PR to submit to). If `gh auth status` shows only read scope, `gh api` will return 403 — surface it via Step 7f's hints.

## Examples

### Example A — PR with inline ticket, user wants inline comments posted

**User input:**

> "review PR #142, ticket PROJ-558 — add validation for email and phone in registration form. Post the comments."

**Skill execution:**

1. Classify: `pr = #142`.
2. Ticket context — user provided it inline, skip `AskUserQuestion`:
   - Ticket: PROJ-558
   - Description: "add validation for email and phone in registration form"
3. Surface mode — user said "Post the comments", skip `AskUserQuestion`. `submit_mode = "comment"`.
4. Load `references/review.md`.
5. Build context block.
6. Print: "Preflight done. Running the pinned code-review workflow for PR #142 (with --comment)…"
   - 6a. Read `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/commands/code-review.md`.
   - 6b. Bind `<target> = #142`, `--comment = true`, attach the Step 5 context block as additional CLAUDE.md-equivalent guidance for the snapshot's reviewer subagents.
   - 6c. Execute the snapshot's numbered steps inline. The snapshot posts inline comments + a summary comment per its own Steps 7–9.
7. Stop. Snapshot handled the surface.

### Example B — bare PR input, both questions asked

**User input:**

> "review #200"

**Skill execution:**

1. Classify: `pr = #200`.
2. Ticket context — none provided. Call `AskUserQuestion` with the 4 options from Step 2. User picks "Extract from PR description" → run `gh pr view 200 --json body,title` and parse ticket refs.
3. Surface mode — call `AskUserQuestion` with the 3 options from Step 3. User picks "Print only". `submit_mode = "terminal"`.
4. Load `references/review.md`.
5. Build context block.
6. Print: "Preflight done. Running the pinned code-review workflow for PR #200 (terminal-only)…"
   - 6a. Read the pinned snapshot.
   - 6b. Bind `<target> = #200`, `--comment = false` (terminal mode).
   - 6c. Execute the snapshot's steps inline. Snapshot stops at its own Step 7 terminal summary.
7. Stop.

### Example C — branch input (no surface-mode question)

**User input:**

> "review branch feature/payments"

**Skill execution:**

1. Classify: `branch = feature/payments`.
2. Ticket context — none provided. Call `AskUserQuestion`. User picks "None / skip".
3. Surface mode — **skipped** (not a PR). `submit_mode = "terminal"` by default.
4. Load `references/review.md`.
5. Build context block (Requirement / ticket = "None provided").
6. Print: "Preflight done. Running the pinned code-review workflow for branch feature/payments…"
   - 6a. Read the pinned snapshot.
   - 6b. Resolve branch → PR via `gh pr list --head feature/payments`. If exactly one match, bind `<target>` to that PR number; otherwise abort with the multi/zero-match message.
   - 6c. Execute snapshot inline in terminal mode.
7. Stop.

### Example D — PR URL, user wants a unified PR review submitted

**User input:**

> "review https://github.com/acme/widgets/pull/87 and submit it as a PR review"

**Skill execution:**

1. Classify: `pr = https://github.com/acme/widgets/pull/87`.
2. Ticket context — none provided. Call `AskUserQuestion`. User picks "None / skip".
3. Surface mode — user said "submit it as a PR review", skip `AskUserQuestion`. `submit_mode = "submit-review"`.
4. Load `references/review.md`.
5. Build context block.
6. Print: "Preflight done. Running the pinned code-review workflow for PR #87 (will submit as a unified PR review after findings are produced)…"
   - 6a. Read the pinned snapshot.
   - 6b. Bind `<target>` to the PR URL, `--comment = false`. For `submit-review`, also skip the snapshot's Steps 8–9 — this skill's Step 7 will post the review.
   - 6c. Execute the snapshot inline. It stops at its own Step 7 terminal summary.
7. **Step 7 (this skill):**
   - 7a. Parse URL → `owner=acme`, `repo=widgets`, `number=87`. Confirm with `gh pr view 87 --repo acme/widgets --json url,number,state,isDraft` → `state=OPEN`, `isDraft=false`.
   - 7b. Snapshot's output is a normal findings summary; no short-circuit indicators. Continue.
   - 7c. Extract findings. Snapshot listed 3 issues; 2 have clear `path:line`, 1 is "consider adding integration test for the new endpoint" (no specific line). Inline = 2, overflow = 1.
   - 7d. Write payload to `/tmp/pr-review-submit-1717427200.json`:
     ```json
     {
       "body": "Reviewed PR #87. Two issues to address inline; one general suggestion below.\n\n## Additional notes\n- Consider adding an integration test for the new endpoint (no specific line).",
       "event": "COMMENT",
       "comments": [
         {"path": "src/handlers/orders.ts", "line": 42, "side": "RIGHT", "body": "Null check missing on `req.body.order_id` before .toLowerCase()."},
         {"path": "src/db/migrations/0042.sql", "line": 7, "side": "RIGHT", "body": "Adding NOT NULL without a default fails on existing rows."}
       ]
     }
     ```
   - 7e. Run `gh api --method POST repos/acme/widgets/pulls/87/reviews --input /tmp/pr-review-submit-1717427200.json`.
   - 7f. Parse `.html_url` from stdout. Print: `Submitted PR review: https://github.com/acme/widgets/pull/87#pullrequestreview-12345678`.
   - 7g. `rm -f /tmp/pr-review-submit-1717427200.json`.

### Example E — Backlog ticket link, confirmed fetch

**User input:**

> "review PR #55 — ticket https://acme.backlog.jp/view/SHOP-310"

(`~/.claude/pr-review.config.json` has a `backlog` provider with `baseUrl: https://acme.backlog.jp`, `keyEnv: BACKLOG_API_KEY`.)

**Skill execution:**

1. Classify: `pr = #55`.
2. **Step 2:**
   - 2a. Load config → `providers = {backlog: …}`.
   - 2b. Message contains `https://acme.backlog.jp/view/SHOP-310` → matches the Backlog pattern → key `SHOP-310`.
   - 2c. `AskUserQuestion`: "Fetch ticket content from backlog (SHOP-310)?" → user picks **Fetch**. Verify `BACKLOG_API_KEY` is set, then `curl -fsSL --max-time 15 "https://acme.backlog.jp/api/v2/issues/SHOP-310?apiKey=${BACKLOG_API_KEY}"` → parse `.summary` + `.description`. (Had it failed: print the one-line warning, keep the URL as-is.)
   - 2d. Skipped (fetch succeeded).
3. Surface mode — not stated. `AskUserQuestion` → user picks "Print only". `submit_mode = "terminal"`.
4. Load `references/review.md`.
5. Build context block — `## Requirement / ticket` contains `SHOP-310: <summary>` plus the fetched description.
6. Print: "Preflight done. Running the pinned code-review workflow for PR #55 (terminal-only)…"
   - 6a. Read the pinned snapshot.
   - 6b. Bind `<target> = #55`, `--comment = false`.
   - 6c. Execute snapshot inline.
7. Stop.
