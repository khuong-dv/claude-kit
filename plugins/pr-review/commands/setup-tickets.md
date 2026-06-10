---
description: Interactive wizard to configure ticket providers (Backlog, Jira Cloud, GitHub Issues, Linear) for pr-review:review's requirement-context fetching. Writes pr-review.config.json (user- or project-level), prints env var and MCP setup instructions. Never stores secrets in the config.
allowed-tools: AskUserQuestion, Read, Write, Edit, Bash(gh:*), Bash(curl:*), Bash(python3:*), Bash(ls:*), Bash(mkdir:*)
---

# /pr-review:setup-tickets

Configures which ticket systems `pr-review:review` may fetch requirement
context from. Produces/updates a `pr-review.config.json` file. The config
stores env var **names** only — never secret values.

The full provider spec (patterns, fetch commands, error rules) lives in
`${CLAUDE_PLUGIN_ROOT}/skills/review/references/ticket-providers.md`. Read it
first so the config you write matches what the skill expects.

## Wizard flow

All questions go through `AskUserQuestion`.

### 1. Pick providers

Ask (multiSelect): "Which ticket providers do you want to configure?"
- **Backlog (Nulab)** — REST, API key via query param.
- **Jira Cloud** — REST (Basic auth) and/or Atlassian MCP.
- **GitHub Issues** — uses `gh` CLI auth; no credentials needed.
- **Linear** — GraphQL (API key) and/or Linear MCP.

### 2. Per-provider details

For each selected provider, collect what its config block needs:

- **Backlog**: base URL (e.g. `https://yourspace.backlog.jp`); env var name
  for the API key (default `BACKLOG_API_KEY`).
- **Jira Cloud**: base URL (e.g. `https://yourorg.atlassian.net`); env var
  names for email + API token (defaults `JIRA_EMAIL`, `JIRA_API_TOKEN`); ask
  whether to prefer MCP when connected (`prefer: "mcp"`).
- **GitHub Issues**: nothing to ask — config block is `{"enabled": true}`.
  Verify `gh auth status` succeeds and tell the user if it doesn't.
- **Linear**: env var name for the API key (default `LINEAR_API_KEY`); ask
  whether to prefer MCP (`prefer: "mcp"`).

Accept defaults silently when the user picks a "use default" style answer.

### 3. Pick scope

Ask: "Where should this config live?"
- **User-level (recommended)** — `~/.claude/pr-review.config.json`. Applies to
  every repo; right place for personal credentials' env var names.
- **Project-level** — `.claude/pr-review.config.json` in the current repo.
  Overrides user-level per provider key. Note: the file contains no secrets
  (only base URLs + env var names), so committing it is usually fine; if the
  base URL itself is sensitive, suggest adding it to `.gitignore`.

### 4. Write the config

- Read the target file if it exists. Merge: keep existing providers, replace
  only the ones configured in this run. Never drop providers the user set up
  earlier.
- Write JSON with the `ticketProviders` top-level key, matching the schema in
  `ticket-providers.md`.
- Validate with `python3 -m json.tool <file>` after writing.

### 5. Print follow-up instructions

After writing, print (do NOT execute) the remaining manual steps:

- Env vars — for each REST-configured provider:
  ```
  export BACKLOG_API_KEY="..."   # add to ~/.bashrc or ~/.zshrc
  ```
  Never ask the user to paste the secret value into this conversation.
- MCP (Jira/Linear only) — if the user wants MCP instead of/alongside REST:
  - Connect via `/mcp` in Claude Code, or `claude mcp add` for a custom
    server.
  - Once the MCP server is connected and authenticated, REST env vars are
    unnecessary for that provider; `prefer: "mcp"` makes the skill try MCP
    first.

### 6. Optional smoke test

Ask whether the user wants to test a fetch now. If yes, ask for a ticket
key/URL, then run the provider's fetch command from `ticket-providers.md`:

- Only if the required env vars are already set in this shell (check with
  `[[ -n "${VAR:-}" ]]` — never print values).
- On success: print the ticket's title only.
- On failure: print the one-line warning format from the spec and point at
  the likely cause (env var not exported in this session, wrong base URL,
  expired token). Do not retry.

## Rules

- Config files contain env var names, base URLs, and flags — **never secret
  values**. If the user pastes a secret, do not write it anywhere; tell them
  to export it as an env var instead.
- Do not edit shell rc files. Print instructions only.
- Do not run `claude mcp add` or trigger MCP authentication yourself —
  instruct the user.
- Merging is additive: this wizard must never delete a provider it wasn't
  asked to touch.
