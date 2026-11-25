import Foundation

/// The builder's skills: the four steps that turn a skill into an app, and the contract an
/// interface is written to. They're what the builder reads, so a change to `Interface`'s bridge
/// or its CSS changes `interface` here in the same change.
package enum BuilderSkills {
    package static let all: [(name: String, description: String, text: String)] = [
        ("explore", "Before step 1, for a Yokan app made from a repository of skills: read everything in source/ and work out the workflow its skills make together.", explore),
        ("interview", "Step 1 of building a Yokan app: read the skill, then ask the user what only they can answer.", interview),
        ("design", "Step 2 of building a Yokan app: work out what kind of tool the skill is, then draw three versions of its interface, on sample data, for the user to choose from.", design),
        ("adjust", "Step 3 of building a Yokan app, and how to change one later: take the version the user chose and change it with them until it's right.", adjust),
        ("implement", "Step 4 of building a Yokan app: write what the running app needs, check it, and finish.", implement),
        ("interface", "The contract a Yokan app's interface.html is written to: its files, the yokan API, the CSS it starts with, and how it should look. Load before writing or changing one.", interface),
    ]

    /// The skills as a Claude Code plugin named `yokan`, written whole each time, so a build
    /// always runs on the ones this version of Yokan has.
    package static func write(to plugin: URL) throws {
        try? FileManager.default.removeItem(at: plugin)
        let about = plugin.appending(path: ".claude-plugin")
        try FileManager.default.createDirectory(at: about, withIntermediateDirectories: true)
        let manifest = ["name": "yokan", "version": "1.0.0", "description": "How Yokan turns a skill into an app"]
        try JSONSerialization.data(withJSONObject: manifest).write(to: about.appending(path: "plugin.json"))
        for skill in all {
            let folder = plugin.appending(path: "skills/\(skill.name)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = "---\nname: \(skill.name)\ndescription: \(skill.description)\n---\n\n\(skill.text)\n"
            try Data(file.utf8).write(to: folder.appending(path: "SKILL.md"))
        }
    }

    static let explore = """
        # Explore

        The user gave you a whole repository, not one skill. It's in `source/`, exactly as it came, and it \
        stays that way: it's read-only, to you and to everyone. The app is one app for all of it. So before \
        anything is asked or drawn, you need to know what its skills are and how they're used together.

        ## Read everything

        - Glob `source/**` first, so you know all that's there before you open any of it.
        - Read in batches: many files in one step, never one at a time. The user is waiting.
        - What the author says: the README, any docs, AGENTS.md or CLAUDE.md. What it's for, who uses it, \
        and in what order.
        - Every SKILL.md, whole: its name, when it says to use it, and what it does. Don't stop at the first \
        few, and don't judge one by its description.
        - What each skill points to beside it: references, templates, examples. Read a script for what it \
        does, since that is part of what the skill does.
        - Whatever else gives direction: agents, commands, hooks, a plugin's manifest.

        In a big repository, read every SKILL.md whole and skim the rest.

        ## Work out the workflow

        1. **The job.** What someone uses all this for, start to finish, in a sentence.
        2. **The order.** Which skill starts, what each one produces, and which one takes that next. Look \
        for skills that name each other, files or folders one writes and another reads, numbered steps, and \
        roles that hand work on.
        3. **What each skill is in it.** A step of the one workflow, a tool used at any point, or something \
        that doesn't belong in this app. Leave those last out, and say so.
        4. **What passes between them.** A spec, a list of tasks, a draft, a verdict. That is what the app \
        keeps in memory, and it's what the interface shows: where the work is, and what each step made.
        5. **What a skill needs that an app can't do.** The app's agent can read the repository and write its \
        memory. It runs commands only if the user lets it: Yokan asks them the first time the agent needs one, so \
        APP.md never sends the user to a menu for it. Then it runs \
        in a sandbox: no network but PyPI, so it installs Python packages itself, into work/, and writing \
        only in memory and in work/, where what a command makes \
        belongs. Where a skill runs something, plan for the agent running it there, tell the user now that \
        they'll be asked, and find what has to be installed first that pip can't give: the agent asks for each such command, and Yokan runs it once the user approves it. Where a skill \
        needs the web, the agent does the thinking and tells the user what to fetch, or the step is left out.

        If the skills don't make a workflow, and it's a collection someone picks from, that is the answer: \
        the app is the place to pick one and use it, with one memory they all share.

        ## Say what you found

        In a few lines: what the repository is for, the workflow as one line with arrows (`plan → build → \
        review`), and what you're leaving out and why. Then load yokan:interview and carry on in the same \
        turn. From here on, where a step says "the skill" or "SKILL.md", read "the workflow" and "the \
        skills in source/".
        """

    static let interview = """
        # Interview

        You are at the start. Nothing is designed yet, and the user has said nothing but which skill they want.

        ## First, read

        Read SKILL.md, all of it (for an app made from a repository you already have: yokan:explore was the \
        reading), and work out three things before you ask anything:

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

        ## Sketch each answer

        A question about a screen is hard to answer in words. So before you ask one, draw what each answer \
        would look like: `sketches/1.html` for the first choice, `sketches/2.html` for the second, and so on, \
        in the order you list the choices. Yokan shows the sketch for whichever answer the user points at, \
        beside the question, marked as a rough idea. Write them all in one step, then ask.

        A sketch is a wireframe, not a design, and takes seconds:

        - Under 40 lines of HTML and inline CSS. No script, no `yokan`, no real content.
        - Blocks of `var(--surface)` on the page, each labelled with a word or two in `var(--mono)` at 11px: \
        "question", "answer box", "skill map". A line or two of real words only where it helps, like the \
        question itself in `var(--display)`.
        - The part the question is about outlined in `var(--accent)`, so the eye goes to what differs \
        between the sketches. Everything else is the same in all of them.
        - The whole window: `body { display: flex; height: 100%; padding: 28px; gap: 16px }`.

        Skip the sketches only for a question no picture would help with, like what a session is.

        ## Then, say what you'll build

        In three lines at most: what the screen is, what it remembers, what a session is. Then set "stage" to \
        "design" in app.json, load yokan:design, and carry on in the same turn. Don't wait to be told to.
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
        - **A pipeline** (several skills used in order, as an app made from a repository often is): the \
        steps laid out with the current one open, what each has made kept in reach, and the way on to the \
        next always in view.

        If the skill is none of these, say what it is in your own words. The conversation is always available, \
        since it's how the skill thinks, but it's the main surface only when talking really is the work.

        The kind of tool also sets the character: a study tool is calm and encouraging, a console is dense and \
        exact, a journal is warm, a review desk is neutral so the work stands out. yokan:interface says how \
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

        Three whole interfaces, each a real answer to "what should this be", not one design in three \
        colours. Drawn one after another they are the longest wait of the build, so draw them at once: \
        decide what each puts first, then start three helpers with the Agent tool, all in one step, one \
        for each version. A helper knows nothing of this conversation, so its brief is complete: to load \
        yokan:interface with the Skill tool and read demo.json before anything, what kind of tool this is \
        and its character, what the user does in it and what they asked for, the memory files and their \
        shapes, what the buttons send, this version's name and what it puts first, the one file it \
        writes, and to answer in one line. While they draw, write `designs/index.json` and app.json. \
        When they are back, check that each file is there and whole; draw any that is missing yourself. \
        With no tool for starting helpers, load yokan:interface and draw the three yourself.

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

        Yokan shows the three side by side as live thumbnails, with a "Use this one" button. Tell the user, \
        in three short lines, what kind of tool you took the skill to be, what each version is for, and which \
        you'd pick and why. Don't describe the code. Then stop and wait for their choice.
        """

    static let adjust = """
        # Adjust

        The user has chosen a version, or is back to change an app they've been using.

        ## When they choose

        "Use version B, Dashboard." means Yokan has already copied designs/B.html to interface.html. Read \
        interface.html, set "stage" to "adjust" in app.json, and say in one line that it's theirs to change \
        now. If they ask for a mix ("B, but with A's map"), make it in interface.html: the versions in \
        designs/ are there to read from.

        If none of the three is right, ask what's missing in one question, go back to yokan:design, and \
        draw three new ones over the old.

        ## When they ask for a change

        - Make the change they asked for and nothing else. Edit, don't rewrite: what they didn't mention, they \
        liked.
        - If a change needs something the interface doesn't have (a new thing remembered, a new shape), add it \
        to demo.json too, so they see it, and to APP.md if there is one, so the running app keeps it.
        - Load yokan:interface before a change bigger than a tweak. If what they ask for breaks it (a font from \
        the web, a link out), say what you can do instead, in a sentence.
        - Answer in one line: what changed. They can see the rest.

        ## When they come back to an app in use

        Read interface.html, APP.md and demo.json first, so you know what is there. The app has real memory \
        in the old shape, and the interface has to draw it as it is: treat anything new as possibly missing. \
        If they want to see other directions rather than a change, set "stage" to "design", load yokan:design \
        and draw three new versions from what the app is today.

        ## When it's right

        When they say it's right, or ask you to finish: set "stage" to "implement" in app.json, load \
        yokan:implement, and carry on in the same turn.
        """

    static let implement = """
        # Implement

        The design is settled. Now make it work for real, with the user's own sessions and memory.

        ## Write APP.md

        The agent that runs this app is given SKILL.md, then APP.md, then its memory. It has never seen this \
        build, and it can't see the interface. APP.md tells it what the skill can't:

        - **The workflow**, for an app made from a repository. That agent is given only the list of skills \
        in source/, and reads one when it needs it, so APP.md comes first with what yokan:explore found: the \
        job, the steps in order with the skill each one uses (by its path in source/), what each step makes \
        and where in memory it goes, how to tell which step the work is at, what it runs in work/ and what \
        the user must have installed for that, and what the app does in place of anything it can't do.
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
        - It follows yokan:interface: one file, nothing from the network.

        ## Finish

        Set "stage" to "done" in app.json. Yokan then opens the app on its first session. Tell the user, in one \
        line, that it's ready and what to say first.
        """

    static let interface = """
        # Interface

        An app is a folder, and you work in it:

        | File | What it is | Who writes it |
        |---|---|---|
        | `SKILL.md` | The skill, in an app made from one | Nobody: leave it as it is |
        | `source/` | The repository of skills, in an app made from several | Nobody: it's read-only |
        | `app.json` | `name`, `symbol` (an SF Symbol's name), `stage` | You |
        | `interface.html` | What the user sees | You |
        | `demo.json` | Sample data for the preview: `{"memory": {"file": …}, "messages": [{"role": "user", "text": "…"}]}` | You |
        | `designs/` | The versions to choose from: `A.html`, `B.html`, `C.html`, and `index.json` naming them | You, in the design step |
        | `APP.md` | What the running agent needs beyond the skill | You, in the last step |
        | `memory/` | What the app remembers | Only the running agent. Never you |
        | `work/` | Where the running agent's commands run, and what they make, if the user lets it run any | Only the running agent. Never you |

        ## interface.html

        A version in designs/ is written to exactly the same rules: it becomes interface.html when chosen.

        One file. Its CSS and JavaScript are inline, and it loads nothing: no CDN, no web font, no remote image, \
        no `fetch`, no link that opens. Yokan blocks all of those, so a page that needs one is a broken page. \
        Draw icons as inline SVG or leave them out.

        Before your page runs, Yokan gives it `window.yokan` and a little CSS.

        ### yokan

        | | |
        |---|---|
        | `yokan.messages` | `[{role: "user" or "assistant", text}]`, this session, oldest first. The last one grows while the agent is answering |
        | `yokan.memory` | `{"skill-map.json": "<the file's text>", …}`: every file in memory |
        | `yokan.json(name)` | That file parsed, or `null` if it's missing or isn't JSON |
        | `yokan.busy` | `true` while the agent is working |
        | `yokan.status` | What it's doing when it isn't talking, like "Writing skill-map.json". Often empty |
        | `yokan.app.name`, `yokan.session.title` | For a heading, if you want one |
        | `yokan.preview` | `true` in the design's preview, where the data is demo.json's |
        | `yokan.send(text)` | Say something as the user. Ignored while busy |
        | `yokan.onChange(fn)` | Calls `fn` now, and again whenever any of the above changes |
        | `yokan.html(markdown)` | A message's Markdown as safe HTML |
        | `yokan.escape(text)` | Text made safe to put in HTML |

        Draw everything from that state inside one `yokan.onChange`, so the page is always what the state says: \
        it will be called many times a second while an answer streams. Keep what the user is typing out of what \
        you redraw. The agent's text goes through `yokan.html`, anything else through `yokan.escape`, never raw \
        into `innerHTML`.

        Put your script inside a block, `<script>{ … }</script>`. The page runs in WebKit, which refuses a \
        top-level `const` or `let` named like something `window` already has (`status`, `name`, `top`, \
        `history`), and one refused name stops the whole script. If the script throws, Yokan tells the user \
        "The interface has an error", and they'll tell you: fix it before anything else.

        Whatever is structured (progress, levels, a list, a plan) comes from a memory file through \
        `yokan.json`, never from picking apart a message's text. A button that does something does it by \
        sending what the user would have typed: `yokan.send("show me a harder one")`.

        ### The CSS it starts with

        Yokan is dark, and an app is part of it: the page sits in Yokan's window, inside Yokan's own dark \
        chrome, so it starts from Yokan's look and is always dark. There is no light mode to design for.

        You get the system sans at 15px, `box-sizing: border-box`, a body with no margin filling the window, \
        headings already in the serif, and these:

        - `--text` `--secondary` `--tertiary`: text, strongest first.
        - `--bg` (the page, near black) · `--surface` (a quiet raised fill) · `--line` (a hairline).
        - `--accent` (Yokan's vermilion) · `--on-accent` (text on a fill of it).
        - `--display`: the serif. For what's said large: a question, a title, a big number.
        - `--mono`: the monospace. For small labels, counts, dates, anything that's data.
        - `--radius`.

        Use them rather than colours and fonts of your own. A page that brings a white background or a \
        different typeface looks pasted into the window.

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
          - *Type.* Yokan's three voices, and how much of each. `--display` leads where the app is for \
        reading, thinking and writing; the sans leads where it's for doing; `--mono` leads where it's for \
        code, data and consoles. Every app uses all three a little: a serif line for the thing that \
        matters, sans for the body, mono for the small labels.
          - *Density.* A console is tight (13px, 8px rhythm). A study tool or a journal is open (16–17px, \
        24px rhythm).
          - *Accent.* `--accent` is for the one thing to press and the one thing that's current. An app \
        may redefine it to a colour that suits its subject, as long as it's as bright on the dark page.
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
        - **Dark, like the window around it.** Depth comes from `--bg`, then `--surface`, then a \
        hairline, never from a shadow or a white card. Any colour you add has to read on near black.
        - **Words are short and plain.** "Answer", not "Type your answer here…". No header repeating the \
        app's name, no labels on what is obvious.

        ### What gives a page away as generated

        None of these: gradients and glows, emoji as icons, a purple accent for no reason, everything \
        centred, a row of identical cards with an icon on each, a coloured left border on a card, shadows \
        for decoration, a "Welcome to…" banner, three sizes of rounded corner. Icons are inline SVG with \
        one stroke weight, or left out.

        The starter interface.html already in the folder is a plain conversation done to these rules. Read it \
        for how `yokan` is used, then design for the skill in front of you: don't hand back the starter.
        """
}
