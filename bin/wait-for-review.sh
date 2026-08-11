#!/usr/bin/env bash
# Waits for a PR review to land, without a Claude session being alive for it.
#
# The wait happens in bash, which costs nothing. A Claude session that sits
# waiting re-sends its whole context every time it resumes, which is the most
# expensive thing in the plan -> ship -> review flow.
#
# Usage:
#   wait-for-review.sh --request <pr>     ask Copilot for a review and exit
#   wait-for-review.sh <pr> [notify|auto]
#
#   notify (default)  notifies you when a review lands, then exits. You run
#                     /ship-it:fix yourself in a fresh session. Nothing is
#                     touched without you looking.
#   auto              runs `claude -p "/ship-it:fix <pr>"` on its own, which
#                     commits and pushes unattended. Only use it on repos
#                     where you accept that.
#
# Env: INTERVAL=60  MAX_ROUNDS=2  TIMEOUT_MIN=90
#
# Requires gh (authenticated) and jq. Run it from the repo, in your own
# terminal — not through Claude's Bash tool. Detached is the point:
#   nohup wait-for-review.sh 123 notify >/dev/null 2>&1 &

set -uo pipefail   # deliberately not -e: every failure below is handled

# copilot-pull-request-reviewer: one global GitHub App id, stable across repos.
# The REST requested_reviewers endpoint rejects it with 422 (it isn't a
# collaborator), so requesting has to go through GraphQL with botIds.
COPILOT_BOT="BOT_kgDOCnlnWA"

usage() { echo "usage: $0 [--request] <pr-number> [notify|auto]" >&2; exit 1; }

REQUEST_ONLY=0
[ "${1:-}" = "--request" ] && { REQUEST_ONLY=1; shift; }
PR="${1:-}"; MODE="${2:-notify}"
[ -n "$PR" ] || usage
[ "$MODE" = notify ] || [ "$MODE" = auto ] || usage
for c in gh jq; do command -v "$c" >/dev/null || { echo "missing $c" >&2; exit 1; }; done

INTERVAL="${INTERVAL:-60}"
MAX_ROUNDS="${MAX_ROUNDS:-2}"
TIMEOUT_MIN="${TIMEOUT_MIN:-90}"
LOG="/tmp/watch-review-${PR}.log"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

notify() {
  printf '\a'
  if command -v osascript >/dev/null; then
    osascript -e "display notification \"$1\" with title \"PR #$PR\"" 2>/dev/null
  elif command -v notify-send >/dev/null; then
    notify-send "PR #$PR" "$1" 2>/dev/null
  fi
  return 0
}

# Copilot never starts a review on its own, and never re-reviews after a push.
# Every round has to ask. `union: true` makes asking twice harmless.
# Everything goes through typed GraphQL variables (-F) with the query in single
# quotes. Interpolating the ids into the query string instead is a quoting trap:
# one stray character and the server answers with a parse error that reads like
# a permissions problem.
request_review() {
  local nwo owner repo prid err
  nwo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"
  [ -n "$nwo" ] || { log "ERROR: gh can't resolve the repo (wrong directory, or not logged in)"; return 2; }
  owner="${nwo%%/*}"; repo="${nwo##*/}"

  # On a GraphQL error the API still answers 200 and gh dumps the whole error
  # JSON to stdout, --jq and all. So validate the shape: a node id, nothing else.
  prid="$(gh api graphql -F owner="$owner" -F name="$repo" -F number="$PR" \
    -f query='query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number){ id } } }' \
    --jq '.data.repository.pullRequest.id' 2>/dev/null)"
  if [[ ! "$prid" =~ ^[A-Za-z0-9_=-]+$ ]]; then
    log "ERROR: no PR #$PR in $nwo (or gh can't reach GitHub)"
    return 2
  fi

  if err="$(gh api graphql -F prid="$prid" -F bot="$COPILOT_BOT" \
    -f query='mutation($prid:ID!,$bot:ID!){ requestReviews(input:{pullRequestId:$prid, botIds:[$bot], union:true}){ clientMutationId } }' 2>&1)"; then
    log "review requested from Copilot"
    return 0
  fi

  log "ERROR: could not request the review -- ${err//$'\n'/ }"
  # The most common cause by far: the bot id can't be requested when Copilot
  # code review isn't turned on. Waiting would then never end, so stop either
  # way -- but report the real error above rather than assuming this one.
  log "       if that looks like a permissions problem, enable Copilot code review"
  log "       (Settings > Copilot > Code review, or a 'Copilot code review' rule"
  log "       under Settings > Rules > Rulesets)."
  return 1
}

# Reviews plus comments. If the count moves, somebody reviewed -- Copilot or a
# human, which is why this counts both instead of filtering by author.
fingerprint() {
  gh pr view "$PR" --json reviews,comments --jq '"\(.reviews|length):\(.comments|length)"' 2>/dev/null
}

failing_checks() {
  gh pr checks "$PR" --json state,name \
    -q '[.[] | select(.state=="FAILURE" or .state=="ERROR") | .name] | join(", ")' 2>/dev/null
}

run_fix() {
  local rc
  log "running /ship-it:fix in a fresh headless session"
  claude -p "/ship-it:fix $PR" --max-turns 40 \
    --allowedTools "Read,Edit,Write,Grep,Glob,Bash" >>"$LOG" 2>&1
  rc=$?   # must be captured before anything else runs
  log "fix exited with code $rc"
  return $rc
}

request_review || exit $?
[ "$REQUEST_ONLY" = 1 ] && exit 0

baseline="$(fingerprint)"
[ -n "$baseline" ] || { log "ERROR: can't read PR #$PR"; exit 2; }
deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
round=0

log "watching PR #$PR -- mode $MODE, every ${INTERVAL}s, giving up after ${TIMEOUT_MIN}min"

while [ "$round" -lt "$MAX_ROUNDS" ]; do
  sleep "$INTERVAL"

  if [ "$(date +%s)" -gt "$deadline" ]; then
    log "no review after ${TIMEOUT_MIN}min"
    notify "no review after ${TIMEOUT_MIN}min"
    exit 0
  fi

  state="$(gh pr view "$PR" --json state --jq .state 2>/dev/null)"
  if [ -n "$state" ] && [ "$state" != "OPEN" ]; then
    log "PR is $state now -- stopping"
    notify "PR is $state"
    exit 0
  fi

  # A red build outranks the review: fixing comments on top of it wastes a round.
  failed="$(failing_checks)"
  if [ -n "$failed" ]; then
    log "CI failing: $failed"
    notify "CI failing -- $failed"
    exit 0
  fi

  current="$(fingerprint)"
  [ -n "$current" ] && [ "$current" != "$baseline" ] || continue

  round=$(( round + 1 ))
  log "review landed ($baseline -> $current), round $round/$MAX_ROUNDS"
  baseline="$current"

  if [ "$MODE" = notify ]; then
    notify "review landed -- run /ship-it:fix $PR"
    log "in a fresh Claude Code session:  /clear  then  /ship-it:fix $PR"
    exit 0
  fi

  run_fix
  # fix pushed, so the counts moved on their own -- re-baseline before looking
  # again, or our own replies read as a new review round.
  sleep 20
  baseline="$(fingerprint)"
  request_review || exit $?
  deadline=$(( $(date +%s) + TIMEOUT_MIN * 60 ))
done

log "$MAX_ROUNDS rounds done -- the rest is yours"
notify "$MAX_ROUNDS rounds done, check the PR"
