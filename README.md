# ship-it

The way I take a change from "che, habría que hacer X" to an open PR — wrapped up as a Claude
Code plugin.

Five skills that hand off to each other: figure out the repo, plan the change, build it,
open the PR, and chase down the review. It's just *my* flow. Grab it, rename stuff, rip out what
you don't use, bend it into whatever works for you.

The one bit worth keeping: the skills don't hardcode anything repo-specific. They read each
repo's `CLAUDE.md` for the details (base branch, commit style, what needs a human), so the same
flow works everywhere.

## What the flow does

```
onboard  ->  plan  ->  /clear  ->  ship  ->  /clear  ->  watch  ->  (ping)  ->  fix
```

1. **onboard** — first time in a repo, it reads the code and writes an `AGENTS.md` (with
   `CLAUDE.md` symlinked to it): build/test commands, PR base branch, commit style, what
   changes need a human, and which docs have to move when which code moves. That file is the
   config the rest of the flow reads. Skip it if the repo already has one.
2. **plan** — a real back-and-forth before any code. It pokes around the repo, throws you a
   couple of approaches, argues the trade-offs, and only when you say "go" writes the plan to
   `docs/plans/<ticket>.md`. Then it stops and tells you what to run next.
3. **ship** — takes that plan and builds it **in its own git worktree**, one milestone at a
   time, running each milestone's verification command before committing it. Opens the PR,
   tears the worktree down, stops.
4. **watch** — doesn't wait. It hands the waiting to a detached shell process and stops. That
   process pings you when a review lands (or when CI goes red, or when nothing shows up).
5. **fix** — sorts each comment into accept / reject / needs-a-human, fixes the accepted
   ones (one commit per topic), replies to every thread, and pushes. Two rounds tops, then a
   human takes over.

Every skill fires from natural phrases in English or Spanish (the triggers live in each skill's
`description`). The instructions are written in English because agents follow them a little more
reliably — but you keep talking to it however you want, and commits/PRs follow the repo's
`CLAUDE.md`, not the skill.

## Why it stops between stages

Each stage ends by printing what to run next, and going no further. That's deliberate, for two
reasons.

