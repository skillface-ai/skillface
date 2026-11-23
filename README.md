# Yokan

A macOS app that turns a skill into an app.

A skill is a good set of instructions with nowhere to live: every run starts from an empty
context, prints its state as text, and asks you to paste it back next time. Yokan gives a skill
an interface of its own, a memory that outlives every session, and sessions you can come back to.
The skill keeps doing the thinking.

Take [Socratic Tutor](https://github.com/janestreet/agent_skills/blob/master/socratic-tutor/SKILL.md).
As a skill it draws its skill map in ASCII and has a "save state" command. As a Yokan app the map
is on screen, kept in memory, and tomorrow's session starts from where today's stopped.

## The flow

1. **Drop a skill** on home, paste one or a link to one, or pick one Claude Code already has.
   A link to a GitHub repository, or a dropped folder of skills, makes one app from all of them.
2. **Read.** The builder reads the skill and asks what only you can answer, one question at a
   time, with the likely answers as buttons. Given a repository, it first reads all of it and
   works out the workflow its skills make: which starts, what each hands to the next.
3. **Draw.** It works out what kind of tool the skill is (a study tool, a review desk, a planner,
   a console…) and draws three versions for that job. You see them live, side by side, on sample
   data, and take one.
4. **Shape.** Say what to change in the one you chose until it's right, then ship it.
5. **Ship.** It writes what the running app needs (which memory to keep, and how) and checks
   its work. The app opens on its first session.

Home is that drop target with a dock of the apps you used last; **All apps** (⌘K) is the dock
risen into a sheet, with the box to find one already taking the keyboard. An open app fills the
window: its sessions run along the top as one lifeline, **What it knows** opens its memory beside
it as files you can read and put right, and **Reshape** goes back to the builder, in the session
the app was built in, so it knows what's there and why.

## How it works

An app is a folder in `~/Library/Application Support/Yokan/Apps/`:

| File | What it is |
|---|---|
| `SKILL.md` | The skill, as it was added, in an app made from one |
| `source/` | The repository, as it came, in an app made from several. Read-only |
| `APP.md` | What the builder adds for the running agent: which memory to keep, and how |
| `app.json` | Name, symbol, and how far the build is |
| `interface.html` | What you see: one self-contained page |
| `demo.json` | Sample memory and messages, for the design's preview |
| `designs/` | The versions the builder drew to choose from |
| `memory/` | What outlives every session |
| `work/` | Where its commands run and what they make, if you let it run any |
| `sessions/` | Every conversation, one JSON file each |

Both agents are your own [Claude Code](https://claude.com/claude-code), run headless and
contained: no shell, no web, none of your settings. The builder works in the app's folder with
six skills (`explore`, for a repository, then `interview`, `design`, `adjust`, `implement`, and
`interface`, the contract a page is written to). The app's own agent, and any subagents it hands work to, work in `memory/` and
nowhere else, so using an app can never change its skill or its interface. An app made from a
repository is told which skills it has and reads each from `source/` when its turn comes. Each session is a Claude Code session, resumed message by
message; a new one is started with the skill, `APP.md`, and the memory as it stands.

A skill that runs scripts needs a shell. An app gets one only when you turn on **Use the
Terminal** in its ••• menu, and then inside Claude Code's sandbox: no network but PyPI, for the Python packages a skill needs, and it can write
only in its `memory/` and `work/`. It can read most other files on your Mac. Python packages it
installs itself, into `work/`; anything else a script needs (Homebrew, LaTeX), it shows you
the command and runs it on your Mac once you approve it.

The interface is a web page that is handed `window.yokan` (the messages, the memory, `send`) and
nothing else. It loads nothing from the network and can't navigate.

## Commands

```sh
make run      # open Yokan
make check    # build + test
make shots    # .build/shots/*.png, every screen on sample data
make app      # .build/app/Yokan.app
```

`$YOKAN_HOME` moves everything Yokan keeps. The live test builds a real app with your Claude Code:
`YOKAN_LIVE=/tmp/yokan YOKAN_SKILL=path/to/SKILL.md swift test --filter Live`. With
`YOKAN_REPO=<link>` it fetches a real repository instead, which asks nothing of Claude Code.
