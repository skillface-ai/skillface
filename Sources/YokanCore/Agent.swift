import Foundation

/// One message to an app's agent, or to the builder: everything Claude Code is started with.
package struct AgentTurn: Sendable {
    package let app: SkillApp
    package let session: Session
    package let message: String
    /// The app's memory as the session starts, which is what keeps it from starting empty.
    package let memory: [TextFile]
    package let skill: String
    /// The skills in `source/`, for an app made from a repository of them. Then `skill` is empty.
    package let skills: [SourceSkill]
    /// Whether the user let this app run commands. Only its own agent ever does: never the builder.
    package let terminal: Bool
    package let rules: String
    /// The builder's skills, as a Claude Code plugin.
    package let plugin: URL

    package init(
        app: SkillApp, session: Session, message: String, memory: [TextFile], skill: String, skills: [SourceSkill] = [],
        terminal: Bool = false, rules: String, plugin: URL
    ) {
        (self.app, self.session, self.message, self.memory) = (app, session, message, memory)
        (self.skill, self.skills, self.terminal, self.rules, self.plugin) = (skill, skills, terminal, rules, plugin)
    }

    /// Where it works, which is all it can write: the builder in the app's folder, the app's own
    /// agent in its memory, so using an app can never change its skill or its interface.
    package var folder: URL { session.kind == .build ? app.folder : app.memory }

    /// Whether this turn gets a shell: an app in use, whose user said so.
    package var runs: Bool { terminal && session.kind == .use }
}

