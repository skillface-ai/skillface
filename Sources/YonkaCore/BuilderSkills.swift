import Foundation

/// The builder's skills: the four steps that turn a skill into an app, and the contract an
/// interface is written to. They're what the builder reads, so a change to `Interface`'s bridge
/// or its CSS changes `interface` here in the same change.
package enum BuilderSkills {
    package static let all: [(name: String, description: String, text: String)] = [
        ("interview", "Step 1 of building a Yonka app: read the skill, then ask the user what only they can answer.", interview),
        ("design", "Step 2 of building a Yonka app: work out what kind of tool the skill is, then draw three versions of its interface, on sample data, for the user to choose from.", design),
        ("adjust", "Step 3 of building a Yonka app, and how to change one later: take the version the user chose and change it with them until it's right.", adjust),
        ("implement", "Step 4 of building a Yonka app: write what the running app needs, check it, and finish.", implement),
        ("interface", "The contract a Yonka app's interface.html is written to: its files, the yonka API, the CSS it starts with, and how it should look. Load before writing or changing one.", interface),
    ]

    /// The skills as a Claude Code plugin named `yonka`, written whole each time, so a build
    /// always runs on the ones this version of Yonka has.
    package static func write(to plugin: URL) throws {
        try? FileManager.default.removeItem(at: plugin)
        let about = plugin.appending(path: ".claude-plugin")
        try FileManager.default.createDirectory(at: about, withIntermediateDirectories: true)
        let manifest = ["name": "yonka", "version": "1.0.0", "description": "How Yonka turns a skill into an app"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: about.appending(path: "plugin.json"))
        for skill in all {
            let folder = plugin.appending(path: "skills/\(skill.name)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = "---\nname: \(skill.name)\ndescription: \(skill.description)\n---\n\n\(skill.text)\n"
            try Data(file.utf8).write(to: folder.appending(path: "SKILL.md"))
        }
    }

    static let interview = """
        # Interview

        You are at the start. Nothing is designed yet, and the user has said nothing but which skill they want.

        ## First, read

        Read SKILL.md, all of it, and work out three things before you ask anything:

        1. **What the user does in it, over and over.** Answering a question, reviewing a draft, logging \
        something. That is what the interface is for, and it gets the most room.
        2. **What has to outlive a session.** This is the reason the app exists. Look for what the skill prints so \
        the user can keep track (a progress map, a list, a plan), what it asks the user to save or paste back, and \
        what it would otherwise work out again from nothing each time (their level, their preferences, what was \
        covered). Each of those becomes memory.
        3. **What a session is.** One topic, one day, one document? That decides what a new session opens with and \
        what the list of sessions will read like.

        ## Then, ask

        Ask only what the skill doesn't settle and what changes the design. Three questions is usual, five is the \
        most. One at a time, each with two to four likely answers as a checklist, the one you'd pick first. Wait \
        for each answer before the next.

        Good questions are about the user, not about software:

        - What they want in view the whole time, and what only when they ask.
        - What a new session should open with: where they left off, or a clean start.
        - Which of the things the skill tracks they care to see, when it tracks several.

        Don't ask what has an obvious answer, don't ask about colours or fonts, and never ask a question whose \
        answer you would ignore. If the skill settles everything, ask one question, the one about what stays in view.

        ## Then, say what you'll build

        In three lines at most: what the screen is, what it remembers, what a session is. Then set "stage" to \
        "design" in app.json, load yonka:design, and carry on in the same turn. Don't wait to be told to.
        """

    static let design = """
        # Design

        You know the skill and what the user wants. Now they need something to look at, and a choice.

        ## First, decide what kind of tool this is

        A skill's app is not a chat window with decoration. Ask what a professional would build for someone \
        who does this work every day, and name it in a phrase before you draw anything. Some that come up:

        - **A study tool** (tutoring, drilling, language practice): one question at a time, large, with \
        progress always in view. Think flashcards and a course map.
        - **A review desk** (code review, editing, critique): the thing under review fills the screen, findings \
        sit beside it as a list you work through, each with a state.
        - **A planner** (weekly plans, roadmaps, trip planning): a board or a calendar is the surface, and \
        the conversation is a side panel that changes it.
        - **A log or tracker** (habits, a journal, a training diary): today's entry first, then history as a \
        timeline or a chart.
        - **A workbench** (writing, research, analysis): a document that grows, with the conversation as \
        margin notes.
        - **A console** (ops, debugging, triage): dense, a queue on the left, the current item in the middle, \
        status everywhere.

        If the skill is none of these, say what it is in your own words. The conversation is always available, \
        since it's how the skill thinks, but it's the main surface only when talking really is the work.

        The kind of tool also sets the character: a study tool is calm and encouraging, a console is dense and \
        exact, a journal is warm, a review desk is neutral so the work stands out. yonka:interface says how \
        character becomes type, colour and spacing.

        ## Then, decide what it remembers

        Decide the memory every version draws from: which files, and the exact shape of each. Anything \
        structured that the user sees (progress, a list, a plan) comes from a memory file, never from reading \
        the conversation's text. The fewest files that work, with names a person would understand in the \
        Memory tab: `skill-map.json`, `notes.md`. All three versions read the same memory, so the choice \
        between them is about the interface alone.

        Write demo.json: memory in those shapes and a few messages, as a real session a little way in would \
        have them. Every preview is drawn from it, so make it true to life, not lorem ipsum.

        ## Then, draw three versions

        Load yonka:interface. Then write three whole interfaces, each a real answer to "what should this \
        be", not one design in three colours:

        - `designs/A.html`, `designs/B.html`, `designs/C.html`, each complete and self-contained.
        - `designs/index.json`: `[{"id": "A", "name": "Focus", "idea": "One question fills the screen, the \
        map stays quiet beside it."}, …]`. A name of one or two words, and an idea of one line saying what \
        this version is for, in the user's terms.

        Make them differ in what they put first. For example: one that gives the whole screen to the single \
        thing the user does, one that leads with the overview and progress, and one that reads as a document \
        or a timeline. If two of them could swap headings without anyone noticing, one of them is wasted: \
        redraw it. Put the one you would pick as A.

        Each must look right on demo.json and with no memory and no messages at all, which is what a new \
        user sees first.

        Give the app its name and an SF Symbol that suits it, in app.json ("name", "symbol"). A short name, \
        as it would sit under an icon. Leave "stage" at "design": the user is choosing.

        Never write into memory/. It is the user's real memory, and it starts empty.

        ## Then, hand over the choice

        Yonka shows the three side by side as live thumbnails, with a "Use this one" button. Tell the user, \
        in three short lines, what kind of tool you took the skill to be, what each version is for, and which \
        you'd pick and why. Don't describe the code. Then stop and wait for their choice.
        """

    static let adjust = """
        # Adjust

        The user has chosen a version, or is back to change an app they've been using.

        ## When they choose

        "Use version B, Dashboard." means Yonka has already copied designs/B.html to interface.html. Read \
        interface.html, set "stage" to "adjust" in app.json, and say in one line that it's theirs to change \
        now. If they ask for a mix ("B, but with A's map"), make it in interface.html: the versions in \
        designs/ are there to read from.

        If none of the three is right, ask what's missing in one question, go back to yonka:design, and \
        draw three new ones over the old.

        ## When they ask for a change

        - Make the change they asked for and nothing else. Edit, don't rewrite: what they didn't mention, they \
        liked.
        - If a change needs something the interface doesn't have (a new thing remembered, a new shape), add it \
        to demo.json too, so they see it, and to APP.md if there is one, so the running app keeps it.
        - Load yonka:interface before a change bigger than a tweak. If what they ask for breaks it (a font from \
        the web, a link out), say what you can do instead, in a sentence.
        - Answer in one line: what changed. They can see the rest.

        ## When they come back to an app in use

        Read interface.html, APP.md and demo.json first, so you know what is there. The app has real memory \
        in the old shape, and the interface has to draw it as it is: treat anything new as possibly missing. \
        If they want to see other directions rather than a change, set "stage" to "design", load yonka:design \
        and draw three new versions from what the app is today.

        ## When it's right

        When they say it's right, or ask you to finish: set "stage" to "implement" in app.json, load \
        yonka:implement, and carry on in the same turn.
        """

    static let implement = """
        # Implement

        The design is settled. Now make it work for real, with the user's own sessions and memory.

        ## Write APP.md

        The agent that runs this app is given SKILL.md, then APP.md, then its memory. It has never seen this \
        build, and it can't see the interface. APP.md tells it what the skill can't:

        - **Memory.** Each file the interface reads: its name, its exact shape with a short example, and when to \
        write it. Be exact, since the interface parses it. Say that it's written the moment it changes, not at \
        the end.
        - **What the interface already shows.** So it doesn't say it again: if the interface draws the progress \
        map, the agent must not print one in the conversation.
        - **How a session starts.** From memory: where the user stands and what comes next, in a line, and \
        then on with it. With no memory, how the first session begins.
        - **What the app makes unnecessary.** Where the skill tells the user to save state, paste it back, or ask \
        to see progress, say what happens here instead.

        Write it to the agent, plainly, as short as covers those. Don't repeat the skill.

        ## Check

        Read interface.html once more against each of these, and fix what fails:

        - With no memory and no messages it shows a way to begin, not a blank page or an error.
        - A memory file that's missing, empty, or lacks a field doesn't break it.
        - A long message, a long list and a narrow window all still read well.
        - While the agent is working, the user can see that it is, and can't send twice.
        - Every shape in demo.json is the shape APP.md asks for.
        - It follows yonka:interface: one file, nothing from the network.

        ## Finish

        Set "stage" to "done" in app.json. Yonka then opens the app on its first session. Tell the user, in one \
        line, that it's ready and what to say first.
        """

    static let interface = """
        # Interface

        An app is a folder, and you work in it:

        | File | What it is | Who writes it |
        |---|---|---|
        | `SKILL.md` | The skill | Nobody: leave it as it is |
        | `app.json` | `name`, `symbol` (an SF Symbol's name), `stage` | You |
        | `interface.html` | What the user sees | You |
        | `demo.json` | Sample data for the preview: `{"memory": {"file": …}, "messages": [{"role": "user", "text": "…"}]}` | You |
        | `designs/` | The versions to choose from: `A.html`, `B.html`, `C.html`, and `index.json` naming them | You, in the design step |
        | `APP.md` | What the running agent needs beyond the skill | You, in the last step |
        | `memory/` | What the app remembers | Only the running agent. Never you |

        ## interface.html

        A version in designs/ is written to exactly the same rules: it becomes interface.html when chosen.

        One file. Its CSS and JavaScript are inline, and it loads nothing: no CDN, no web font, no remote image, \
        no `fetch`, no link that opens. Yonka blocks all of those, so a page that needs one is a broken page. \
        Draw icons as inline SVG or leave them out.

        Before your page runs, Yonka gives it `window.yonka` and a little CSS.

        ### yonka

        | | |
        |---|---|
        | `yonka.messages` | `[{role: "user" or "assistant", text}]`, this session, oldest first. The last one grows while the agent is answering |
        | `yonka.memory` | `{"skill-map.json": "<the file's text>", …}`: every file in memory |
        | `yonka.json(name)` | That file parsed, or `null` if it's missing or isn't JSON |
        | `yonka.busy` | `true` while the agent is working |
        | `yonka.status` | What it's doing when it isn't talking, like "Writing skill-map.json". Often empty |
        | `yonka.app.name`, `yonka.session.title` | For a heading, if you want one |
        | `yonka.preview` | `true` in the design's preview, where the data is demo.json's |
        | `yonka.send(text)` | Say something as the user. Ignored while busy |
        | `yonka.onChange(fn)` | Calls `fn` now, and again whenever any of the above changes |
        | `yonka.html(markdown)` | A message's Markdown as safe HTML |
        | `yonka.escape(text)` | Text made safe to put in HTML |

        Draw everything from that state inside one `yonka.onChange`, so the page is always what the state says: \
        it will be called many times a second while an answer streams. Keep what the user is typing out of what \
        you redraw. The agent's text goes through `yonka.html`, anything else through `yonka.escape`, never raw \
        into `innerHTML`.

        Put your script inside a block, `<script>{ … }</script>`. The page runs in WebKit, which refuses a \
        top-level `const` or `let` named like something `window` already has (`status`, `name`, `top`, \
        `history`), and one refused name stops the whole script. If the script throws, Yonka tells the user \
        "The interface has an error", and they'll tell you: fix it before anything else.

        Whatever is structured (progress, levels, a list, a plan) comes from a memory file through \
        `yonka.json`, never from picking apart a message's text. A button that does something does it by \
        sending what the user would have typed: `yonka.send("show me a harder one")`.

        ### The CSS it starts with

        The system font at 15px, `box-sizing: border-box`, a body with no margin filling the window, and these, \
        which follow light and dark on their own:

        `--text` `--secondary` `--tertiary` (text, strongest first) · `--bg` (the page) · `--surface` (a quiet \
        fill) · `--line` (a hairline) · `--accent` · `--radius`

        Use them rather than colours of your own, so every app belongs on the same Mac.

        ## How it should look

        Like a product a good team shipped for exactly this job. Not a chat window, not a template.

        ### Fit the purpose

        - **Start from the work, not from the conversation.** Decide what object the user is really working \
        on (a question, a document, a board, a queue, a day) and make that the screen. The conversation is \
        how the skill thinks: give it the main column only when talking is the work, and otherwise a side \
        panel, a thread under the object, or the answer box alone.
        - **Use real controls.** What is structured gets a structured control: levels are bars, a list of \
        findings is a list with states, a plan is a board, a choice between a few things is buttons, a date \
        is a date. Each one acts by sending what the user would have typed.
        - **Give it the character of its job.** Set the character with the few things that carry it:
          - *Type.* System sans for tools. `"New York", Georgia, serif` for reading and writing. \
        `ui-monospace` for code, data and consoles. `ui-rounded` for something friendly. One family for \
        text, at most one more for display or numbers.
          - *Density.* A console is tight (13px, 8px rhythm). A study tool or a journal is open (16–17px, \
        24px rhythm).
          - *Accent.* One colour that suits the subject, set by redefining `--accent` (in both light and \
        dark). Keep every other colour to the variables.
          - *Shape.* `--radius` small and square for exact tools, larger for soft ones.

        ### Craft

        - **One thing matters most on the screen.** Give it the room and the weight. Everything else is \
        quieter and smaller, or isn't there.
        - **A type scale, not a pile of sizes.** Three or four sizes with clear jobs (a title, body, a \
        label, a big number) and two weights. Labels in `--secondary`. Numbers that change line up with \
        `font-variant-numeric: tabular-nums`.
        - **A spacing scale.** Multiples of 4 or 8, the same gap for the same relationship everywhere. Align \
        every edge to another edge. A reading column no wider than 680px.
        - **Hierarchy from space and type** before borders. A hairline (`--line`) to separate, a quiet fill \
        (`--surface`) to group, never both, and never a card inside a card.
        - **Every state is designed.** Empty (say what this is and offer the way in), working (something \
        small says the agent is at it, and nothing can be sent twice), long (a long list, a long answer, a \
        narrow window), and wrong (a missing file or field draws as empty, not as an error).
        - **It feels alive.** Enter sends and Shift-Enter makes a line. The box has focus when the page \
        opens. What's new scrolls into view. Changes ease over about 200ms. Bars and numbers move when \
        memory changes.
        - **Both appearances.** Check it in light and dark: the variables follow on their own, and any \
        colour you add needs both.
        - **Words are short and plain.** "Answer", not "Type your answer here…". No header repeating the \
        app's name, no labels on what is obvious.

        ### What gives a page away as generated

        None of these: gradients and glows, emoji as icons, a purple accent for no reason, everything \
        centred, a row of identical cards with an icon on each, a coloured left border on a card, shadows \
        for decoration, a "Welcome to…" banner, three sizes of rounded corner. Icons are inline SVG with \
        one stroke weight, or left out.

        The starter interface.html already in the folder is a plain conversation done to these rules. Read it \
        for how `yonka` is used, then design for the skill in front of you: don't hand back the starter.
        """
}
