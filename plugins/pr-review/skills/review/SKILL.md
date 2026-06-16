---
name: review
description: Preflight wrapper around the official code-review plugin. Gathers review rules + requirement/ticket context, then chains to /code-review:code-review with the enriched input. Use this skill whenever the user wants to review a PR, commit, or branch — especially when they paste a PR URL/number, commit SHA, branch name, or say "review", "code review", "check this PR", "review this commit". This skill does NOT review code itself — it prepares context then chains.
---

# pr-review:review

Preflight context preparation for `/code-review:code-review` (from the official `code-review` plugin). Job: gather context (review rules, ticket/requirement info), then trigger the upstream review command. Does NOT review code itself.

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
> - **Post inline comments (`--comment`)** — forward `--comment` to upstream so it posts individual inline comments via the GitHub API and a separate summary via `gh pr comment`. Sets `submit_mode = "comment"`.
> - **Submit as PR review** — wrapper-side mode. Upstream runs without `--comment`, then this skill (Step 7) bundles findings into one `POST /repos/.../pulls/.../reviews` call via `gh api` — a single unified Review entry on the PR. Sets `submit_mode = "submit-review"`.

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

### Step 6: Trigger /code-review:code-review

Print a short confirmation that names the input and the chosen `submit_mode`, e.g.:

> "Preflight done. Running /code-review:code-review for PR #142 (terminal-only)…"
> "Preflight done. Running /code-review:code-review for PR #142 (with --comment)…"
> "Preflight done. Running /code-review:code-review for PR #142 (will submit as a unified PR review after upstream finishes)…"

Then invoke the upstream command. **You MUST dispatch the chained command via the `SlashCommand` tool** — printing `/code-review:code-review …` as plain text in your assistant output does NOT execute it (Claude Code does not auto-dispatch slash command strings from the assistant; the upstream command will simply never run, leaving the preflight orphaned).

Call `SlashCommand` with:

```
command: "/code-review:code-review <args>"
```

where `<args>` is the single-string argument payload described below (raw input, optional `--comment`, then a blank line, then the context block from Step 5).

`SlashCommand` is a **built-in** Claude Code tool — it is NOT a deferred tool, so do not look for it in any deferred-tool list, and do not run `ToolSearch` to check for it. Just call it. The host either dispatches the slash command or returns a concrete error.

Only abort if a real `SlashCommand` call returns an error (typical messages: "tool not allowed", "command not found", "plugin not enabled"). In that case, surface the exact error verbatim plus one diagnostic line based on what it said:

- "command not found" / "unknown command" / similar → the upstream `code-review` plugin is likely not enabled. Tell the user to enable `code-review@claude-plugins-official` via `/plugin`.
- "tool not allowed" / permission-style errors → `SlashCommand` is blocked by the host's `allowed-tools` or settings. Tell the user to grant `SlashCommand`.
- Anything else → surface as-is, no speculation.

Do **not** silently fall back to printing the command as text.

The args payload, in order:
1. The raw input from the user (PR URL / PR number / commit SHA / branch).
2. `--comment` **only when `submit_mode == "comment"`**. Omit for `"terminal"` and `"submit-review"` — for `submit-review`, we want upstream to stop at its terminal-summary step so the wrapper can submit the review itself in Step 7.
3. The context block from Step 5 (review rules + ticket info).

After dispatching, wait for upstream to finish. Then:

- If `submit_mode ∈ {"terminal", "comment"}` — **stop**. Let upstream's behavior stand. Do not review or post anything else.
- If `submit_mode == "submit-review"` — proceed to **Step 7** below.

Do not review in parallel or interfere with upstream while it runs.

### Step 7: Submit as PR review (`submit_mode == "submit-review"` only)

Only runs when the user chose **Submit as PR review** at Step 3. This step never executes for `"terminal"` or `"comment"` modes.

The goal: convert upstream's terminal-summary output into one batched GitHub PR Review and submit it via `gh api`. Hardcoded `event: "COMMENT"` — APPROVE/REQUEST_CHANGES has policy traps (GH blocks the PR author on their own PR) and is intentionally not exposed here.

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

