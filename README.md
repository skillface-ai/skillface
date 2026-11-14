# Yonka

A macOS app that turns a skill into an app.

A skill is a good set of instructions with nowhere to live: every run starts from an empty
context, prints its state as text, and asks you to paste it back next time. Yonka gives a skill
an interface of its own, a memory that outlives every session, and sessions you can come back to.
The skill keeps doing the thinking.

Take [Socratic Tutor](https://github.com/janestreet/agent_skills/blob/master/socratic-tutor/SKILL.md).
As a skill it draws its skill map in ASCII and has a "save state" command. As a Yonka app the map
is on screen, kept in memory, and tomorrow's session starts from where today's stopped.

## The flow

1. **New App.** Paste a skill, a link to one, or pick one Claude Code already has.
2. **Interview.** The builder reads the skill and asks what only you can answer, one question at
   a time, with the likely answers as buttons.
3. **Design.** It writes the interface, and you see it beside the conversation, on sample data.
4. **Adjust.** Say what to change until it's right, then press **Done**.
5. **Implement.** It writes what the running app needs (which memory to keep, and how) and checks
   its work. The app opens on its first session.

After that, an app is three tabs: **Sessions** (every conversation, in the app's own interface),
**Memory** (what it remembers, as files you can read and edit), and **Skill** (the skill, and
what the builder added). **Edit Interface** goes back to the builder, in the session the app was
built in, so it knows what's there and why.

## How it works

An app is a folder in `~/Library/Application Support/Yonka/Apps/`:

| File | What it is |
|---|---|
| `SKILL.md` | The skill, as it was added |
| `APP.md` | What the builder adds for the running agent: which memory to keep, and how |
| `app.json` | Name, symbol, and how far the build is |
| `interface.html` | What you see: one self-contained page |
| `demo.json` | Sample memory and messages, for the design's preview |
| `memory/` | What outlives every session |
| `sessions/` | Every conversation, one JSON file each |

Both agents are your own [Claude Code](https://claude.com/claude-code), run headless and
contained: no shell, no web, none of your settings. The builder works in the app's folder with
five skills (`interview`, `design`, `adjust`, `implement`, and `interface`, the contract a page is
written to). The app's own agent works in `memory/` and nowhere else, so using an app can never
change its skill or its interface. Each session is a Claude Code session, resumed message by
message; a new one is started with the skill, `APP.md`, and the memory as it stands.

The interface is a web page that is handed `window.yonka` (the messages, the memory, `send`) and
nothing else. It loads nothing from the network and can't navigate.

## Commands

```sh
make run      # open Yonka
make check    # build + test
make shots    # .build/shots/*.png, every screen on sample data
make app      # .build/app/Yonka.app
```

`$YONKA_HOME` moves everything Yonka keeps. The live test builds a real app with your Claude Code:
`YONKA_LIVE=/tmp/yonka YONKA_SKILL=path/to/SKILL.md swift test --filter Live`.
