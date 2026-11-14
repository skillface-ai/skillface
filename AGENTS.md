# Yonka

A macOS app that turns a skill into an app: its own interface, a memory that lasts, and sessions
to come back to. README.md has the product and the flow. Its architecture follows Yongkang's.

`CLAUDE.md` is a symlink to this file. Edit `AGENTS.md`.

## Layout

- `Sources/YonkaCore/`: no SwiftUI, so all of it runs under `swift test`.
  - `Skill.swift`: a SKILL.md, read and checked. `YonkaError`.
  - `SkillApp.swift`: an app's folder, `Info` (`app.json`), `Stage`, `Session`, `TextFile`, `Choices`.
  - `YonkaHome.swift`: where everything lives. Every read and write of an app's folder.
  - `Agent.swift`: `AgentTurn`, Claude Code's flags and what it's told (`Agent`), its stream
    (`AgentStream`, `AgentEvent`, `Reply`), and running it (`AgentProcess`).
  - `BuilderSkills.swift`: the builder's five skills, written out as a Claude Code plugin.
  - `Interface.swift`: what an `interface.html` is given: `bridge` (`window.yonka`), `css`,
    `policy`, the starter page, and the `State` it's handed.
- `Sources/YonkaUI/`: `AppModel` (every workflow; failures become `notice`) and the screens.
  `InterfaceView` is the one web view.
- `Sources/Yonka/main.swift`: the app.
- `Sources/Shots/`: dev-only, draws every screen offscreen on sample data.
- `Tests/YonkaCoreTests/`: on a throwaway home and a stand-in for Claude Code. `LiveTests` is the
  whole flow on the real one, only when asked for.

## Commands

```sh
make check    # build + test: the definition of done
make shots    # .build/shots/*.png
make run      # open the app
```

## Rules

- **The interface API is a contract.** A change to `Interface.bridge`, `Interface.css` or
  `Interface.State` updates `BuilderSkills.interface` (what the builder reads), the starter page
  and the tests in the same change.
- **The disk is the truth.** `AppModel` writes through `YonkaHome` and reads back with `refresh`,
  which is also how it sees what an agent wrote. Don't keep a second copy of an app's state.
- **An app's agent writes only `memory/`**, and the builder never writes there. A page loads
  nothing and goes nowhere (`Interface.policy`, `InterfaceView`'s delegate). Don't give the web
  view a base URL or a store that lasts.
- **Everything from a skill or an agent is untrusted:** a skill's name becomes a folder only
  through `Skill.slug`, a memory's name a path only through `YonkaHome.memoryFile`, a session's
  id only as a UUID, and `app.json` decodes whatever is in it.
- **Values don't change.** Core's types are immutable: a change is a new value (`Session.adding`,
  `Info.at`, `Reply.applying`).
- **A UI change gets shots before and after.** They can't see the sidebar's glass or the toolbar:
  check those by running the app.
- Comments explain why. `ponytail:` marks a deliberate ceiling and what to do when it's hit.
