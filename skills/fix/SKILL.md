---
name: fix
description: Processes a PR's review comments (Copilot or human), classifies them, applies the fixes that belong, replies to each thread, and pushes. Use whenever the user says "address the review", "fix what Copilot said", "handle the comments", mentions Copilot already reviewed a PR, or passes a PR number/URL with pending reviews — or in Spanish "revisá los comentarios", "arreglá lo que dijo Copilot", "atendé el review".
argument-hint: "[pr-number]"
disable-model-invocation: true
allowed-tools: Bash(gh *)
---

## PR #$0

- Argument: !`case "$0" in ''|*[!0-9]*) echo "MISSING — invoke as /ship-it:fix <pr-number>";; *) echo "PR $0";; esac`
- !`gh pr view $0 --json number,title,url,state,labels --jq '"\(.title) [\(.state)] \(.url) — labels: \(if (.labels|length) == 0 then "none" else ([.labels[].name] | join(", ")) end)"' 2>&1`
- Threads: !`gh pr view $0 --comments 2>&1`
- Inline: !`gh api repos/{owner}/{repo}/pulls/$0/comments --paginate --jq '.[] | "id=\(.id) \(.path):\(.line // .original_line) by \(.user.login)\(if .in_reply_to_id then " reply-to=\(.in_reply_to_id)" else "" end)\n\(.body)\n---"' 2>&1`

**If the Argument line says MISSING, stop right there** and ask for the PR number. An
unsubstituted `$0` doesn't come through empty — the shell expands it to the process name, so
every command below quietly queried a PR called `bash`. Everything they returned is garbage.

Otherwise: that block was fetched before you read anything, so the comments are already here —
**don't re-fetch them**. If any line came back with an error instead of data, say what failed
and stop.

`gh api` expands `{owner}/{repo}` from the current repo on its own, so there's nothing to
resolve first.

# Address review comments

Turn the comments above into commits or into justified replies. **Two automatic rounds max**;
the third is for a human.

## 1. Determine the round

From the labels in the context block:

- No `ai-round-*` label -> this is **round 1**.
- Has `ai-round-1` -> this is **round 2**.
- Has `ai-round-2` -> **STOP**. Don't touch code. Go straight to step 5 (escalate).

The `needs-human` label does **not** stop this skill: it means a human does the merge, not
that comments go unaddressed. Both Copilot rounds run anyway. The only things that stop the
rounds are `ai-round-2`, or a comment landing in the "Human" group (step 3).

## 2. Get on the branch

```bash
gh pr checkout $0
```

Discard threads already resolved and comments already answered in earlier rounds. Copilot
tends to repeat comments that were already dismissed: if a previous thread has a justified
rejection, don't reopen it.

You have the comments but not the diff. Read only the files a comment actually points at.

## 3. Classify each comment

Before touching anything, classify **all** comments into three groups and show the user the
classification:

| Group | Criterion | Action |
|---|---|---|
| **Accept** | Real bug, concrete risk, or a `CLAUDE.md` convention broken | Fix it |
| **Reject** | False positive, generic style suggestion that contradicts `CLAUDE.md`, or out-of-scope refactor | Reply to the thread with the reason, don't touch code |
| **Human** | Touches something on the "Changes that require human review" list, or implies a design decision the plan didn't make | Don't touch. Goes to step 5 |

Core criterion: **a comment is not an order**. Rejecting with an argument is a valid response
and preferable to a mechanical fix that dirties the diff.

## 4. Apply and reply

For the "Accept" group:
- Fix it. One commit per topic, not one "fix review comments" commit with everything in it.
- Run lint and tests after each fix.
- Reply to the thread saying what changed and in which commit.

For the "Reject" group:
- Reply to the thread with the concrete reason. No bare "doesn't apply".

```bash
gh api repos/{owner}/{repo}/pulls/$0/comments/{{comment_id}}/replies -f body="{{reply}}"
```

The PR number belongs in that path. `pulls/comments/{{id}}` without it is a valid route for
reading or editing a comment, which makes the shorter form look right — but replying to one
returns 404.

Then:

```bash
git push
gh pr edit $0 --add-label "ai-round-{{N}}" --remove-label "ai-round-{{N-1}}"
```

## 5. Escalate what doesn't resolve itself

If there are "Human" group comments, or this was round 3:

```bash
gh pr edit $0 --add-label "needs-human" --add-assignee "@me"
```

And leave **one** comment on the PR with the status:

```markdown
## Pending human review

- [ ] {{comment/topic}} — {{why it needs a human decision}}

Automatic rounds completed: {{N}}/2
Auto-resolved this round: {{count}} fixes, {{count}} justified rejections.
```

## 6. Close the stage — and stop

Report in three lines: how many were fixed, how many rejected and why, and what's left for
the user.

Then print the block that matches how this round ended, and **stop**. Don't invoke `watch`
yourself and don't start another round.

If you pushed fixes and rounds are left — Copilot does **not** re-review on its own, so the
next `watch` is what re-requests it:

   ---
   Round {{N}} pushed: {{url}}

   Run these yourself, in order:
       /clear fix-{{n}}-round-{{N}}
       /ship-it:watch {{n}}
   ---

If nothing is pending and the PR is green, say so in one line — that's the merge signal, and
there's nothing to hand off. Same if you escalated: name what needs them and stop there.

Never merge.

---

*Convention: `{{like-this}}` marks a value to replace. `<>` is avoided because it breaks skill parsing.*
