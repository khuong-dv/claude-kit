---
description: Check the upstream official code-review plugin for new versions. If there's a version drift from this plugin's pinned snapshot, spawn an agent to diff and report breaking changes. Never updates anything automatically — output is advisory.
allowed-tools: Bash(curl:*), Bash(diff:*), Bash(python3:*), Bash(cat:*), Bash(ls:*), Bash(mkdir:*), Read, Write, Edit, Agent
---

# /pr-review:check-code-review-updates

This command compares the **pinned** version of the official `code-review` plugin (recorded in this plugin's `plugin.json` and snapshot under `state/code-review-pinned/`) against the **latest** upstream version, then asks an agent to summarize breaking changes.

It will **not** update anything on its own. After reading the agent's report, the user decides whether to accept the upstream change — and if so, runs the explicit re-pin steps printed at the end.

## Steps

### 1. Read the local pin

Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and extract `pinned["code-review"].version` → call this `PINNED_VERSION`.

Read `${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/MANIFEST.json` to get the list of files that were snapshotted (relative paths under the upstream plugin).

If `plugin.json` has no `pinned.code-review` block, stop and tell the user that nothing is pinned yet.

### 2. Fetch the upstream marketplace entry

Run:

```
curl -fsSL --max-time 10 https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json
```

Parse JSON, find the entry with `name == "code-review"`, extract its `version` → call this `UPSTREAM_VERSION`.

If fetch fails, stop and tell the user (likely a network issue; nothing to compare).

### 3. Compare versions

- If `PINNED_VERSION == UPSTREAM_VERSION`: print "Already up to date (code-review @ ${PINNED_VERSION})." and stop.
- Otherwise continue.

### 4. Fetch upstream snapshot files

For each file listed in `MANIFEST.json.files`, fetch its current content from the URL in `.remote`. Save under a temp directory (e.g. `/tmp/pr-review-upstream-code-review-<timestamp>/`). Mirror the same relative path layout.

### 5. Diff pinned snapshot vs upstream

For each file, compute a unified diff:

```
diff -u "${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/<relpath>" "<tempdir>/<relpath>"
```

Collect the diffs as text.

If all diffs are empty (file content matches even though `version` field differs), tell the user "Upstream bumped version to ${UPSTREAM_VERSION} but tracked files are identical. Safe to re-pin (no diff)." Then proceed to Step 7 — but the agent in Step 6 can be skipped since there is nothing material to review.

### 6. Spawn the review agent

Use the `Agent` tool with `subagent_type: "pr-review-code-review-update-reviewer"` (defined in `${CLAUDE_PLUGIN_ROOT}/agents/code-review-update-reviewer.md`).

Pass the agent a prompt containing:
- `PINNED_VERSION` and `UPSTREAM_VERSION`
- The full text of `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` (so it knows what pr-review:review expects from the upstream command)
- All collected diffs from Step 5
- The full upstream file contents (so the agent isn't reading diff-only)

Ask the agent to produce:
1. A short summary (1–3 lines): what changed.
2. A classification: **safe**, **needs-attention**, or **breaking** w.r.t. pr-review:review's assumptions about `/code-review:code-review`.
3. A list of specific risks (each one referencing a file:line in the upstream version).
4. A go/no-go recommendation.

### 7. Print the re-pin instructions

After the agent's report (or after a "no material diff" Step 5), print the exact manual steps to re-pin, e.g.:

```
To accept this upstream version:
  1. Copy fetched files into the pinned snapshot:
     cp -r <tempdir>/* "${CLAUDE_PLUGIN_ROOT}/state/code-review-pinned/"
  2. Bump the pinned version in plugin.json:
     - Edit "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"
     - Set .pinned["code-review"].version = "${UPSTREAM_VERSION}"
  3. Update MANIFEST.json:
     - Set .pinnedVersion = "${UPSTREAM_VERSION}"
     - Set .pinnedAt = today's date (YYYY-MM-DD)
  4. If breaking changes were flagged, also update skills/review/SKILL.md to match.
```

Do **not** perform these steps automatically. The user opted into a manual update flow.

## Notes

- This command is **read-mostly**: it fetches, diffs, and reports. The only writes are to the temp directory.
- If the user wants to silence the SessionStart warning while leaving the pin out of date, set `PR_REVIEW_DISABLE_UPDATE_WARN=1` in their environment.
- This command does not handle network-pinned plugins other than `code-review`. To extend to others later, add entries to `pinned` in `plugin.json` and to `MANIFEST.json.files`, and generalize Steps 1–6.
