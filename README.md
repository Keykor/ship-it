# ship-it

The way I take a change from "che, habría que hacer X" to an open PR — wrapped up as a Claude
Code plugin.

Five skills that pass the baton to each other: figure out the repo, plan the change, build it,
open the PR, and chase down the review. It's just *my* flow. Grab it, rename stuff, rip out what
you don't use, bend it into whatever works for you.

The one bit worth keeping: the skills don't hardcode anything repo-specific. They read each
repo's `CLAUDE.md` for the details (base branch, commit style, what needs a human), so the same
flow works everywhere.

## What the flow does

```
onboard  ->  plan  ->  ship  ->  watch  ->  fix
```

1. **onboard** — first time in a repo, it reads the code and writes a `CLAUDE.md`: build/test
   commands, PR base branch, commit style, and what changes need a human. That file is the
   config the rest of the flow reads. Skip it if the repo already has one.
2. **plan** — a real back-and-forth before any code. It pokes around the repo, throws you a
   couple of approaches, argues the trade-offs, and only when you say "go" writes the plan to
   `docs/plans/<ticket>.md`.
3. **ship** — takes that plan, builds it one milestone at a time, commits in the repo's
   style, runs the tests, opens the PR against the base branch, and hands off to `watch`.
4. **watch** — asks Copilot for a review and waits in the background. When it lands, it
   kicks off `fix` and loops — two rounds tops, then it steps back for a human.
5. **fix** — sorts each comment into accept / reject / needs-a-human, fixes the accepted
   ones (one commit per topic), replies to every thread, and pushes.

Every skill fires from natural phrases in English or Spanish (the triggers live in each skill's
`description`). The instructions are written in English because agents follow them a little more
reliably — but you keep talking to it however you want, and commits/PRs follow the repo's
`CLAUDE.md`, not the skill.

## What you need

- **Claude Code** — it's a Claude Code plugin.
- **[GitHub CLI](https://cli.github.com) (`gh`), logged in** — `gh auth login` once. `ship`,
  `watch`, and `fix` do everything through `gh`.
- **GitHub Copilot code review turned on** for the repo/org (Copilot subscription with PR review
  enabled). `watch` and `fix` are built around Copilot's review; without it `ship`
  still opens the PR fine, there's just nothing to react to. Want a different reviewer? See "Make
  it yours".
- **`jq`** — the review poller uses it (`brew install jq`).
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

Restart Claude Code. You get `/onboard`, `/plan`, `/ship`, `/watch`, `/fix`,
plus they fire from plain phrases like "plan this", "ship it", "atendé el review".

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

Skip it and everything still works — you'll just approve more commands.

### If you run the sandbox

`gh` trips on TLS inside Claude Code's sandbox (`x509: OSStatus -26276`), so `watch` runs
its review poller with the sandbox off — the one spot where the nested `gh` works. It's baked
into the skill, nothing to set up. Don't run the sandbox? Then this doesn't apply, ignore it.

## Quickstart

1. Install (above) and restart Claude Code.
2. In your repo, run `/onboard` — it preflights your setup (`gh` logged in, `jq`, a git remote)
   and writes a `CLAUDE.md`. Skip it if the repo already has one.
3. Describe a change, or say "plan this" — `plan` talks it through and writes
   `docs/plans/<ticket>.md`.
4. Say "ship it" — `ship` builds it and opens the PR, then `watch` takes over the
   review loop and hands each round to `fix`.

You keep talking to it however you like; the skills follow the repo's `CLAUDE.md`.

## Make it yours

- **Not Copilot?** The bot id and review query live in `skills/watch` and `skills/fix`.
- **More/fewer rounds?** The two-round cap is in `skills/watch` and `skills/fix`
  (`ai-round-*`).
- **Different plan folder or PR template?** `skills/plan` and `skills/ship`.
- **Rename a skill?** Rename its folder and the `name:` in its `SKILL.md`.

## Layout

```
.claude-plugin/
  marketplace.json     # marketplace "keykor" -> plugin "ship-it"
  plugin.json
skills/
  onboard/SKILL.md   # write the repo's CLAUDE.md
  plan/SKILL.md      # discuss + write docs/plans/<ticket>.md
  ship/SKILL.md      # build the plan, open the PR
  watch/SKILL.md     # wait for the review, loop into fix
  fix/SKILL.md       # apply/reject comments, reply, push
bin/
  preflight.sh         # checks gh / jq / git remote before you start
  wait-for-review.sh   # review poller (watch runs it with the sandbox off)
```

## License

MIT — see [LICENSE](LICENSE).
