---
name: onboard
description: Creates or updates a repo's agent instructions (AGENTS.md, with CLAUDE.md pointing at it) by exploring the code and adding the standard workflow sections (git/PR rules, changes that require human review, which docs must stay in sync with which code). Use whenever the user is starting in a new repo, says "set up the CLAUDE.md", "onboard this repo", "there's no CLAUDE.md here", or asks to complete or improve an existing one — or in Spanish "armá el CLAUDE.md", "iniciá este repo", "falta el CLAUDE.md acá". Also run it before the first time `plan` runs in a repo that has no CLAUDE.md yet.
---

# Build the repo's agent instructions

Produce the file that every agent reads on this repo, combining two things: what you discover
by reading the code, and the fixed sections the `plan` -> `ship` -> `watch` flow needs.

It goes in `AGENTS.md`, with `CLAUDE.md` symlinked to it — see step 3 for why.

If one already exists, **do not overwrite it**: fill in what's missing and flag what's stale.

## 0. Preflight the setup

Before anything, check the tooling the flow needs:

```bash
preflight.sh
```

(The plugin bundles this script and puts its `bin/` on your `PATH`, so call it by name.) Run
it with the sandbox off if you use Claude Code's sandbox (it calls `gh`). It reports any
missing piece (`gh` not installed or not logged in, no `jq`, no git remote) with the fix for
each. If something required is missing, tell the user and stop until it's sorted — the rest of
the flow just fails on `gh` otherwise.

## 1. Explore (what you discover on your own)

Refresh first so you read the real state, not a stale checkout: `git fetch origin` (updates
every remote branch). Then read, don't guess:

- Build manifests: `go.mod`, `pom.xml`, `build.gradle`, `package.json`, `Makefile`,
  `Taskfile.yml`. The real build, test, and lint commands come from here.
- CI: `.github/workflows/`. **The commands CI runs are the source of truth** for how this
  repo builds and tests; they win over whatever the README says.
- `README.md`, `CONTRIBUTING.md`, `docker-compose.yml`, `Dockerfile`, k8s charts.
- `git log --oneline -50` to infer the real commit-message format, not the documented one.
- `git branch -r` to see which branch work actually targets (this is the PR base branch
  that `ship` will read back).
- Package/module layout: the **rule** of organization, not the list of folders.
- Config: where env vars come from and how a new one is added.
- `docs/` and the repo root, for **docs meant to be read by agents** — protocols, which
  services this one talks to, what has to be complied with, decision records. Also machine-
  readable contracts, which beat prose every time: OpenAPI/AsyncAPI specs, a Backstage
  `catalog-info.yaml`. List what you find; you'll confirm with the user in step 2.

Rule: if a command couldn't be confirmed by reading something, don't invent it. Leave it as
`{{fill-in}}` and tell the user which ones are pending.

## 2. Ask (what isn't in the code)

These can't be deduced from the repo and are what make the file worth having. Ask them
together, in one message, with a tentative proposal for each:

1. **PR base branch** and branch-naming convention.
2. **Which changes require human review** in *this* service. Propose a starting point based
   on what you saw (migrations, contracts with other services, auth, running workflows, data
   deletion) and ask them to add or remove.
3. **Historical quirks**: odd decisions the code doesn't explain. Ask directly: "is there
   anything in this repo that would surprise someone new?"
4. **Which docs have to move with which code.** Show the agent-facing docs you found in
   step 1 and ask, for each: *what do you have to touch for this to go stale?* The answer is
   a pair — `src/api/**` -> `docs/protocolos.md` — and it's the only part of this that can't
   be derived. A doc nobody has to update is a doc that will be wrong in a month.

   If the repo has none, don't propose creating them. Maintaining is not the same as
   generating: an architecture doc written by an agent that never gets checked reads as
   authoritative and drifts silently. Only wire up what already exists and has an owner.

If the user doesn't want to answer now, leave those sections with a visible `{{fill-in}}`. A
marked gap beats an invented fact.

