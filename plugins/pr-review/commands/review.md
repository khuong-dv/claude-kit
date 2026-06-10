---
description: Explicit slash-command entrypoint to the pr-review:review skill. Same behavior as auto-trigger — gathers ticket context + review rules, asks how to surface findings, then chains to /code-review:code-review. Use this when you want to invoke review through the / menu instead of natural language.
allowed-tools: Skill, AskUserQuestion, Bash(gh:*), Bash(python3:*), Bash(rm:*), Read, Write
---

# /pr-review:review

Thin wrapper that explicitly invokes the `pr-review:review` skill with the
user's arguments. Behavior is identical to the auto-trigger flow — this
command exists solely so the review entrypoint shows up in the slash menu.

## Usage

```
/pr-review:review <PR URL | PR number | commit SHA | branch>
```

Optional context can be added inline, e.g.:

```
/pr-review:review #142, ticket PROJ-558 — add email validation. Submit as a PR review.
```

The skill itself decides whether to ask follow-up questions (ticket source,
how to surface findings) or skip them based on what you provided.

## What this command does

Invoke the `pr-review:review` skill via the `Skill` tool, passing the
arguments verbatim. Do not re-implement the skill's logic here — defer
entirely to `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md`.

If no arguments are provided, still invoke the skill — it will ask via
`AskUserQuestion` to classify the input (PR / commit / branch).
