# Skillface

A macOS app that turns a skill into an app: its own interface, a memory that lasts, and sessions
to come back to. README.md has the product and the flow.

`CLAUDE.md` is a symlink to this file. Edit `AGENTS.md`.

## Layout

- `Sources/SkillfaceCore/`: no SwiftUI, so all of it runs under `swift test`.
  - `Skill.swift`: a SKILL.md, read and checked. `SkillfaceError`.
  - `Command.swift`: a command an agent asks the user to approve, and running it.
  - `Repo.swift`: a link to a GitHub repository of skills, fetched and unpacked.
  - `SkillApp.swift`: an app's folder, `Info` (`app.json`), `Stage`, `Design`, `Session`, `TextFile`,
    `SourceSkill`, `Choices`.
  - `SkillfaceHome.swift`: where everything lives. Every read and write of an app's folder.
  - `Agent.swift`: `AgentTurn`, Claude Code's flags and what it's told (`Agent`), its stream
    (`AgentStream`, `AgentEvent`, `Reply`), and running it (`AgentProcess`).
  - `Codex.swift`: the provider choice, conversation handoff, and restricted Codex CLI invocation.
  - `Toolless.swift`: Antigravity and Grok, run with every tool denied (`ToollessInvocation`).
  - `BuilderSkills.swift`: the builder's six skills, written out as a Claude Code plugin.
  - `Interface.swift`: what an `interface.html` is given: `bridge` (`window.skillface`), `css`,
    `policy`, the starter page, and the `State` it's handed.
- `Sources/SkillfaceUI/`: `AppModel` (every workflow; failures become `notice`) and the screens:
  `HomeView` (the drop target, the dock, All Apps), `AppScreen` (an open app: the lifeline, what
  it knows), `BuilderView` (the conversation, the versions). `Theme` is Skillface's own look, always
  dark; `InterfaceView` is the one web view, and an app's page follows the Mac's appearance.
- `Sources/Skillface/main.swift`: the app.
- `Sources/Shots/`: dev-only, draws every screen offscreen on sample data.
- `Tests/SkillfaceCoreTests/`: on a throwaway home and a stand-in for Claude Code. `LiveTests` is the
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
- **The disk is the truth.** `AppModel` writes through `SkillfaceHome` and reads back with `refresh`,
  which is also how it sees what an agent wrote. Don't keep a second copy of an app's state.
- **An app's agent writes only `memory/`** (and `work/`, once it runs commands), and the builder
  writes in neither. Nobody writes
  `source/`, a repository as it came: its agent may read there (`--add-dir`), and what keeps it
  from writing is that `SkillfaceHome.create(from:named:)` leaves every file and folder read-only.
- **An app runs commands only when its user said so, and only in the sandbox.** The say-so is in
  `terminal.json` beside the apps (`SkillfaceHome.runs`), never in an app's folder, which an agent
  writes. Then its own agent, never the builder, gets Bash under `Agent.sandbox(for:)`: no network but PyPI (`Agent.registries`),
  no way out of the sandbox, writing only `memory/` and `work/`. Codex uses a named permission profile
  for these same folders and registries. Without terminal permission it returns structured file changes
  for Skillface to validate, with the shell disabled. Antigravity and Grok have no sandbox that holds to
  those (`AgentProvider.sandboxes`), so they only ever return file changes, with every tool denied. Don't allow Bash any other way
  (`--allowedTools`, a permission mode): without the sandbox it must stay denied. What the sandbox
  can't do (Homebrew, an installer) the agent asks for (`Command`), and Skillface runs it itself,
  unsandboxed, only after the user read that exact command and said yes, each time.
- **A build runs nothing, so a new app rehearses.** The builder leaves a `## Rehearsal` in APP.md
  for a skill that runs things (`Agent.rehearses`), and `AppModel` then asks for the terminal and
  sends `Agent.rehearse` to the app's own agent, which keeps what it learns in `memory/setup.md`.
  Don't give the builder a shell to check its own work.
- A page loads
  nothing and goes nowhere (`Interface.policy`, `InterfaceView`'s delegate). Don't give the web
  view a base URL or a store that lasts.
- **Everything from a skill or an agent is untrusted:** a skill's name becomes a folder only
  through `Skill.slug`, a repository only its plain files (nothing hidden, no links), a memory's name a path only through `SkillfaceHome.memoryFile`, a session's
  id only as a UUID, and `app.json` decodes whatever is in it.
- **Values don't change.** Core's types are immutable: a change is a new value (`Session.adding`,
  `Info.at`, `Reply.applying`).
- **A UI change gets shots before and after.** They can't see the window's own buttons, which sit
  over the content (`Theme.lights`): check those by running the app.
- Comments explain why. `ponytail:` marks a deliberate ceiling and what to do when it's hit.