## 3. Write

Write **`AGENTS.md`** at the repo root, and point `CLAUDE.md` at it:

```bash
ln -s AGENTS.md CLAUDE.md
```

`AGENTS.md` is the cross-tool standard — Codex, Cursor, Copilot, Gemini CLI, Aider and others
read it, so one file serves every agent and chatbot instead of one file per tool. Claude Code
is the exception: it reads `CLAUDE.md` and **not** `AGENTS.md`, which is what the symlink is
for. (If you need Claude-only instructions, make `CLAUDE.md` a real file whose first line is
`@AGENTS.md` and put them underneath, instead of the symlink.)

If a real `CLAUDE.md` already exists, don't move it on your own: offer `git mv CLAUDE.md
AGENTS.md` plus the symlink, and if the user says no, just keep writing `CLAUDE.md`. Nothing
else in the flow cares — the other skills read `CLAUDE.md` and the symlink resolves.

File structure, in this order:

1. What this service is (2-3 lines), stack, infra
2. Commands (build, tests, lint, local dependencies)
3. Git and PRs (base branch, naming, commit format, PR body)
4. **Where to look** — the pointer table, see below
5. Code conventions (errors, logging, config, tests, structure, prohibitions)
6. **Changes that require human review**
7. How we work (plan first, don't refactor out of scope, ask when in doubt)
8. Context that isn't in the code

Writing criteria:

- **Target: under 150 lines.** This file is re-sent on every turn of every session in this
  repo, so it is the most expensive text in the project. Treat the limit as a budget.
- Every line must change the agent's behavior. If it's true but changes nothing, cut it.
- Write explicit prohibitions, not just recommendations. "Don't add dependencies without
  asking" is worth more than "use dependencies judiciously".
- Nothing task-specific. That goes in `docs/plans/`, not here.

**Write only what can't be read off the code.** Conventions that depart from the language's
defaults, pitfalls, the reasoning behind an odd decision, the git and PR rules. Directory
layouts, dependency lists and architecture overviews don't belong: an agent derives those by
reading the repo when it needs them, and in the file they cost context in *every* session,
including the ones that never touch that area.

Three things go somewhere else instead:

| Content | Where | Why |
|---|---|---|
| A procedure (how a release is cut, how a migration runs) | A skill | Loads only when it's used |
| Anything that applies to one part of the repo | `.claude/rules/{{name}}.md` with `paths:` globs in its frontmatter | Loads only when files matching the globs are in play |
| Anything task-specific | `docs/plans/` | Not permanent context |

Don't use `@path/to/file.md` imports to shrink the file. Imported files are pulled in at
startup just the same, so the context cost is identical — it only looks smaller. `paths:`
rules are the mechanism that actually defers loading.

### The "Where to look" table

The repo's agent-facing docs (step 2, question 4) go in as **pointers, never as imports**. One
row each, saying *when* to open it — not what it says:

```markdown
## Where to look

