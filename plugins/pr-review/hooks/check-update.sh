#!/usr/bin/env bash
# pr-review SessionStart hook: warn (only) when pinned upstream plugin versions
# differ from the official marketplace. Never fails the session.
#
# Opt-out: set PR_REVIEW_DISABLE_UPDATE_WARN=1 in your environment.
#
# This script writes a single line to stdout when a mismatch is found. Claude
# Code surfaces SessionStart stdout to the user. On any error (no network, no
# jq, malformed JSON, etc.) we exit 0 silently — a session-start hook is the
# wrong place to nag.

set -u

if [[ "${PR_REVIEW_DISABLE_UPDATE_WARN:-0}" == "1" ]]; then
  exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
MARKETPLACE_URL="https://raw.githubusercontent.com/anthropics/claude-code/main/.claude-plugin/marketplace.json"

# Need: curl + (python3 OR jq). Prefer python3 (no extra install).
if ! command -v curl >/dev/null 2>&1; then exit 0; fi
if ! command -v python3 >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then exit 0; fi
[[ -f "$PLUGIN_JSON" ]] || exit 0

REMOTE=$(curl -fsSL --max-time 5 "$MARKETPLACE_URL" 2>/dev/null) || exit 0
[[ -n "$REMOTE" ]] || exit 0

LOCAL=$(cat "$PLUGIN_JSON" 2>/dev/null) || exit 0

if command -v python3 >/dev/null 2>&1; then
  python3 - "$LOCAL" "$REMOTE" <<'PY' || exit 0
import json, sys
local_raw, remote_raw = sys.argv[1], sys.argv[2]
try:
    local = json.loads(local_raw)
    remote = json.loads(remote_raw)
except Exception:
    sys.exit(0)

pinned = (local.get("pinned") or {})
if not pinned:
    sys.exit(0)

remote_plugins = {p.get("name"): p.get("version") for p in remote.get("plugins", [])}

mismatches = []
for name, info in pinned.items():
    pinned_version = (info or {}).get("version")
    upstream_version = remote_plugins.get(name)
    if not pinned_version or not upstream_version:
        continue
    if pinned_version != upstream_version:
        mismatches.append((name, pinned_version, upstream_version))

if mismatches:
    parts = [f"{n} pinned={p} upstream={u}" for (n, p, u) in mismatches]
    print(
        "[pr-review] upstream plugin update available: "
        + "; ".join(parts)
        + ". Run /pr-review:check-code-review-updates to review."
        " (Silence: PR_REVIEW_DISABLE_UPDATE_WARN=1)"
    )
PY
  exit 0
fi

# jq fallback
PINNED_VERSION=$(printf '%s' "$LOCAL" | jq -r '.pinned["code-review"].version // empty' 2>/dev/null) || exit 0
UPSTREAM_VERSION=$(printf '%s' "$REMOTE" | jq -r '.plugins[] | select(.name=="code-review") | .version // empty' 2>/dev/null) || exit 0

if [[ -n "$PINNED_VERSION" && -n "$UPSTREAM_VERSION" && "$PINNED_VERSION" != "$UPSTREAM_VERSION" ]]; then
  echo "[pr-review] upstream plugin update available: code-review pinned=${PINNED_VERSION} upstream=${UPSTREAM_VERSION}. Run /pr-review:check-code-review-updates to review. (Silence: PR_REVIEW_DISABLE_UPDATE_WARN=1)"
fi
exit 0
