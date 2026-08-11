---
name: watch
description: Hands off waiting for a PR review to a detached shell process, so no Claude session burns context waiting. Use right after opening a PR with `ship`, and whenever the user says "wait for the review", "let me know when Copilot answers", "keep going with the PR", or asks to leave the PR review cycle running — or in Spanish "quedate esperando el review", "avisame cuando Copilot conteste", "seguí vos con el PR".
argument-hint: "[pr-number] [notify|auto]"
allowed-tools: Bash(gh *) Bash(command *)
---

## Context

- PR on this branch: !`gh pr view --json number,url,title --jq '"#\(.number) \(.title) — \(.url)"' 2>/dev/null || echo "none for this branch"`
- Watcher script: !`command -v wait-for-review.sh >/dev/null && echo "on PATH" || echo "MISSING — the plugin's bin/ isn't on PATH"`

# Hand the wait off and stop

This skill **does not wait for the review**. Waiting inside a Claude session re-sends the
entire context every time the session resumes, which is the single most expensive thing in
this flow. A shell process waiting costs nothing.

Your whole job is to give the user the exact command and then stop.

1. PR number: `$0` if given, otherwise the one in the context block. If there's neither, say
   so and stop.
2. If the script is missing, say so and stop. Don't write your own.
3. Mode: `$1` if given, otherwise `notify`.
4. Print exactly this block, with the values filled in, and **stop**:

   ---
   Launch the watcher from this repo, in your own terminal:

       nohup wait-for-review.sh {{n}} {{mode}} >/dev/null 2>&1 &

   notify — pings you when a review lands, then exits. You run the fix.
   auto   — runs `claude -p "/ship-it:fix {{n}}"` itself: commits and pushes unattended.

   When it pings, come back with a clean session:
       /clear watch-{{n}}
       /ship-it:fix {{n}}

   Log: /tmp/watch-review-{{n}}.log
   ---

5. One line after it: this session is done, close or clear it.

## Limits

- **Don't poll with Bash from this session.** Every check is a turn carrying the whole
  context. That is the exact cost this skill exists to avoid.
- **Don't put the wait in a subagent or `context: fork`.** A subagent is another instance
  with its own context window, burning tokens until it exits. Moving the wait there doubles
  it, it doesn't save anything.
- **Don't run the watcher through the Bash tool**, backgrounded or not. It has to outlive
  this session, and `nohup` in the user's own terminal is what does that.
- Don't touch the PR or the code here. This is handoff only.

---

*Convention: `{{like-this}}` marks a value to replace. `<>` is avoided because it breaks skill parsing.*
