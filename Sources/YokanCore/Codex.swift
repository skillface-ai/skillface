import Foundation

package enum AgentProvider: String, Codable, CaseIterable, Sendable {
    /// Each one's value is its command, and what the choice is saved as.
    case claude, codex, antigravity = "agy", grok

    package var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .grok: "Grok"
        }
    }

    /// Whether its shell can be held to PyPI and an app's two folders. One that can't never gets a shell.
    /// ponytail: Antigravity has a terminal sandbox with network rules that might do, and Grok's
    /// doesn't limit the network on macOS. Give Antigravity a profile like Codex's if apps need
    /// to run commands under it.
    package var sandboxes: Bool { self == .claude || self == .codex }

    func failure(_ detail: String) -> String {
        if self == .claude { return Agent.explain(detail) }
        if ["unauthorized", "401", "not logged in", "not signed in", "not authenticated", "authentication"].contains(where: detail.lowercased().contains) {
            let login = self == .antigravity ? "agy" : "\(rawValue) login"
            return "\(name) needs you to sign in. Run \(login) in Terminal, then try again."
        }
        return detail.isEmpty ? "\(name) couldn't finish that turn." : detail
    }
}

extension AgentTurn {
    /// Claude resumes its own thread. Replay just the exchange it missed while another agent was selected.
    var claudeMessage: String {
        let lastClaude = session.messages.lastIndex { $0.role == .assistant && ($0.provider ?? .claude) == .claude }
        let missed = session.messages.dropFirst(lastClaude.map { $0 + 1 } ?? 0)
        guard missed.contains(where: { ($0.provider ?? .claude) != .claude }) else { return message }
        return transcript(missed) + "\n\nUser: " + message
    }

    func transcript(_ messages: ArraySlice<Session.Message>) -> String {
        messages.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n\n")
    }

    /// What an agent that isn't Claude Code is told first: it has no plugin to read the builder's skills from.
    var instructions: String {
        session.kind == .build
            ? Agent.builder(for: self) + "\nThe builder skills follow in full. Use them directly.\n" + BuilderSkills.all.map(\.text).joined(separator: "\n\n")
            : Agent.rules(for: self)
    }

    /// The app's files, for an agent with no way to read them, and how to send back the ones it changes.
    func files() throws -> String {
        "\nHere are the current app files as JSON:\n" + String(decoding: try JSONEncoder().encode(YokanHome.codexContext(self)), as: UTF8.self)
            + "\nReturn your user-facing reply as message and every changed text file in files, with its relative path and complete text. Use an empty array if nothing changed. Paths are relative to " + (session.kind == .build ? "the app folder." : "memory/.")
    }

    /// The conversation again, for an agent that keeps no thread of its own.
    var conversation: String {
        "\n\nConversation so far:\n" + transcript(session.messages[...]) + "\n\nUser: " + message
    }

    /// Checks and saves the message and files such an agent answered with.
    func save(_ answer: Data) throws -> [AgentEvent] {
        let response = try JSONDecoder().decode(CodexInvocation.Answer.self, from: answer)
        try YokanHome(root: app.folder.deletingLastPathComponent().deletingLastPathComponent()).apply(response.files, to: self)
        return [.touched, .said(response.message)]
    }
}

/// Codex runs outside the app folder so imported project settings cannot configure its tools.
/// Without terminal permission it returns proposed text files for Yokan to validate and save.
struct CodexInvocation: Invocation {
    let executable: URL
    let directory: URL
    let arguments: [String]
    var input: URL { directory.appending(path: "prompt") }
    var stdin: URL? { input }

    init(_ turn: AgentTurn, executable: URL) throws {
        self.executable = executable.resolvingSymlinksInPath()
        guard try self.executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw YokanError("The Codex executable must be a regular file.")
        }
        directory = FileManager.default.temporaryDirectory.appending(path: "yokan-codex-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            var args = ["--no-daemon", "-a", "never", "exec", "--ephemeral", "--json", "--skip-git-repo-check",
                        "--ignore-user-config", "--ignore-rules", "--strict-config", "-c", "web_search=\"disabled\""]
            for feature in ["apps", "plugins", "hooks", "computer_use", "browser_use", "multi_agent", "code_mode", "goals", "view_image"] {
                args += ["--disable", feature]
            }
            var prompt = turn.instructions
            if turn.runs {
                // A named profile avoids the implicit writable cwd and temporary folders of workspace-write.
                var permissions = [":root": "read", turn.app.memory.path: "write", turn.app.work.path: "write"]
                for path in Agent.secrets + [Agent.claudeHome] {
                    permissions[(path as NSString).expandingTildeInPath] = "deny"
                }
                // Codex re-executes itself inside the sandbox, including when its binary lives under ~/.codex.
                permissions[self.executable.path] = "read"
                args += ["-c", "default_permissions=\"yokan\"", "-c", "permissions.yokan.filesystem=" + (try Self.table(permissions)),
                         "-c", "permissions.yokan.network.enabled=true", "-c", "permissions.yokan.network.allow_local_binding=false",
                         "-c", "permissions.yokan.network.domains=" + (try Self.table(Dictionary(uniqueKeysWithValues: Agent.registries.map { ($0, "allow") })))]
                prompt += "\nMemory is at \(turn.app.memory.path). Use absolute paths. Work in \(turn.app.work.path)."
            } else {
                args += ["--sandbox", "read-only", "--disable", "shell_tool", "--disable", "unified_exec"]
                let schema = directory.appending(path: "schema.json")
                try Data(Self.schema.utf8).write(to: schema)
                args += ["--output-schema", schema.path]
                prompt += try turn.files()
            }
            prompt += turn.conversation
            arguments = args + ["-o", directory.appending(path: "answer").path, "-"]
            try Data(prompt.utf8).write(to: directory.appending(path: "prompt"))
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func table(_ values: [String: String]) throws -> String {
        func quote(_ string: String) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            return String(decoding: try encoder.encode(string), as: UTF8.self)
        }
        return "{" + (try values.sorted { $0.key < $1.key }.map { try quote($0.key) + "=" + quote($0.value) }).joined(separator: ",") + "}"
    }

    static let schema = """
        {"type":"object","properties":{"message":{"type":"string"},"files":{"type":"array","items":{"type":"object","properties":{"path":{"type":"string"},"text":{"type":"string"}},"required":["path","text"],"additionalProperties":false}}},"required":["message","files"],"additionalProperties":false}
        """
    struct Answer: Decodable {
        struct File: Decodable { let path: String; let text: String }
        let message: String
        let files: [File]
    }

    func events(from line: String) -> [AgentEvent] {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [] }
        switch event["type"] as? String {
        case "thread.started": return [.doing("Thinking")]
        case "item.started":
            let item = event["item"] as? [String: Any]
            return item?["type"] as? String == "command_execution" ? [.doing("Running a command")] : []
        case "item.completed":
            let item = event["item"] as? [String: Any]
            return ["command_execution", "file_change"].contains(item?["type"] as? String ?? "") ? [.touched] : []
        case "turn.completed": return [.done(error: nil)]
        case "turn.failed":
            let detail = (event["error"] as? [String: Any])?["message"] as? String ?? ""
            return [.done(error: AgentProvider.codex.failure(detail))]
        default: return []
        }
    }

    func finish(_ turn: AgentTurn) throws -> [AgentEvent] {
        let data = try Data(contentsOf: answer)
        return turn.runs ? [.said(String(decoding: data, as: UTF8.self))] : try turn.save(data)
    }
}
