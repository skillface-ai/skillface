import Foundation

/// The builder's skills: the four steps that turn a skill into an app, and the contract an
/// interface is written to. They're what the builder reads, so a change to `Interface`'s bridge
/// or its CSS changes `interface` here in the same change.
package enum BuilderSkills {
    package static let all: [(name: String, description: String, text: String)] = [
        ("interview", "Step 1 of building a Yonka app: read the skill, then ask the user what only they can answer.", interview),
        ("design", "Step 2 of building a Yonka app: write its interface, on sample data, for the user to look at.", design),
        ("adjust", "Step 3 of building a Yonka app, and how to change one later: change the interface with the user until it's right.", adjust),
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

        You know the skill and what the user wants. Now they need something to look at.

        1. Load yonka:interface. It is the contract, and the taste.
        2. Decide the memory the interface draws from: which files, and the exact shape of each. Anything \
        structured that the user sees (progress, a list, a plan) comes from a memory file, never from reading \
        the conversation's text. Keep it to the fewest files that work, with names a person would understand in \
        the Memory tab: `skill-map.json`, `notes.md`.
        3. Write demo.json: memory in those shapes and a few messages, as a real session a little way in would \
        have them. The preview is drawn from it, so make it true to life, not lorem ipsum.
        4. Write interface.html, whole. It must look right on demo.json and with no memory and no messages at \
        all, which is what a new user sees first.
        5. Give the app its name and an SF Symbol that suits it, in app.json ("name", "symbol"). A short name, \
        as it would sit under an icon.
        6. Set "stage" to "adjust" in app.json.

        Never write into memory/. It is the user's real memory, and it starts empty.

        Then tell the user, in two sentences, what they are looking at and what it will remember, and ask what \
        they'd change. Don't describe the code.
        """

    static let adjust = """
        # Adjust

        The user is looking at the interface and telling you what to change. This is also where they land when \
        they come back to an app they've been using and want it different: then read interface.html, APP.md and \
        demo.json first, so you know what is there.

        - Make the change they asked for and nothing else. Edit, don't rewrite: what they didn't mention, they \
        liked.
        - If a change needs something the interface doesn't have (a new thing remembered, a new shape), add it \
        to demo.json too, so they see it, and to APP.md if there is one, so the running app keeps it.
        - An app in use has real memory in the old shape. The interface has to draw it as it is: treat anything \
        new as possibly missing.
        - Load yonka:interface before a change bigger than a tweak. If what they ask for breaks it (a font from \
        the web, a link out), say what you can do instead, in a sentence.
        - Answer in one line: what changed. They can see the rest.

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
        | `APP.md` | What the running agent needs beyond the skill | You, in the last step |
        | `memory/` | What the app remembers | Only the running agent. Never you |

        ## interface.html

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

        Like something Apple would ship: calm, obvious, nothing extra.

        - **One thing matters most on the screen.** Find it and give it the room. Everything else is quieter \
        and smaller, or isn't there.
        - **Content, not chrome.** No header bar repeating the app's name, no boxes around boxes, no labels on \
        what is obvious. If taking something away loses nothing, take it away.
        - **Type does the work.** Hierarchy from size and weight and `--secondary`, not from colour or borders. \
        Two sizes and two weights are usually enough. A reading column no wider than 680px.
        - **Space is the layout.** Generous, even margins. Align everything to something.
        - **One accent**, for the one thing to press or the one thing that's current. No gradients, no shadows \
        for decoration, no emoji as icons.
        - **It feels alive.** Enter sends and Shift-Enter makes a line. The box has focus when the page opens. \
        New messages scroll into view. While the agent works, something small says so. Changes ease in over \
        about 200ms rather than jumping.
        - **Empty is a first impression.** With no messages and no memory, say in a line what this is and offer \
        the way in: a box, or a few things to start with.
        - **Words are short and plain.** "Message", not "Type your message here…".

        The starter interface.html already in the folder is a plain conversation done this way. Build from it.
        """
}
