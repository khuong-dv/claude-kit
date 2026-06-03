---
name: code-review-preflight
description: Prepares context (review rules + requirement/ticket info) then auto-triggers /code-review:code-review. Use this skill whenever the user wants to review a PR, commit, or branch — especially when they paste a PR URL/number, commit SHA, branch name, or say "review", "code review", "check this PR", "review this commit". This skill does NOT review code itself — it gathers context then chains to code-review:code-review so that command runs with richer input.
---

# Code Review Preflight

Preflight context preparation for `code-review:code-review`. The only job: gather context (review rules, ticket/requirement info), then auto-trigger the review command. This skill does NOT review code itself.

## Trigger conditions

User provides one of:
- PR URL (e.g. `https://github.com/org/repo/pull/123`)
- PR number (`#123`, `PR 123`)
- Commit SHA (`abc1234...`)
- Branch name (`feature/login-v2`)
- A request like "review PR X", "check commit Y", "code review branch Z"

If input is ambiguous, ask briefly: "Which PR/commit/branch do you want to review?"

## Workflow

### Step 1: Classify input

Classify the user's input as one of:
- `pr` — PR URL or number
- `commit` — commit SHA (hex string, 7-40 chars)
- `branch` — branch name
- `unclear` — ask the user

Don't guess if ambiguous.

### Step 2: Gather requirement / ticket context

Use `AskUserQuestion` to let the user choose how to provide ticket context:

> "Where does the requirement / ticket context for this review come from?"

Options:
- **Paste description directly** — user types requirement/acceptance criteria in their response.
- **Ticket link (Jira/Linear/Asana/...)** — user pastes a URL. Note it as-is (no need to fetch unless user asks).
- **Extract from PR description** — if input is a PR, read PR body via `gh pr view <pr> --json body,title` and parse any ticket references from it.
- **None / skip** — review based on code and review.md only, no extra ticket context.

If the user already provided ticket info in their original message (e.g. "review PR #142, ticket PROJ-558 — add email validation"), skip this question and use what they gave.

After selection, if more info is needed (e.g. they chose "Paste description" but haven't pasted yet), ask a follow-up.

### Step 3: Load review rules

Read `references/review.md` from this skill's directory. This is the default rule set.

Additionally, if the working directory contains `.claude/review.md` or `review.md` at repo root, read it too and include it as a separate section in the context block. The bundled review.md is always loaded.

### Step 4: Build context block

Assemble a text block:

```
## Input
<type>: <raw value from user>

## Review rules (from code-review-preflight skill)
<contents of references/review.md>

## Requirement / ticket
<content from step 2, or "None provided">
```

### Step 5: Auto-trigger code-review:code-review

Print a short confirmation (e.g. "Preflight done. Running code-review:code-review for PR #142..."), then **invoke** the review command via the Skill tool:

```
Skill(skill="code-review:code-review", args=<args string>)
```

The `<args string>` is a text string containing:
- First line: the raw input from user (PR URL / PR number / commit SHA / branch name).
- Followed by the context block from step 4 (review rules + ticket info).

Example args:

```
#142

## Review rules (from code-review-preflight skill)
<... contents of references/review.md ...>

## Requirement / ticket
Ticket: PROJ-558
Description: Add validation for email and phone in registration form
```

After invoking the Skill tool, **stop**. Let `code-review:code-review` run its own workflow (fetch PR via gh, spawn review agents, post comment). Do not review in parallel or interfere.

## Important notes

- **Auto-trigger, don't instruct user to type.** After gathering context, invoke `code-review:code-review` via Skill tool immediately.
- **Don't fetch PR diff during preflight.** Fetching and reviewing is `code-review:code-review`'s job. This skill only gathers context and passes it as args.
- **Don't review code yourself.** This skill doesn't scan code or find bugs. Preflight → chain only.
- **Don't fabricate ticket info.** If user chose "None / skip", write "None provided" in the context block. Don't guess.
- **Bundled review.md is the canonical rule set.** If the project has its own review rules (`.claude/review.md` in repo), include them as an additional section.

## Example

**User input:**
> "review PR #142, ticket PROJ-558 — add validation for email and phone in registration form"

**Skill execution:**

1. Classify: `pr = #142`
2. Ticket context — user already provided it inline, skip AskUserQuestion:
   - Ticket: PROJ-558
   - Description: "add validation for email and phone in registration form"
3. Load `references/review.md`.
4. Build context block.
5. Print: "Preflight done. Running code-review:code-review for PR #142..."
6. Invoke `Skill(skill="code-review:code-review", args="#142\n\n## Review rules (from code-review-preflight skill)\n<... review.md contents ...>\n\n## Requirement / ticket\nTicket: PROJ-558\nDescription: add validation for email and phone in registration form")`
7. Stop. Let the review command run.
