import Foundation

/// One message to an app's agent, or to the builder: everything Claude Code is started with.
package struct AgentTurn: Sendable {
    package let app: SkillApp
    package let session: Session
    package let message: String
    /// The app's memory as the session starts, which is what keeps it from starting empty.
    package let memory: [TextFile]
    package let skill: String
    package let rules: String
    /// The builder's skills, as a Claude Code plugin.
    package let plugin: URL

    package init(app: SkillApp, session: Session, message: String, memory: [TextFile], skill: String, rules: String, plugin: URL) {
        (self.app, self.session, self.message, self.memory) = (app, session, message, memory)
        (self.skill, self.rules, self.plugin) = (skill, rules, plugin)
    }

    /// Where it works, which is all it can write: the builder in the app's folder, the app's own
    /// agent in its memory, so using an app can never change its skill or its interface.
    package var folder: URL { session.kind == .build ? app.folder : app.memory }
}

/// What Claude Code is asked and told. The user's own Claude Code, contained as Yongkang
/// contains a miniapp's: `--restricted` leaves it no shell, no web and none of the user's
/// settings, acceptEdits lets it write in its folder, and with nobody to prompt, anything else
/// is denied.
package enum Agent {
    /// What the app sends for the user when a skill is added.
    package static let begin = "Turn this skill into an app with me."
    /// When they pick one of the versions drawn for them.
    package static func chose(_ design: Design) -> String { "Use version \(design.id), \(design.name)." }
    /// And when they say the design is right.
    package static let finish = "That's right. Finish the app."

    package static func arguments(for turn: AgentTurn) -> [String] {
        let build = turn.session.kind == .build
        let tools = ["Read", "Write", "Edit", "Glob", "Grep"] + (build ? ["Skill"] : [])
        let session = turn.session.started ? ["--resume", turn.session.id] : ["--session-id", turn.session.id]
        return ["-p", "--restricted", "--strict-mcp-config", "--tools", tools.joined(separator: ",")]
            + ["--permission-mode", "acceptEdits", "--permission-prompts", "none"]
            + (build ? ["--plugin-dir", turn.plugin.path] : [])
            + ["--output-format", "stream-json", "--verbose", "--include-partial-messages"]
            + session + ["--append-system-prompt", build ? builder(of: turn.app) : rules(for: turn), "--", turn.message]
    }

    /// What an app's agent is told on top of Claude Code's own prompt: the skill, what the
    /// builder added, and its memory.
    static func rules(for turn: AgentTurn) -> String {
        let memory = turn.memory.isEmpty
            ? "Nothing yet: this is the first session."
            : turn.memory.map { "### \($0.name)\n\n\($0.text)" }.joined(separator: "\n\n")
        let rules = turn.rules.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
            You are \(turn.app.info.name), an app the user made in Yonka, a Mac app, from the skill below. Yonka shows \
            what you say in the app's own interface, and keeps every session, so the user comes back to this one \
            whenever they like and starts new ones whenever they like. Do what the skill says.

            <skill>
            \(turn.skill)
            </skill>

            \(rules.isEmpty ? "" : "<app>\n\(rules)\n</app>\n")
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
    static func builder(of app: SkillApp) -> String {
        """
        You are Yonka's builder. Yonka is a Mac app that turns a skill into an app: the skill keeps doing the \
        thinking, and the app gives it an interface of its own, memory that outlives every session, and sessions \
        the user can come back to, so the skill never starts again from nothing. The user added the skill in \
        SKILL.md, and you are building \(app.info.name) from it, with them, in this folder.

        The build is four steps, each a skill of yours. Load a step's skill with the Skill tool as you reach it, and \
        write the step you are on to "stage" in app.json:

        1. interview (yonka:interview): read the skill, then ask the user what only they can answer.
        2. design (yonka:design): work out what kind of tool this skill is, then draw three versions of its \
        interface, on sample data, for the user to choose from.
        3. adjust (yonka:adjust): change the one they chose until it's right. A user who comes back later to \
        change the interface lands here too.
        4. implement (yonka:implement): write what the running app needs, check it, and set stage to "done".

        yonka:interface is the contract interface.html is written to: load it before you write or change one.

        The user reads your messages in a narrow chat beside a live preview, which redraws each time you change a \
        file: the versions in designs/ while they are choosing, interface.html after. So keep messages to a few plain sentences, never paste code or file contents into \
        them, and ask one question at a time. When a question has a few likely answers, end the message with them \
        as a checklist, one per line, your recommendation first, like this:

        - [ ] Always in view, beside the conversation
        - [ ] Only when I ask for it

        Yonka draws those as buttons. The user can always type something else.
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
            return [.done(error: failed ? (event["result"] as? String ?? "Claude Code couldn't finish that") : nil)]
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
                        throw YonkaError(said.isEmpty ? "Claude Code stopped before it answered" : String(said.suffix(300)))
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
            throw YonkaError("Yonka's apps run on Claude Code, and this Mac doesn't have it: install it from claude.com/claude-code")
        }
        return (URL(fileURLWithPath: lines[lines.count - 2]), lines[lines.count - 1])
    }
}
