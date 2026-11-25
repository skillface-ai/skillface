import Foundation

package enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case claude, codex

    package var name: String { self == .claude ? "Claude Code" : "Codex" }

    func failure(_ detail: String) -> String {
        if self == .claude { return Agent.explain(detail) }
        if ["unauthorized", "401", "not logged in", "authentication"].contains(where: detail.lowercased().contains) {
            return "Codex needs you to sign in. Run codex login in Terminal, then try again."
        }
        return detail.isEmpty ? "Codex couldn't finish that turn." : detail
    }
}

extension AgentTurn {
    /// Claude resumes its own thread. Replay just the exchange it missed while Codex was selected.
    var claudeMessage: String {
        let lastClaude = session.messages.lastIndex { $0.role == .assistant && $0.provider != .codex }
        let missed = session.messages.dropFirst(lastClaude.map { $0 + 1 } ?? 0)
        guard missed.contains(where: { $0.provider == .codex }) else { return message }
        return transcript(missed) + "\n\nUser: " + message
    }

    func transcript(_ messages: ArraySlice<Session.Message>) -> String {
        messages.map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n\n")
    }
}

/// Codex runs outside the app folder so imported project settings cannot configure its tools.
/// Without terminal permission it returns proposed text files for Yokan to validate and save.
struct CodexInvocation {
    let executable: URL
    let directory: URL
    let arguments: [String]
    var input: URL { directory.appending(path: "prompt") }
    private var answer: URL { directory.appending(path: "answer") }

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
            var prompt = turn.session.kind == .build
                ? Agent.builder(for: turn) + "\nThe builder skills follow in full. Use them directly.\n" + BuilderSkills.all.map(\.text).joined(separator: "\n\n")
                : Agent.rules(for: turn)
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
                let files = YokanHome.codexContext(turn)
                prompt += "\nHere are the current app files as JSON:\n" + String(decoding: try JSONEncoder().encode(files), as: UTF8.self)
                prompt += "\nReturn your user-facing reply as message and every changed text file in files, with its relative path and complete text. Use an empty array if nothing changed. Paths are relative to " + (turn.session.kind == .build ? "the app folder." : "memory/.")
            }
            prompt += "\n\nConversation so far:\n" + turn.transcript(turn.session.messages[...]) + "\n\nUser: " + turn.message
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

    private static let schema = """
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
        if turn.runs { return [.said(String(decoding: data, as: UTF8.self))] }
        let response = try JSONDecoder().decode(Answer.self, from: data)
        let home = YokanHome(root: turn.app.folder.deletingLastPathComponent().deletingLastPathComponent())
        try home.apply(response.files, to: turn)
        return [.touched, .said(response.message)]
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}