/// What Claude Code is asked and told. The user's own Claude Code, contained as Yongkang
/// contains a miniapp's: `--restricted` leaves it no shell, no web and none of the user's
/// settings, acceptEdits lets it write in its folder, and with nobody to prompt, anything else
/// is denied. An app the user let run commands gets Bash back, inside Claude Code's sandbox
/// (`sandbox(for:)`), which is the only reason it runs unasked: without those settings Bash
/// would have to prompt, and is denied.
package enum Agent {
    /// What the app sends for the user when a skill is added.
    package static let begin = "Turn this skill into an app with me."
    /// And when a repository of them is.
    package static let beginAll = "Turn these skills into one app with me."
    /// When they pick one of the versions drawn for them.
    package static func chose(_ design: Design) -> String { "Use version \(design.id), \(design.name)." }
    /// And when they say the design is right.
    package static let finish = "That's right. Finish the app."
    /// What an app's agent ends a message with when it needs to run a command and may not, so
    /// Yokan asks the user for it. Only ever a request: the answer is the user's, in a dialog.
    package static let asks = "[[terminal]]"
    /// And what it's sent for the user once they've said yes.
    package static let allowed = "You can run commands now. Go on."

    /// The switch's name in the app's menu. An app built before the mark has an APP.md that sends
    /// the user there, and an agent that follows it: naming the switch is asking too.
    package static let switchName = "Use the Terminal"

    /// A reply without that mark, and whether it asked.
    package static func asking(_ text: String) -> (text: String, asks: Bool) {
        let said = text.replacingOccurrences(of: asks, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (said, text.contains(asks) || text.localizedCaseInsensitiveContains(switchName))
    }

    /// Why a turn failed, in words that say what to do. Claude Code's own are kept for anything
    /// that isn't its sign-in.
    package static func explain(_ error: String) -> String {
        let signIn = ["authenticat", "oauth", "/login", "api key", "not logged in"]
        if signIn.contains(where: error.lowercased().contains) {
            return "Claude Code is signed out. Run claude in Terminal, sign in with /login, then try again."
        }
        return error.isEmpty ? "Claude Code couldn't finish that" : error
    }

    package static func arguments(for turn: AgentTurn) -> [String] {
        let build = turn.session.kind == .build
        // An app's agent may hand work to subagents, as skills often say to. They are held to the
        // same tools, the same folders and the same sandbox, so they add nothing it couldn't do.
        let tools = ["Read", "Write", "Edit", "Glob", "Grep"] + (build ? ["Skill"] : ["Agent"]) + (turn.runs ? ["Bash"] : [])
        let session = turn.session.started ? ["--resume", turn.session.id] : ["--session-id", turn.session.id]
        // An app made from a repository reads its skills there as it needs them. The builder
        // is already in the folder that holds it. Claude Code would let it write there too:
        // what stops it is that `source/` is read-only on the disk.
        let source: [String] = build || turn.skills.isEmpty ? [] : ["--add-dir", turn.app.source.path]
        let reach: [String] = source + (turn.runs ? ["--add-dir", turn.app.work.path, "--settings", sandbox(for: turn)] : [])
        return ["-p", "--restricted", "--strict-mcp-config", "--tools", tools.joined(separator: ",")]
            + ["--permission-mode", "acceptEdits", "--permission-prompts", "none"]
            + (build ? ["--plugin-dir", turn.plugin.path] : []) + reach
            + ["--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            + session + ["--append-system-prompt", build ? builder(for: turn) : rules(for: turn), "--", turn.message]
    }

    /// What the user's secrets are kept in, which no command may read.
    /// ponytail: a short list of the usual places. A command can read the rest of the disk, and
    /// with only `registries` to reach has nowhere to send it. Deny reading the home folder if that isn't enough.
    static let secrets = ["~/.ssh", "~/.aws", "~/.gnupg", "~/.config/gh", "~/.netrc", "~/Library/Keychains"]

    /// The only hosts a command can reach: where Python's packages come from, so an app installs
    /// what its skill needs, into `work/`, without the user. Nothing can be sent to either.
    /// ponytail: Python only. A registry that also takes uploads on the same host (npm's does) is a
    /// way out for what a command read, so add one only after checking that.
    static let registries = ["pypi.org", "files.pythonhosted.org"]

    /// Claude Code's settings for an app that runs commands: every one in its sandbox, with no
    /// way out of it. That leaves no network but `registries`, and writing only where the agent works (memory)
    /// and in `work/`, and no launching anything outside it: `open` and Apple Events are refused,
    /// which is what keeps a script it wrote from running unsandboxed. Don't add `allowAppleEvents`
    /// or `excludedCommands`. `source/` is a folder it was added, so it's taken back by name: read-only
    /// on the disk stops a file tool, not a `chmod`.
    static func sandbox(for turn: AgentTurn) -> String {
        let settings: [String: Any] = ["sandbox": [
            "enabled": true, "failIfUnavailable": true, "autoAllowBashIfSandboxed": true, "allowUnsandboxedCommands": false,
            "filesystem": ["denyWrite": [turn.app.source.path], "denyRead": secrets],
            "network": ["allowedDomains": registries],
        ]]
        // Nothing here can fail to encode. If it did, "{}" has no sandbox, so Bash is denied.
        return (try? JSONSerialization.data(withJSONObject: settings)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// What an app's agent is told about running things.
    private static func commands(for turn: AgentTurn) -> String {
        guard turn.runs else {
            return """
                You can't run commands yet, or go to the web. When a skill needs a command run, don't tell the \
                user to run it and don't send them to a menu: say in a sentence what you need to run, and end \
                your message with a line that is exactly \(asks). Yokan then asks the user to let this app run \
                commands, and you are told if they do, in this same session: never ask for a new session or \
                for a menu, whatever <app> or an earlier message says. If they don't, do the thinking yourself \
                and say exactly what they have to run.
                """
        }
        return """
            The user let this app run commands, so you have Bash, in a sandbox: no network but PyPI, and a command \
            can write only in memory and in \(turn.app.work.path). Run what a skill says to run, yourself, in \
            that folder (`cd` there first), and keep memory for what's worth remembering, not for what commands \
            make. Install the Python packages a skill needs yourself, without asking: make a virtual environment \
            there once (`python3 -m venv .venv`), `pip install` into it, and run everything with its python. \
            Check first what is already on this Mac. So a `pip install` is yours to run, never the user's. What pip can't give (Homebrew, a system tool, \
            anything the sandbox refuses that the work truly needs) you ask for, and never tell the user to run \
            it themselves: say in a sentence what the command does and why, then end your message with the one \
            command between a line that is exactly \(Command.open) and a line that is exactly \(Command.close). \
            Yokan shows it to the user, and if they approve runs it on their Mac, outside the sandbox, from \
            the work folder, and tells you how it ended. One command a message, as short and plain as it can \
            be, since the user reads it before saying yes. It can't answer questions, only a password \
            dialog, so give it the flags that keep it from asking. The sandbox can't open a file or an app either \
            (`open` and AppleScript fail): when a command makes something to look at, a video or a picture, \
            give its full path, and say Show in Finder in the app's ••• menu leads to it, in work.
            """
    }

    /// What an app is made from, as its agent is told: the one skill whole, or each of a
    /// repository's by name, to read when its turn comes.
    private static func made(for turn: AgentTurn) -> (from: String, what: String) {
        guard !turn.skills.isEmpty else { return ("the skill below", "<skill>\n\(turn.skill)\n</skill>") }
        let list = turn.skills.map { "- \($0.skill.name) (\($0.path)): \($0.skill.description.prefix(300))" }.joined(separator: "\n")
        return ("the skills of a repository, listed below", """
            <skills>
            The repository is in \(turn.app.source.path), as it came: yours to read, never to change. Before you \
            use a skill, read its SKILL.md there, whole, and whatever it points to beside it.

            \(list)
            </skills>
            """)
    }

    /// What an app's agent is told on top of Claude Code's own prompt: the skill, what the
    /// builder added, and its memory.
    static func rules(for turn: AgentTurn) -> String {
        let memory = turn.memory.isEmpty
            ? "Nothing yet: this is the first session."
            : turn.memory.map { "### \($0.name)\n\n\($0.text)" }.joined(separator: "\n\n")
        let rules = turn.rules.trimmingCharacters(in: .whitespacesAndNewlines)
        let made = made(for: turn)
        return """
            You are \(turn.app.info.name), an app the user made in Yokan, a Mac app, from \(made.from). Yokan shows \
            what you say in the app's own interface, and keeps every session, so the user comes back to this one \
            whenever they like and starts new ones whenever they like. \(turn.skills.isEmpty ? "Do what the skill says." : "Follow the workflow <app> describes, and do what each skill says when its turn comes.")

            \(made.what)

            \(rules.isEmpty ? "" : "<app>\n\(rules)\n</app>\n")
            ## Commands

            This section is how this app runs and installs things now. It holds over <app>, over a skill, and \
            over anything said earlier in this session: where one of those says you can't run or install \
            something, or that the user must run a command in their own Terminal, that was written before the \
            app could, and no longer holds. Don't repeat an earlier answer about what's missing: act on it.

            \(commands(for: turn))

            ## Memory

            The folder you are in is this app's memory: files that outlive every session, and the only place you can \
            write. A session never starts from nothing. Begin from what memory says, and say where things stand \
            instead of asking the user what they already told you. Keep memory true as you go: when something a \
            later session would want changes (progress, a decision, what the user got wrong, what comes next), write \
            it right then, since the user may close the window at any moment. Never ask the user to save, copy or \
            paste state, even where the skill offers that: memory is how this app remembers.

            Memory as this session began:

            \(memory)
            """
    }

    /// What the builder is told. The steps themselves are its skills.
    static func builder(for turn: AgentTurn) -> String {
        let added = turn.skills.isEmpty
            ? "The user added the skill in SKILL.md, and you are building \(turn.app.info.name) from it, with them, in this folder."
            : """
              The user added a whole repository of skills, \(turn.skills.count) of them, which is in source/ as it \
              came. You are building \(turn.app.info.name), one app for all of them, with the user, in this folder. \
              So before step 1, load yokan:explore: read everything there and work out how the skills are used together.
              """
        return """
        You are Yokan's builder. Yokan is a Mac app that turns a skill into an app: the skill keeps doing the \
        thinking, and the app gives it an interface of its own, memory that outlives every session, and sessions \
        the user can come back to, so the skill never starts again from nothing. \(added)

        The build is four steps, each a skill of yours. Load a step's skill with the Skill tool as you reach it, and \
        write the step you are on to "stage" in app.json:

        0. explore (yokan:explore), only for an app made from a repository of skills, which has a source/ \
        folder: read all of it, and work out the workflow its skills make. The stage stays "interview".
        1. interview (yokan:interview): read the skill, then ask the user what only they can answer, with a \
        rough sketch of each answer.
        2. design (yokan:design): work out what kind of tool this skill is, then draw three versions of its \
        interface, on sample data, for the user to choose from.
        3. adjust (yokan:adjust): change the one they chose until it's right. A user who comes back later to \
        change the interface lands here too.
        4. implement (yokan:implement): write what the running app needs, check it, and set stage to "done".

        yokan:interface is the contract interface.html is written to: load it before you write or change one.

        The user reads your messages in a narrow chat beside a live preview, which redraws each time you change a \
        file: the versions in designs/ while they are choosing, interface.html after. So keep messages to a few plain sentences, never paste code or file contents into \
        them, and ask one question at a time. When a question has a few likely answers, end the message with them \
        as a checklist, one per line, your recommendation first, like this:

        - [ ] Always in view, beside the conversation
        - [ ] Only when I ask for it

        Yokan draws those as buttons. The user can always type something else.
        """
    }
}

/// What a turn is doing, as Claude Code's stream says it.
package enum AgentEvent: Equatable, Sendable {
    /// More of what it's saying, as it arrives.
    case delta(String)
    /// A whole piece of what it said.
    case said(String)
    /// What it's doing instead of talking: "Writing skill-map.json".
    case doing(String)
    /// A tool finished, so the app's files may have changed.
    case touched
    /// The end, with what went wrong if anything did.
    case done(error: String?)
}

package enum AgentStream {
    /// One line of `--output-format stream-json`.
    package static func events(from line: String) -> [AgentEvent] {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [] }
        let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        switch event["type"] as? String {
        case "stream_event":
            let delta = (event["event"] as? [String: Any])?["delta"] as? [String: Any]
            guard delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String else { return [] }
            return [.delta(text)]
        case "assistant":
            // What Claude Code says itself when a turn fails ("Failed to authenticate…") comes as
            // a message from a model called <synthetic>. It's the error, which `result` carries.
            if (event["message"] as? [String: Any])?["model"] as? String == "<synthetic>" { return [] }
            return content.compactMap { block in
                switch block["type"] as? String {
                case "text": (block["text"] as? String).map(AgentEvent.said)
                case "tool_use": .doing(describe(block["name"] as? String ?? "", block["input"] as? [String: Any] ?? [:]))
                default: nil
                }
            }
        case "user":
            return content.contains { $0["type"] as? String == "tool_result" } ? [.touched] : []
        case "result":
            let failed = event["is_error"] as? Bool == true
            return [.done(error: failed ? Agent.explain(event["result"] as? String ?? "") : nil)]
        default:
            return []
        }
    }

    private static func describe(_ tool: String, _ input: [String: Any]) -> String {
        let file = (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "a file"
        return switch tool {
        case "Write": "Writing \(file)"
        case "Edit": "Changing \(file)"
        case "Read": "Reading \(file)"
        case "Skill": "Getting ready"
        case "Agent": "Handing work to a helper"
        case "Bash": "Running " + ((input["description"] as? String).map { "“\($0.prefix(60))”" } ?? "a command")
        default: "Looking through its files"
        }
    }
}

/// A turn's answer as it builds up, one event at a time.
package struct Reply: Equatable, Sendable {
    private let said: [String]
    private let saying: String
    /// What it's doing right now, when that isn't talking.
    package let status: String
    package let error: String?

    package init() { (said, saying, status, error) = ([], "", "", nil) }

    private init(said: [String], saying: String, status: String, error: String?) {
        (self.said, self.saying, self.status, self.error) = (said, saying, status, error)
    }

    /// Everything said so far, a blank line between the pieces a tool call came between.
    package var text: String {
        (said + [saying]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    package func applying(_ event: AgentEvent) -> Reply {
        switch event {
        case .delta(let more): Reply(said: said, saying: saying + more, status: "", error: error)
        // The whole of what the deltas were spelling out.
        case .said(let text): Reply(said: said + [text], saying: "", status: "", error: error)
        case .doing(let what): Reply(said: said, saying: saying, status: what, error: error)
        case .touched: self
        case .done(let failure): Reply(said: said, saying: saying, status: "", error: failure)
        }
    }
}

/// Runs a turn: the user's Claude Code, in the turn's folder, its events as they come.
package final class AgentProcess: Sendable {
    /// Where Claude Code is, and the PATH it runs with.
    package typealias Find = @Sendable () throws -> (claude: URL, path: String)

    private let errors: URL
    private let find: Find

    package init(errors: URL, find: @escaping Find = AgentProcess.loginShell) {
        (self.errors, self.find) = (errors, find)
    }

    /// Ends when the turn does; stops Claude Code if whoever is listening stops.
    package func events(for turn: AgentTurn) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached { [errors, find] in
                do {
                    let found = try find()
                    try FileManager.default.createDirectory(at: turn.folder, withIntermediateDirectories: true)
                    if turn.runs { try FileManager.default.createDirectory(at: turn.app.work, withIntermediateDirectories: true) }
                    FileManager.default.createFile(atPath: errors.path, contents: nil)
                    let process = Process()
                    process.executableURL = found.claude
                    process.arguments = Agent.arguments(for: turn)
                    process.currentDirectoryURL = turn.folder
                    process.environment = ProcessInfo.processInfo.environment.merging(["PATH": found.path]) { $1 }
                    // Nothing to read: without it Claude Code waits three seconds for a prompt on stdin.
                    process.standardInput = FileHandle.nullDevice
                    // A file, not a pipe: nobody reads it until the end, and a full pipe would stop Claude Code.
                    process.standardError = try FileHandle(forWritingTo: errors)
                    let output = Pipe()
                    process.standardOutput = output
                    let (exited, exit) = AsyncStream<Void>.makeStream()
                    process.terminationHandler = { _ in exit.finish() }
                    try process.run()

                    var finished = false
                    try await withTaskCancellationHandler {
                        for try await line in output.fileHandleForReading.bytes.lines {
                            for event in AgentStream.events(from: line) {
                                if case .done = event { finished = true }
                                continuation.yield(event)
                            }
                        }
                    } onCancel: {
                        process.terminate()
                    }
                    for await _ in exited {}
                    if !finished, !Task.isCancelled {
                        let said = (try? String(contentsOf: errors, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        throw YokanError(said.isEmpty ? "Claude Code stopped before it answered" : Agent.explain(String(said.suffix(300))))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Claude Code as the user's login shell finds it: an app started from the Dock has none of
    /// the PATH their terminal has.
    package static let loginShell: Find = {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["+m", "-ilc", #"printf '\n%s\n%s\n' "$(whence -p claude)" "$PATH""#]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        // The last two lines, after whatever .zshrc printed: where it is (empty when it isn't), and PATH.
        let lines = said.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropLast()
        guard lines.count >= 2, lines[lines.count - 2].hasPrefix("/") else {
            throw YokanError("Yokan's apps run on Claude Code, and this Mac doesn't have it: install it from claude.com/claude-code")
        }
        return (URL(fileURLWithPath: lines[lines.count - 2]), lines[lines.count - 1])
    }
}
