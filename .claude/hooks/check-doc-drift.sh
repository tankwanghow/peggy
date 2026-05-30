#!/usr/bin/env bash
#
# PostToolUse(Bash) hook: after a `git commit`, check whether the committed
# code changes might have made the project docs stale. If code files changed,
# inject a reminder asking Claude to reconcile the docs (and get the user's
# permission before editing them). The hook never edits anything itself —
# it only signals; the judgement and the update are Claude's.

set -euo pipefail

input=$(cat)

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Only act on real `git commit` invocations: the command must appear at the
# start of a command segment (line start, or after ; && || |), not merely
# mention the words "git commit" inside a quoted string or another tool's args.
if ! printf '%s' "$cmd" | grep -Eq '(^|[;&|]|&&)[[:space:]]*git[[:space:]]+commit\b'; then
  exit 0
fi

cd "$(printf '%s' "$input" | jq -r '.cwd // "."')" 2>/dev/null || exit 0

# Files touched by the most recent commit, restricted to code/config paths
# whose changes could plausibly invalidate the docs.
changed=$(git show --name-only --pretty=format: HEAD 2>/dev/null \
  | grep -E '^(lib/|config/|priv/repo/migrations/|mix\.exs|assets/)' || true)

[ -z "$changed" ] && exit 0

msg=$(printf 'A git commit just landed touching code/config files:\n%s\n\nBefore moving on, judge whether these changes have made any project docs stale: CLAUDE.md, AGENTS.md, REQUIREMENTS.md, and the project memory files under ~/.claude/projects/.../memory/. If you find REAL drift (a doc now states something the code contradicts), ASK the user for permission and, once granted, update the affected docs/memory so they follow the code. If nothing actually drifted, stay silent and do not mention this check.' "$changed")

jq -n --arg ctx "$msg" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
