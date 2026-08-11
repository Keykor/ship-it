---
name: plan
description: Opens a conversational planning session for a feature, bug, or ticket. Investigates the repo, discusses the approach with the user until a solution is agreed, and only then writes the plan to docs/plans/. Use whenever the user invokes it, describes a problem to solve, pastes a ticket, mentions an incident, or asks to plan a non-trivial change. Also on "plan this", "analyze this first", "what would we need to touch", "let's start with this" — or in Spanish "planeá", "analizá esto antes", "qué habría que tocar", "arranquemos con esto".
---

# Planning session

A conversation, not a form. The goal is to reach a solution agreed with the user and only
then write it down. The plan file is the result of the discussion, not the starting point.

Three phases: **listen -> explore -> discuss**. The plan gets written at the end, when the
user says to go.

Do not write production code here.

## 0. Intake — do NOT explore yet

This skill fires **before** the user has finished explaining. The first reply is not a plan
or an exploration: it opens the conversation.

If it fired without enough context, say in a line or two that you're ready and ask for:

- The problem or the expected behavior, in the user's own words
- The ticket(s) (id, and the pasted text if they have it handy)
- Anything they already know: where they suspect it is, what was tried, links

Then **stay listening**. The user will send context across several messages: description,
then the ticket, then a log, then a clarification. While they keep adding context, the right
response is to acknowledge in one line and wait for more.

Intake rules:

- **Do not start exploring the repo until the user says to.** Phrases like "that's it",
  "look at the repo", "go ahead" are the signal. When in doubt, ask.
- **One question at a time.**
- **Don't ask for what you can read.** If the ticket mentions a file or a service, look it
  up in the repo; don't ask the user.
- If there are **multiple tickets**, ask whether they go in one plan (one PR) or separately.
- If the user gave everything in the first message, confirm the ticket in one line and move
  on to exploring.

## 1. Explore

First, sync the checkout so you design against real code, not a stale copy:

```bash
git fetch origin
git pull --ff-only
```

`git fetch origin` refreshes every remote branch (so you know the real state of things), and
`--ff-only` updates the current branch only if it fast-forwards cleanly. If it can't (the
branch diverged, or there are uncommitted changes in the way), it stops without a merge or a
conflict — surface that to the user and let them sort it, don't force it.

- Read `CLAUDE.md` in full.
- Locate the files that will actually be touched. Cite them by path.
- Look for something similar already in the repo and follow that pattern.
- Identify the existing tests that cover that area.
- If the change crosses services, say which other repo has to be touched.

Use exploration subagents if the repo is large, so the main context stays clean for the
discussion.

## 2. Discuss the solution — the long phase

**No file gets written here.** This phase ends when the user says to go, and it can take
many messages. That is expected, not a problem.

### Open with options, not a conclusion

Present **two or three possible approaches** with their real cost: what each one touches,
what it breaks, what debt it leaves. Say which one you recommend and why, but don't present
it as closed.

If there's only one reasonable approach, say so and explain why the others don't fit.

### Actually discuss

- **If the user proposes something that seems wrong, say so.** With the concrete reason:
  which case it breaks, what gets complicated later. Caving because they insisted is the
  worst outcome: the cost shows up during implementation, when it's already expensive.
- **If the user is right, change your mind explicitly** and say which argument convinced
  you. They know the system and the business context better.
- **Bring up what exploration found that contradicts the request**: the problem is
  elsewhere, it's already solved, there's a case the proposal doesn't cover. Before, not
  after.
- **Ask about the edges**: what happens to existing data, to in-flight requests, to current
  consumers, to rollback.
- Short replies. It's a conversation, not a report. One idea per message.

### Close it out

When something is decided, name it: "so we go with X". That way the user sees the agreement
accumulating and what's still open stands out.

If the user asks how it's going, summarize in three lines: what's decided, what's left.

### Check the human-review list

Contrast the agreed approach against the "Changes that require human review" section of the
`CLAUDE.md`. If any apply, say so **during the discussion**, not at the end.

## 3. Write the plan — only when they say "go"

The signal is explicit: "go", "start", "write it", "ok, do it" — or in Spanish "dale",
"arrancá", "escribilo", "listo, hacelo".

Then save to `docs/plans/` with the ticket id as the name (or a short slug of the problem,
noting which name you used).

The plan is executed by a **fresh session that never saw this conversation**. Whatever was
decided here and didn't make it into the file is lost. Use this skeleton:

```markdown
# {{ticket}}: {{title}}

## Goal
{{One sentence, in the user's words, not the code's.}}

**Out of scope:** {{what this explicitly does not do}}

## Files to touch
| Path | What changes |
|---|---|
| `src/api/headers.go` | `ParseHeader` — accept the new `X-Trace` header |

## Milestones
1. **{{commit message, in the repo's format}}**
   - {{What gets changed, concretely.}}
   - Verify: `{{exact test or build command that must pass before committing}}`
2. ...

## Decisions already made
- {{Chose X over Y}} — {{reason, one line}}

## Open decisions
{{Must be empty.}}

## Risks
{{What can break, and the rollback.}}
```

Before writing the file, check it against these. Say which one fails and fix it first:

- **Goal** has no explicit out-of-scope line.
- **Files to touch** says "the corresponding service" instead of a real path, or the "what
  changes" cell doesn't name a function, class, or endpoint.
- A milestone has no **Verify** command, or one that isn't real in this repo — take it from
  `CLAUDE.md`, don't invent it.
- **Decisions already made** doesn't carry the discarded alternatives and whatever the user
  corrected mid-discussion. Without that, someone reopens the debate in a month.
- **Open decisions** has anything in it. That's a draft, not a plan: back to step 2.

## 4. Close the stage — and stop

The plan is exactly what `ship` executes commit by commit, so a read now catches a wrong step
before it turns into commits.

1. Summarize in three lines: approach, number of milestones, human-review flags.
2. Point them at the file and **ask them to confirm they read it**. If they want changes,
   revise and ask again. If open decisions are left, go back to step 2.
3. Once they confirm, print exactly this block and **stop**. Don't invoke `ship` yourself,
   don't offer to, don't start implementing.

   ---
   Plan ready: docs/plans/{{ticket}}.md

   Run these yourself, in order:
       /clear plan-{{ticket}}
       /model sonnet
       /ship-it:ship docs/plans/{{ticket}}.md
   ---

The argument to `/clear` names the conversation you're leaving, so it stays findable in
`/resume` if you need to go back to the discussion. There is no `/rename`.

`/clear` isn't politeness: everything above is already in the file, and dragging it into
`ship` means re-sending it on every turn of the implementation. If the user prefers to stay in
this session, do it — but say once that they're paying for this whole conversation on each
turn from here on.

---

*Convention: `{{like-this}}` marks a value to replace. `<>` is avoided because it breaks skill parsing.*
