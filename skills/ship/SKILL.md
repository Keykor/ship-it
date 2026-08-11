---
name: ship
description: Takes an approved plan from docs/plans/ and drives it to an open PR. Implements it by milestones in an isolated worktree, commits per milestone in the repo's style, and opens the PR against the repo's base branch. Use whenever the user approves a plan, says "ship it", "go", "start", "implement it", "do it", or asks to open a PR for already-planned work — or in Spanish "dale", "arrancá", "implementalo", "hacelo".
argument-hint: "[path-to-plan]"
disable-model-invocation: true
---

# Implement and open the PR

Takes the plan at `$0` and drives it to an open PR.

**Precondition:** the plan exists, is approved, and its "Open decisions" section is empty. If
there's no plan, don't improvise: run the `plan` skill first.

Run `/model sonnet` if the session isn't on it already — this is execution, not analysis.

## 0. Read the plan — and only the plan

Read `$0` in full. If no argument came in, find it in `docs/plans/` and say which one you
picked.

The plan is written to be self-sufficient: it names the exact files, what changes in each,
the milestones with their commit messages, the verification command per milestone, and the
decisions already closed. **Don't explore the repo to rebuild context that's already there,
and don't reopen a decision listed under "Decisions already made".**

Read the repo's `CLAUDE.md` too: the **base branch**, the **branch-naming** convention, and
the **commit format** come from its "Git and PRs" section. Don't assume `main`/`master`/`test`.
Resolve the GitHub repo once:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner   # -> {{owner}}/{{repo}}
```

## 1. Prepare — in an isolated worktree

Implementation always runs in its own worktree, so two ships in the same repo never fight
over the working tree. Use the **EnterWorktree** tool (plain `git worktree add` fails under
the sandbox, which can't write `.git/`):

```
EnterWorktree  name: {{ticket}}
```

It lands in `.claude/worktrees/{{ticket}}` on a branch named `worktree-{{ticket}}`, based on
the repo's default branch — neither of which is what this repo uses. Fix both in one step:

```bash
git fetch origin
git switch -C {{type}}/{{ticket}}-{{slug}} origin/{{base}}
```

`{{base}}` is the base branch from `CLAUDE.md`. `{{type}}` (`feature`/`fix`/`chore`) comes
from the nature of the ticket. `{{slug}}` is short, lowercase, hyphenated.

Two things to know about being inside the worktree:

- The session **cannot touch the shared checkout** — a `git -C` back to it is refused. That's
  the isolation working, not a bug.
- The plan file lives in the main checkout and does **not** exist here (it's untracked, so it
  doesn't travel). That's why step 0 reads it first. Don't go looking for it.

If `.claude/worktrees/` isn't in the repo's `.gitignore`, add it in the first commit — a live
worktree otherwise shows up as `?? .claude/` in everyone's `git status`.

## 2. Implement, milestone by milestone

For **each** milestone of the plan, in order:

1. Implement just that milestone.
2. Run its **Verify** command — the exact one the plan specifies for it.
3. **If it fails, stop there.** Fix it before moving on; don't accumulate debt between
   milestones and don't commit a red milestone.
4. Commit with the message the plan gives for that milestone, in the repo's commit format.

Rules:

- **Don't go out of the plan's scope.** If ugly code or an adjacent bug shows up, note it for
  the PR's "Notes" section; don't fix it.
- If the plan turns out to be wrong: **stop**, tell the user what's wrong and what you'd
  change, and wait. Don't drift silently, and don't rewrite the plan on your own — it was
  agreed in a conversation you weren't part of.
- The plan's tests get written, not left for later.

## 3. Pre-PR check

- Full test suite green.
- Lint clean.
- `git diff origin/{{base}} --stat` — check nothing extra slipped in (local config, `.env`,
  build artifacts, `settings.local.json`).
- No secrets, tokens, credentials, or internal endpoints hardcoded in the diff.

## 4. Open the PR

```bash
git push -u origin HEAD
gh pr create --base {{base}} --title "{{ticket}}: {{title}}" --body-file {{temp file}}
```

The plan is a local artifact and never gets committed, so the PR body is the only place the
reviewer sees the agreed criteria. Carry it over:

```markdown
## What it does
{{Two or three lines.}}

## Goal and scope
{{The plan's Goal, verbatim.}}

**Out of scope:** {{the plan's out-of-scope line, verbatim}}

## How to test it
{{Concrete steps to verify by hand.}}

## Notes for the reviewer
{{Non-obvious decisions, taken from the plan's "Decisions already made". Things left out of
scope on purpose. The plan's risks, if it had any.}}
```

If the plan was flagged as requiring human review, or the change touches anything on the
"Changes that require human review" section of the repo's `CLAUDE.md`:

```bash
gh pr edit {{n}} --add-label "needs-human"
```

and say so in the final message.

**Always request Copilot's review**, regardless of whether the PR is `needs-human`. They're
two different things: the label is about who can merge, Copilot's review is an automatic pass
that goes either way. The plugin bundles the script that does it (its `bin/` is on your
`PATH`), so call it by name:

```bash
wait-for-review.sh --request {{n}}
```

It requests the review and exits. If it fails, **say so and don't print the handoff below** —
either Copilot code review isn't enabled on this repo, in which case `watch` would sit there
forever waiting for a review nobody is going to write, or `gh` can't reach GitHub. The script
prints which.

## 5. Tear the worktree down

The work is on origin now, so the worktree has done its job. Leaving it alive is not free:
git refuses to check that branch out anywhere else, so the next session's `fix` can't work.

**First prove the branch is pushed**, then remove:

```bash
git ls-remote --heads origin {{type}}/{{ticket}}-{{slug}}   # must print a sha
git status -sb                                              # must not say "ahead"
```

```
ExitWorktree  action: remove  discard_changes: true
```

`discard_changes: true` is required because the commits aren't on the original branch — they
are on origin, which is why this is safe. **If either check above came back empty or showed
unpushed work, do not remove it.** Say so and leave the worktree alone.

## 6. Close the stage — and stop

Return **only** the PR URL and one line about what's left for human review, if anything.
Don't summarize the work: the user sees it in the PR.

Then print exactly this block and **stop**. Don't invoke `watch` yourself, don't offer to,
don't start watching the review here.

   ---
   PR open: {{url}}

   Run these yourself, in order:
       /clear ship-{{ticket}}
       /ship-it:watch {{n}}
   ---

Everything above — the plan, every file read, every diff — is already in the commits and the
PR. Carrying it into the review rounds means re-sending all of it on every turn, twice over
if there are two rounds. That is the most expensive context in the whole flow.

Never merge. The merge to the base branch is always done by a person.

---

*Convention: `{{like-this}}` marks a value to replace. `<>` is avoided because it breaks skill parsing.*