**Cost.** A Claude session re-sends its entire context on every turn. Carrying the planning
conversation into the implementation, and the implementation into two rounds of review, means
paying for all of it over and over. Every stage already leaves its result somewhere durable —
the plan file, the commits, the PR — so `/clear` between stages loses nothing and is free.
(`/compact` is not: summarizing costs a full read of everything you're summarizing.)

**Control.** `ship` and `fix` have side effects — they commit, they push, they reply on your
PR. Both are marked `disable-model-invocation`, so Claude can't decide to run them on its own.
You type `/ship` or you don't ship.

If you'd rather stay in one session, nothing stops you. The skills will say once what it costs
and then get on with it.

## What you need

- **Claude Code** — it's a Claude Code plugin.
- **[GitHub CLI](https://cli.github.com) (`gh`), logged in** — `gh auth login` once. `ship`,
  `watch`, and `fix` do everything through `gh`.
- **GitHub Copilot code review turned on** for the repo/org (Copilot subscription with PR review
  enabled). `watch` and `fix` are built around Copilot's review; without it `ship`
  still opens the PR fine, there's just nothing to react to. Want a different reviewer? See "Make
  it yours".
- **`jq`** — the review watcher uses it (`brew install jq`).
- **git** with push access.
- **macOS** for the sandbox notes below — on other platforms the flow still works, the `gh`/TLS
  workaround just may not apply.

## Install

Drop this into `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "keykor": {
      "source": { "source": "github", "repo": "Keykor/ship-it" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "ship-it@keykor": true
  }
}
```

Restart Claude Code. You get `/onboard`, `/plan`, `/ship`, `/watch`, `/fix`. `onboard`, `plan`
and `watch` also fire from plain phrases like "plan this" or "atendé el review"; `ship` and
`fix` only run when you type them.

### Nice-to-have settings (macOS)

`git` talks over SSH and `gh` trips on TLS inside Claude Code's sandbox, so excluding them keeps
the flow from asking permission on every call:

```json
{
  "sandbox": {
    "excludedCommands": ["git", "gh"]
  }
}
```

Skip it and everything still works — you'll just approve more commands. `onboard` offers to put
this in the repo's own committed `.claude/settings.json`, which is usually the better place.

## Quickstart

1. Install (above) and restart Claude Code.
2. In your repo, run `/onboard` — it preflights your setup (`gh` logged in, `jq`, a git remote),
   writes a `CLAUDE.md`, and adds the two `.gitignore` entries the flow needs. Skip it if the
   repo already has one.
3. Describe a change, or say "plan this" — `plan` talks it through and writes
   `docs/plans/<ticket>.md`.
4. `/clear`, then `/ship docs/plans/<ticket>.md` — builds it in a worktree and opens the PR.
5. `/clear`, then `/watch <pr>` — gives you a `nohup` line to paste in a terminal. Run it and
   walk away.
6. When it pings: `/clear`, then `/fix <pr>`.

You keep talking to it however you like; the skills follow the repo's `CLAUDE.md`.

## Things worth knowing

- **`ship` works in a worktree** under `.claude/worktrees/`, so two tickets in the same repo
  never fight over the working tree. It removes it once the branch is on origin — leaving it
  alive would stop `fix` from checking that branch out.
- **Plans aren't committed.** `docs/plans/` is gitignored: the plan is a working artifact, not
  product. What the reviewer needs (goal, scope, decisions) goes in the PR body instead.
- **The watcher is a shell script, not a session.** `bin/wait-for-review.sh` runs detached in
  your own terminal, costs nothing while it waits, and logs to `/tmp/watch-review-<pr>.log`.
  Its `auto` mode will run `fix` unattended — it commits and pushes without you looking, so
  only use it where you're fine with that. `notify` is the default.
- **Copilot never reviews on its own**, and never re-reviews after a push. Every round has to
  ask; that's `wait-for-review.sh --request <pr>`. If your repo doesn't have Copilot code
  review enabled, that call fails and says so instead of leaving you waiting forever.
- **`AGENTS.md`, not `CLAUDE.md`.** `AGENTS.md` is the cross-tool standard — Codex, Cursor,
  Copilot, Gemini CLI, Aider and others read it. Claude Code is the one that doesn't, so
  `onboard` symlinks `CLAUDE.md` to it and both work. An existing `CLAUDE.md` is left alone
  unless you agree to the move.
- **Agent-facing docs get pointed at, never imported.** `onboard` asks which docs go stale
  when which code changes, then writes each pair into a `paths:`-scoped rule (so `ship`
  updates the doc while writing the code) and into `.github/copilot-instructions.md` (so the
  review catches what slipped). The docs themselves stay out of startup context — an
  `@docs/architecture.md` import costs the whole file on every session, and `/doctor` is
  built to strip exactly that back out.

## Make it yours

- **Not Copilot?** The bot id and the review request live in one place: `bin/wait-for-review.sh`.
- **More/fewer rounds?** `MAX_ROUNDS` in `bin/wait-for-review.sh`, and the `ai-round-*` cap in
  `skills/fix`.
- **Don't want the worktree?** Drop the `EnterWorktree`/`ExitWorktree` steps in `skills/ship`.
- **Different plan folder or PR template?** `skills/plan` and `skills/ship`.
- **Want it to chain automatically again?** Delete the "Close the stage" section at the end of
  `plan`, `ship` and `fix`, and drop `disable-model-invocation` from their frontmatter.
- **Rename a skill?** Rename its folder and the `name:` in its `SKILL.md`.

## Layout

```
.claude-plugin/
  marketplace.json     # marketplace "keykor" -> plugin "ship-it"
  plugin.json
skills/
  onboard/SKILL.md   # write the repo's CLAUDE.md
  plan/SKILL.md      # discuss + write docs/plans/<ticket>.md
  ship/SKILL.md      # build the plan in a worktree, open the PR
  watch/SKILL.md     # hand the waiting off to a detached process
  fix/SKILL.md       # apply/reject comments, reply, push
bin/
  preflight.sh         # checks gh / jq / git remote before you start
  wait-for-review.sh   # requests the review, then waits for it outside Claude
```

## License

MIT — see [LICENSE](LICENSE).