| Before you... | Read |
|---|---|
| touch a boundary between services | `docs/protocolos.md` |
| add or change an external dependency | `docs/servicios.md` |
| change behavior a contract depends on | the OpenAPI/AsyncAPI spec, not the prose |
```

Three or four lines of fixed cost, and the content itself costs nothing until something
actually needs it. `@docs/arquitectura.md` would cost the whole file in every session — and
`/doctor` is explicitly built to strip architecture overviews out of this file, so an import
is work you'd be asked to undo.

Prefer a machine-readable contract over prose wherever one exists: an OpenAPI or AsyncAPI
spec, or a `catalog-info.yaml`, is parsed unambiguously and can't quietly disagree with the
code the way a hand-written protocol doc does.

### Wire the pairs so the docs stay true

For each code -> doc pair from step 2, question 4, write it in **both** places:

1. `.claude/rules/{{name}}.md`, when the code side is a glob:

   ```markdown
   ---
   paths:
     - "src/api/**"
   ---

   Changing anything here changes a published contract. Update `docs/protocolos.md` in the
   same commit.
   ```

2. `.github/copilot-instructions.md`, so the reviewer catches what slipped through:

   ```markdown
   - A PR that changes `src/api/**` without touching `docs/protocolos.md` is incomplete.
     Flag it.
   ```

The order matters: the rule makes `ship` update the doc while it's writing the code, and
Copilot is the net for what got past it. Only the net, and you find out at review time.

A pair that's transversal (protocols, compliance — no glob describes them) doesn't get a
rule. It lives in the pointer table and in Copilot's instructions only.

### If a CLAUDE.md already exists: move, never delete

Other tooling may depend on what's in there. Every line you take out has to land somewhere —
a rule file or a skill — and you have to report where it went. If something fits neither,
**leave it where it is** and say so. Trimming a file by deleting is not the job.

## 4. Leave the repo ready

```bash
mkdir -p docs/plans
```

Then make sure the repo's `.gitignore` has these two lines, appending them if missing (don't
rewrite the file, and don't touch anything else in it):

```gitignore
.claude/worktrees/
docs/plans/
```

- `.claude/worktrees/` — `ship` implements inside a worktree there. It is **not** ignored by
  default, so without this line a live worktree shows up as `?? .claude/` in everyone's
  `git status`. Ignore only that subdirectory: `.claude/settings.json` below is meant to be
  committed.
- `docs/plans/` — plans are a local working artifact, not product. They stay on disk so the
  flow can read them, and never reach the base branch on merge. The agreed criteria travel to
  the reviewer in the PR body instead, which is `ship`'s job.

If the repo uses GitHub Copilot review, `.github/copilot-instructions.md` has to exist — it's
where the code -> doc pairs from step 3 live. Create it if it's missing, append to it if it
isn't.

### Make the repo self-configuring (offer this)

So the flow runs without anyone editing their personal/global settings, offer to seed the
repo's committed `.claude/settings.json` with what the flow needs. **Merge** into it if it
already exists — never clobber existing keys or arrays.

```json
{
  "permissions": {
    "allow": ["Bash(git:*)", "Bash(gh:*)", "<the repo's build/test/lint/run commands>"],
    "deny": ["Bash(git push --force:*)", "Bash(git reset --hard:*)", "Bash(gh pr merge:*)"]
  },
  "sandbox": {
    "excludedCommands": ["git", "gh"]
  }
}
```

- The `allow` list is git/gh **plus this repo's platform-specific commands** — the ones you
  found in step 1 (`Bash(go test:*)`, `Bash(mvn:*)`, `Bash(npm run build:*)`, `Bash(gradle:*)`,
  etc.). Don't guess the stack: use what step 1 read, and **ask the user** which commands they
  run often that should never prompt (build, test, lint, run). A Go repo and a Java or JS repo
  get different lists.
- `excludedCommands` runs git/gh outside the sandbox — that fixes both the `gh` TLS failure
  inside the sandbox and git being unable to write, and because they run outside, the flow
  needs no user-level network knob.

Say two things before writing it: it's **committed**, so teammates inherit the same sandbox
exclusion in this repo (they can override it in their own `.claude/settings.local.json`); and
the sandbox's writable area is the folder Claude Code launched in, so it should be started from
inside the repo.

If the repo runs lint/format/tests through a Claude Code hook, put the real command (from step
1) in that same `.claude/settings.json`. Don't invent a hook that isn't there.

## 5. Close

Report in a few lines: what you discovered on your own, what's left as `{{fill-in}}`, the
user's answers you folded in, the code -> doc pairs you wired and where each one landed, and
— if the file already existed — **a line per piece of content you moved, saying where it
went**.

Then tell them two things to run:

- `/context` in a fresh session here, to see what the file actually costs at startup.
- `/doctor`, which reviews an existing `CLAUDE.md` and proposes cuts.

And that the real test is the first `plan` run: that's where a missing piece shows up.

---

*Convention: `{{like-this}}` marks a value to replace. `<>` is avoided because it breaks skill parsing.*
