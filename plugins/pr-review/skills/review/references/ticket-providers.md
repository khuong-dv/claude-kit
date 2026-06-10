# Ticket providers — detection, fetch, and error rules

Spec for fetching requirement/ticket content from external systems during
`pr-review:review` Step 2.

**This entire feature is opt-in.** Read this file only when a
`pr-review.config.json` exists (SKILL.md Step 2a) and a fetch may happen.
No config → no provider is active (GitHub included), no fetch prompts, and
the review flow is identical to the pre-fetch behavior.

## Config files

- User-level: `~/.claude/pr-review.config.json`
- Project-level: `.claude/pr-review.config.json` (repo root)

Merge rule: start from the user-level file, then override **per provider key**
with the project-level file. If neither file exists, fetching is disabled and
Step 2 behaves as if this spec did not exist.

Schema:

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
    },
    "linear": {
      "auth": { "type": "apiKey", "keyEnv": "LINEAR_API_KEY" },
      "prefer": "mcp"
    },
    "github": { "enabled": true }
  }
}
```

- Config stores env var **names**, never secret values.
- `prefer: "mcp"` — try MCP tools first; REST is the fallback.
- `github` needs no auth config (it reuses the `gh` CLI's existing auth) but
  is still opt-in: GitHub issue URLs are only fetchable when the config
  contains a `github` block (`{"enabled": true}`).

## Detection patterns

| Provider | Pattern |
|---|---|
| Backlog | `https://<space>.backlog.jp/view/<KEY>` or `https://<space>.backlog.com/view/<KEY>` |
| Jira Cloud | `https://<org>.atlassian.net/browse/<KEY>` |
| GitHub Issues | `https://github.com/<owner>/<repo>/issues/<number>` |
| Linear | `https://linear.app/<team>/issue/<KEY>` (optional trailing `-slug`) |
| Bare key | `[A-Z][A-Z0-9]+-[0-9]+` (e.g. `PROJ-123`) |

Bare-key resolution:
- Exactly one of {backlog, jira, linear} configured → attribute the key to it.
- Two or more configured → ask via `AskUserQuestion` which provider the key
  belongs to. Never guess.
- None configured → not a fetchable reference; note as-is.

## Fetch methods

Before any REST call, verify the required env vars are non-empty
(`[[ -n "${VAR:-}" ]]`). Empty → treat as fetch failure (see Error rules).

### Backlog (Nulab)

```
curl -fsSL --max-time 15 "<baseUrl>/api/v2/issues/<KEY>?apiKey=${<keyEnv>}"
```

Fields: `.summary` (title), `.description`.

### Jira Cloud

MCP first when `prefer == "mcp"` or Atlassian MCP tools are connected
(tool names like `mcp__claude_ai_Atlassian__*` or `mcp__atlassian__*`):
use the issue-get tool with the key, take title + description from its result.

REST fallback:

```
curl -fsSL --max-time 15 -u "${<emailEnv>}:${<tokenEnv>}" \
  "<baseUrl>/rest/api/3/issue/<KEY>?fields=summary,description"
```

Fields: `.fields.summary`, `.fields.description`. The description is ADF
(Atlassian Document Format) JSON — flatten it to plain text by concatenating
all `text` node values in document order (python3 one-liner is fine). Do not
include raw ADF JSON in the context block.

### GitHub Issues

```
gh issue view <number> --repo <owner>/<repo> --json title,body
```

Fields: `.title`, `.body`. No config or extra auth needed.

### Linear

MCP first when `prefer == "mcp"` or Linear MCP tools are connected
(`mcp__claude_ai_Linear__*` or `mcp__linear__*`).

REST (GraphQL) fallback:

```
curl -fsSL --max-time 15 -H "Authorization: ${<keyEnv>}" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ issue(id: \"<KEY>\") { title description } }"}' \
  https://api.linear.app/graphql
```

Fields: `.data.issue.title`, `.data.issue.description`.

## MCP rules

- An MCP server counts as usable only if its tools are actually callable in
  the current session. If only an `authenticate` tool is exposed, the server
  is connected but not authenticated.
- Connected-but-unauthenticated + user confirmed fetch → ask (one
  `AskUserQuestion`) whether to authenticate now. Declined → REST fallback if
  config exists → otherwise note link as-is.
- Never auto-trigger MCP authentication without asking.

## Error rules

On any failure — missing/empty env var, non-2xx HTTP, timeout, JSON parse
error, MCP tool error:

1. Print exactly one warning line:
   `[pr-review] fetch <provider> <key> failed: <short reason> — using link as-is`
2. Put the raw link/key into the `## Requirement / ticket` section unchanged.
3. Continue the workflow. No retries. Never block the review on a fetch error.

## Output handling

- Context block gets: ticket key, title, description.
- Truncate description to ~4000 characters; append `… [truncated]` when cut.
- **Never print secret values.** Reference env vars by name in commands; never
  interpolate their values into displayed text or error messages. If a curl
  error message happens to echo the URL with an `apiKey=` query param, redact
  the key before showing it.