Inspect upstream's terminal output (visible in the current conversation as upstream's recent messages) and the `gh pr view` JSON from 7a.

Abort the submission (no `gh api` call) when any of these holds:

- PR is closed (`state == "CLOSED"` or `"MERGED"`).
- PR is a draft (`isDraft == true`).
- Upstream's output indicates it short-circuited at its own Step 1 (e.g., "skipping — PR is draft", "already reviewed by Claude", "automated PR, no review needed").

When aborting, print a one-line reason and stop. Do not write the JSON or call `gh api`.

#### 7c. Extract findings from upstream's output

Read upstream's terminal-summary section (its own Step 7 output) from the current conversation. For each issue:

- If the text gives a clear file path + line (or line range), record `{path, line, body}`. Use `side: "RIGHT"` (the head ref, which is what `code-review` reviews).
- For line ranges, use the end line as `line` and add `start_line` + `start_side: "RIGHT"`.
- Findings without a parseable file:line (e.g. "missing test coverage in module X", architectural notes) — collect into an **overflow** list. They'll go in the review body, not as inline comments.

If upstream's output explicitly says "No issues found", treat that as zero inline comments and use the "No issues found" line as the body.

#### 7d. Build the payload

Write to `/tmp/pr-review-submit-<unix-timestamp>.json` using the Write tool. Shape:

```json
{
  "body": "<top-level summary from upstream, plus a `\n\n## Additional notes\n` section listing overflow findings if any>",
  "event": "COMMENT",
  "comments": [
    {"path": "src/foo.ts", "line": 42, "side": "RIGHT", "body": "<finding body>"}
  ]
}
```

Notes on the shape:
- Omit `comments` entirely (or use `[]`) when there are zero inline findings — body-only is fine.
- For a multi-line range: include `start_line` and `start_side` alongside `line` and `side`. `line` is the **end** line.
- `body` per comment should be terse — the upstream wrapper already validated and de-duplicated.

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

## Supported upstream flags

These flags are interpreted by `/code-review:code-review` (the official `code-review` plugin), not by this skill. This skill's only job around upstream flags is to ask the user and forward the chosen ones.

- **No flag (default)** — Print summary of findings to the terminal. Nothing is posted to GitHub. Used by `submit_mode == "terminal"` **and** `submit_mode == "submit-review"` (the latter does its own posting in Step 7).
- **`--comment`** — If issues are found, upstream posts inline comments on the PR via `mcp__github_inline_comment__create_inline_comment`. If no issues are found, upstream posts a single summary comment via `gh pr comment`. Used by `submit_mode == "comment"`.

Notes:
- The **Submit as PR review** option (`submit_mode == "submit-review"`) is **wrapper-side**, not an upstream flag. It does not modify upstream's args; it just omits `--comment` and runs Step 7 after upstream returns.
- All three modes are only meaningful when the input is a PR. Skip the question for `commit` / `branch` inputs.
- This list reflects the pinned upstream version (see `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/`). When upstream changes, `/pr-review:check-code-review-updates` will surface it; revisit this table when accepting a new pin.

## Important notes

- **All user-facing questions must use the `AskUserQuestion` tool.** Never ask in free text. Skip a question only when the user already gave the answer in their original message.
- **Ticket fetching is optional and opt-in.** With no `pr-review.config.json` present, Step 2 must behave exactly as it did before this feature existed: same menu, same prompts, no reads of `references/ticket-providers.md`, no external calls. Never push the user to configure providers mid-review — at most, mention `/pr-review:setup-tickets` once in 2d.
- **Don't fetch PR diff during preflight.** Fetching the diff and reviewing is the upstream command's job. Fetching **ticket content** is allowed — but only after the user confirms at 2c, and only via the methods in `references/ticket-providers.md`.
- **Don't review code yourself.** No code scanning, no bug hunting in this skill. Preflight → chain → optional Step 7 submission.
- **Don't fabricate ticket info.** If user picked "None / skip", write "None provided". Don't guess. If a ticket fetch fails, use the link as-is — never invent a summary for it.
- **Never expose secrets.** Ticket API credentials live in env vars (names come from the config). Don't print their values, and redact them from any echoed URLs or error output.
- **Bundled `references/review.md` is canonical.** Project-specific rules (`.claude/review.md`) layer on top, not replace.
- **Upstream is pinned.** If the official `/code-review:code-review` has changed shape (new flags, removed flags, different semantics), the chain may need updating — see `/pr-review:check-code-review-updates`.
- **Don't modify upstream.** Step 7 reads upstream's terminal output only — it does not edit upstream files, inject extra instructions into the args, or otherwise alter the official plugin's behavior.
- **`submit-review` requires PR input + `gh auth` with write scope.** Skip the option entirely for commit/branch inputs (no PR to submit to). If `gh auth status` shows only read scope, `gh api` will return 403 — surface it via Step 7f's hints.

## Examples

### Example A — PR with inline ticket, user wants upstream to post comments

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
6. Print: "Preflight done. Running /code-review:code-review for PR #142 (with --comment)…"
7. Dispatch `/code-review:code-review #142 --comment` followed by the context block.
8. Stop. Upstream takes over.

