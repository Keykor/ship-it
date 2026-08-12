#!/usr/bin/env bash
# Waits for Copilot to review a PR, then prints ONE result line and exits.
#
# Meant to be run as a background Bash command with the sandbox DISABLED:
# `gh` (a Go binary) fails TLS verification inside the Claude Code sandbox
# (x509: OSStatus -26276), so the `watch` skill runs this via the Bash tool
# with run_in_background:true and dangerouslyDisableSandbox:true.
#
# Usage: wait-for-review.sh <pr-number> [max-minutes]
#
# Stays silent while waiting; on exit prints exactly one line:
#   RESULT=REVIEWED  detail=...
#   RESULT=CI_FAILED detail=...
#   RESULT=TIMEOUT   detail=...
#   RESULT=ERROR     detail=...

set -uo pipefail

PR="${1:?usage: wait-for-review.sh <pr-number> [max-minutes]}"
MAX_MIN="${2:-30}"
INTERVAL=30

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  echo "RESULT=ERROR detail=could not resolve repo with gh (no network/TLS? this must run outside the sandbox)"
  exit 0
fi

# Only reviews submitted after we start watching count.
SINCE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DEADLINE=$(( $(date +%s) + MAX_MIN * 60 ))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep "$INTERVAL"

  # A failing check takes priority over the review.
  FAILED="$(gh pr checks "$PR" --json state,name \
    -q '[.[] | select(.state=="FAILURE" or .state=="ERROR") | .name] | join(", ")' 2>/dev/null || echo "")"
  if [ -n "$FAILED" ]; then
    echo "RESULT=CI_FAILED detail=failing checks: ${FAILED}"
    exit 0
  fi

  # A Copilot review submitted after SINCE?
  HIT="$(gh api "repos/${REPO}/pulls/${PR}/reviews" --paginate \
    -q "[.[] | select(.user.login | ascii_downcase | test(\"copilot\")) | select(.submitted_at > \"${SINCE}\") | .state] | join(\",\")" \
    2>/dev/null || echo "")"
  if [ -n "$HIT" ]; then
    NCOM="$(gh api "repos/${REPO}/pulls/${PR}/comments" --paginate -q 'length' 2>/dev/null || echo "?")"
    echo "RESULT=REVIEWED detail=copilot review received (${HIT}); inline comments total: ${NCOM}"
    exit 0
  fi
done

echo "RESULT=TIMEOUT detail=no copilot review within ${MAX_MIN} minutes"
exit 0
