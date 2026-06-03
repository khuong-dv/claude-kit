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

If the user already provided ticket info in their original message (e.g. "review PR #142, ticket PROJ-558 — add email validation"), skip this step and use what they gave.

Otherwise call `AskUserQuestion`:

> Question: "Where does the requirement / ticket context for this review come from?"
>
> Options:
> - **Paste description directly** — user types requirement/acceptance criteria in their next reply.
> - **Ticket link (Jira/Linear/Asana/…)** — user pastes a URL. Note it as-is (no fetch unless user asks).
> - **Extract from PR description** — for PR inputs, read PR body via `gh pr view <pr> --json body,title` and parse any ticket references.
> - **None / skip** — review on code + review.md alone.

If the user picks "Paste description" but hasn't pasted yet, make a second `AskUserQuestion` call (or accept the free-text follow-up if they paste it on their own).

### Step 3: Decide whether to post comments on GitHub (PR only)

The upstream command supports a `--comment` flag — see "Supported upstream flags" below. **Only ask this step when the input is a PR.** For `commit` and `branch` inputs, skip — there is no PR to comment on.

If the user explicitly stated a preference in their original message (e.g. "review and post comments", "just print, don't comment"), skip this step and honor what they said.

Otherwise call `AskUserQuestion`:

> Question: "Post the review findings as comments on the PR, or only print to terminal?"
>
> Options:
> - **Print only (default)** — show findings in the terminal. Nothing is posted to GitHub. Equivalent to running without `--comment`.
> - **Post inline comments** — upstream posts inline comments via the GitHub API for each validated issue. Adds `--comment` to the upstream call.

Record the choice as `comment_flag = "--comment"` or empty.

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

Print a short confirmation that names the input and whether `--comment` will be passed, e.g.:

> "Preflight done. Running /code-review:code-review for PR #142 (with --comment)…"
> "Preflight done. Running /code-review:code-review for PR #142 (terminal-only, no comments)…"

Then invoke the upstream command. Two options depending on what's available in the host environment:

1. **If a SlashCommand-style tool is exposed** — call it with command `/code-review:code-review` and pass the args string described below.
2. **Otherwise** — emit the slash command line directly so the host CLI dispatches it: print `/code-review:code-review <args>` on its own line, followed by the context block.

The args payload, in order:
1. The raw input from the user (PR URL / PR number / commit SHA / branch).
2. `--comment` if the user opted in at Step 3. Omit otherwise.
3. The context block from Step 5 (review rules + ticket info).

After dispatching, **stop**. Let `/code-review:code-review` run its own workflow (fetch PR via `gh`, spawn review agents, optionally post comments). Do not review in parallel or interfere.

## Supported upstream flags

These flags are interpreted by `/code-review:code-review` (the official `code-review` plugin), not by this skill. This skill's only job around flags is to ask the user and forward the chosen ones.

- **No flag (default)** — Print summary of findings to the terminal. Nothing is posted to GitHub.
- **`--comment`** — If issues are found, upstream posts inline comments on the PR via `mcp__github_inline_comment__create_inline_comment`. If no issues are found, upstream posts a single summary comment via `gh pr comment`.

Notes:
- `--comment` is only meaningful when the input is a PR. Skip the question for `commit` / `branch` inputs.
- This list reflects the pinned upstream version (see `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/`). When upstream changes, `/pr-review:check-code-review-updates` will surface it; revisit this table when accepting a new pin.

## Important notes

- **All user-facing questions must use the `AskUserQuestion` tool.** Never ask in free text. Skip a question only when the user already gave the answer in their original message.
- **Don't fetch PR diff during preflight.** Fetching and reviewing is the upstream command's job. This skill only gathers context.
- **Don't review code yourself.** No code scanning, no bug hunting in this skill. Preflight → chain only.
- **Don't fabricate ticket info.** If user picked "None / skip", write "None provided". Don't guess.
- **Bundled `references/review.md` is canonical.** Project-specific rules (`.claude/review.md`) layer on top, not replace.
- **Upstream is pinned.** If the official `/code-review:code-review` has changed shape (new flags, removed flags, different semantics), the chain may need updating — see `/pr-review:check-code-review-updates`.

## Examples

### Example A — PR with inline ticket, user wants comments posted

**User input:**

> "review PR #142, ticket PROJ-558 — add validation for email and phone in registration form. Post the comments."

**Skill execution:**

1. Classify: `pr = #142`.
2. Ticket context — user provided it inline, skip `AskUserQuestion`:
   - Ticket: PROJ-558
   - Description: "add validation for email and phone in registration form"
3. Comment flag — user said "Post the comments", skip `AskUserQuestion`. `comment_flag = "--comment"`.
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
3. Comment flag — call `AskUserQuestion` with the 2 options from Step 3. User picks "Print only". `comment_flag = ""`.
4. Load `references/review.md`.
5. Build context block.
6. Print: "Preflight done. Running /code-review:code-review for PR #200 (terminal-only, no comments)…"
7. Dispatch `/code-review:code-review #200` followed by the context block.
8. Stop.

### Example C — branch input (no comment question)

**User input:**

> "review branch feature/payments"

**Skill execution:**

1. Classify: `branch = feature/payments`.
2. Ticket context — none provided. Call `AskUserQuestion`. User picks "None / skip".
3. Comment flag — **skipped** (not a PR; nowhere to post comments).
4. Load `references/review.md`.
5. Build context block (Requirement / ticket = "None provided").
6. Print: "Preflight done. Running /code-review:code-review for branch feature/payments…"
7. Dispatch `/code-review:code-review feature/payments` followed by the context block.
8. Stop.