### Example B — bare PR input, both questions asked

**User input:**

> "review #200"

**Skill execution:**

1. Classify: `pr = #200`.
2. Ticket context — none provided. Call `AskUserQuestion` with the 4 options from Step 2. User picks "Extract from PR description" → run `gh pr view 200 --json body,title` and parse ticket refs.
3. Surface mode — call `AskUserQuestion` with the 3 options from Step 3. User picks "Print only". `submit_mode = "terminal"`.
4. Load `references/review.md`.
5. Build context block.
6. Print: "Preflight done. Running /code-review:code-review for PR #200 (terminal-only)…"
7. Dispatch `/code-review:code-review #200` followed by the context block.
8. Stop.

### Example C — branch input (no surface-mode question)

**User input:**

> "review branch feature/payments"

**Skill execution:**

1. Classify: `branch = feature/payments`.
2. Ticket context — none provided. Call `AskUserQuestion`. User picks "None / skip".
3. Surface mode — **skipped** (not a PR). `submit_mode = "terminal"` by default.
4. Load `references/review.md`.
5. Build context block (Requirement / ticket = "None provided").
6. Print: "Preflight done. Running /code-review:code-review for branch feature/payments…"
7. Dispatch `/code-review:code-review feature/payments` followed by the context block.
8. Stop.

### Example D — PR URL, user wants a unified PR review submitted

**User input:**

> "review https://github.com/acme/widgets/pull/87 and submit it as a PR review"

**Skill execution:**

1. Classify: `pr = https://github.com/acme/widgets/pull/87`.
2. Ticket context — none provided. Call `AskUserQuestion`. User picks "None / skip".
3. Surface mode — user said "submit it as a PR review", skip `AskUserQuestion`. `submit_mode = "submit-review"`.
4. Load `references/review.md`.
5. Build context block.
6. Print: "Preflight done. Running /code-review:code-review for PR #87 (will submit as a unified PR review after upstream finishes)…"
7. Dispatch `/code-review:code-review https://github.com/acme/widgets/pull/87` (no `--comment`) followed by the context block. Wait for upstream to finish its Step 7 terminal summary.
8. **Step 7 (this skill):**
   - 7a. Parse URL → `owner=acme`, `repo=widgets`, `number=87`. Confirm with `gh pr view 87 --repo acme/widgets --json url,number,state,isDraft` → `state=OPEN`, `isDraft=false`.
   - 7b. Upstream's output is a normal findings summary; no short-circuit indicators. Continue.
   - 7c. Extract findings. Upstream listed 3 issues; 2 have clear `path:line`, 1 is "consider adding integration test for the new endpoint" (no specific line). Inline = 2, overflow = 1.
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
6. Print: "Preflight done. Running /code-review:code-review for PR #55 (terminal-only)…"
7. Dispatch `/code-review:code-review #55` followed by the context block.
8. Stop.
