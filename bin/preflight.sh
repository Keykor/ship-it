#!/usr/bin/env bash
# Checks the tools the ship-it flow needs, prints a short report, and exits
# non-zero if something required is missing. Uses `gh`, so if you run Claude
# Code's sandbox, run this outside it (the `onboard` skill does that).
#
# Usage: preflight.sh

set -uo pipefail

fail=0
check() { # name  test-command  fix-hint
  if eval "$2" >/dev/null 2>&1; then
    printf '  ok    %s\n' "$1"
  else
    printf '  MISS  %s -- %s\n' "$1" "$3"
    fail=$((fail + 1))
  fi
}

echo "ship-it preflight:"
check "gh (GitHub CLI) installed" "command -v gh"   "install: https://cli.github.com"
check "gh authenticated"          "gh auth status"  "run: gh auth login (outside the sandbox)"
check "jq installed"              "command -v jq"   "install: brew install jq"
check "inside a git repo"         "git rev-parse --is-inside-work-tree" "cd into a git repo"
check "git remote 'origin' set"   "git remote get-url origin"           "add one: git remote add origin <url>"

# Copilot code review has no reliable API to probe, so we can't verify it here.
echo "  note  GitHub Copilot code review must be enabled on the repo/org for watch + fix"
echo "        to have anything to react to (can't be auto-checked)."

if [ "$fail" -gt 0 ]; then
  echo "preflight: $fail required item(s) missing -- fix the above before running the flow."
  exit 1
fi
echo "preflight: all good."
