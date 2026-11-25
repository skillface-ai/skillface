import Foundation

/// Antigravity and Grok. Neither has a sandbox Yokan can hold to PyPI and an app's two folders
/// (`AgentProvider.sandboxes`), so neither gets a shell, the web or a file: every tool is denied,
/// the app's files go in the prompt, and what comes back is a message and files for Yokan to
/// check and save, as Codex's does without the terminal. It runs in an empty folder, so nothing
/// a skill brought can configure it.
struct ToollessInvocation: Invocation {
    let executable: URL
    let directory: URL
    let arguments: [String]
    let provider: AgentProvider
    var stdin: URL? { nil }

    /// Antigravity has no flag that takes a tool away, so each kind is denied by rule, over
    /// whatever the user's own settings allow. Its web search has no rule and stays: that
    /// reaches Google, which is already sent the whole prompt.
    static let antigravity = """
        {"toolPermission":"strict","agentMode":"","enableTerminalSandbox":true,"permissions":{"allow":[],"deny":["command(*)","write_file(*)","read_file(*)","mcp(*)","read_url(*)","execute_url(*)"]}}
        """
    /// ponytail: no `--sandbox` under these. Grok's refuses to start on a Mac with Docker's
    /// socket, and with no tool left it has nothing to hold. Add it if a tool is ever let back.
    static let grok = ["--tools", "", "--deny", "*", "--permission-mode", "dontAsk", "--disable-web-search", "--no-subagents", "--no-plan"]

    init(_ turn: AgentTurn, executable: URL) throws {
        (self.executable, provider) = (executable, turn.provider)
        let folder = FileManager.default.temporaryDirectory.appending(path: "yokan-\(turn.provider.rawValue)-\(UUID())")
        directory = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let prompt = try turn.instructions + turn.files() + turn.conversation
            func file(_ name: String, _ text: String) throws -> String {
                let url = folder.appending(path: name)
                try Data(text.utf8).write(to: url)
                return url.path
            }
            if turn.provider == .grok {
                arguments = try ["--prompt-file", file("prompt", prompt), "--json-schema", CodexInvocation.schema,
                                 "--output-format", "streaming-messages-json"] + Self.grok
            } else {
                // ponytail: Antigravity takes its prompt only as an argument, and macOS takes about a
                // megabyte of those. An app with more than that to send fails to start: lower
                // `YokanHome.codexBudget` for it if that's ever met.
                arguments = try ["--print=" + prompt, "--output-format", "stream-json", "--disable-slash-commands",
                                 "--json-schema", file("schema.json", CodexInvocation.schema),
                                 "--settings", file("settings.json", Self.antigravity)]
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Both print a line of JSON for each step and end on the result: Antigravity's wrapped in an
    /// event, Grok's as the line itself. The answer is kept for `finish`, which checks it.
    func events(from line: String) -> [AgentEvent] {
        guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [] }
        guard let result = event["result"] as? [String: Any] ?? (event["type"] as? String == "result" ? event : nil) else {
            return [.doing("Thinking")]
        }
        let failed = result["is_error"] as? Bool == true || (result["status"] as? String ?? "SUCCESS") != "SUCCESS"
        guard !failed, let answered = result["structured_output"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: answered), (try? data.write(to: answer)) != nil else {
            let detail = (result["errors"] as? [String])?.joined(separator: "\n") ?? result["error"] as? String ?? ""
            return [.done(error: provider.failure(detail))]
        }
        return [.done(error: nil)]
    }

    func finish(_ turn: AgentTurn) throws -> [AgentEvent] { try turn.save(Data(contentsOf: answer)) }
}
