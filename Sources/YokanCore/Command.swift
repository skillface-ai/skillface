import Foundation

/// A command an app's agent can't run in its sandbox (Homebrew, an installer) and asks the user
/// to run instead. It is untrusted, so it only ever runs as the user saw it, once, after they
/// said yes: on their Mac, as them, with nothing held back. That is the point of asking.
package struct Command: Equatable, Sendable {
    package let text: String

    /// How an agent asks: the command between these two lines, at the end of a message.
    package static let open = "[[run]]"
    package static let close = "[[/run]]"
    /// Longer than this is nothing a person reads before saying yes.
    static let limit = 2_000

    /// What a reply asks to have run, if anything, and the reply as the user reads it: the
    /// command in a code block where the marks were.
    package static func asked(in reply: String) -> (text: String, command: Command?) {
        guard let start = reply.range(of: open), let end = reply.range(of: close, range: start.upperBound..<reply.endIndex) else {
            return (reply, nil)
        }
        let text = reply[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = reply.replacingCharacters(in: start.lowerBound..<end.upperBound, with: "```\n\(text)\n```")
        // Only what a person can read as it is: plain ASCII. A character that doesn't show, or
        // that reorders the line, would make the sheet say one thing and the shell run another.
        let plain = text.unicodeScalars.allSatisfy { (0x20..<0x7F).contains($0.value) || $0 == "\n" }
        return (shown, text.isEmpty || text.count > limit || !plain ? nil : Command(text: text))
    }

    package struct Outcome: Equatable, Sendable {
        package let status: Int32
        /// The end of what it printed.
        package let output: String
    }

    /// What `sudo` asks for a password with, there being no terminal: a dialog of the Mac's own.
    /// The password goes from it to sudo, and Yokan never sees it.
    static let askpass = """
        #!/bin/sh
        /usr/bin/osascript -e 'text returned of (display dialog "A command you approved in Yokan needs your Mac password." default answer "" with hidden answer with title "Yokan")'

        """

    /// Runs it in `folder`, in the user's login shell so their PATH finds what their terminal
    /// does. Ends when it does; stops it if whoever is waiting stops.
    ///
    /// ponytail: no time limit, since an install can take an hour: the user stops it. It can
    /// answer a password and nothing else, so a command that asks a question waits until stopped.
    package func run(in folder: URL, log: URL, askpass: URL) async throws -> Outcome {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(Self.askpass.utf8).write(to: askpass)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
        // A file, not a pipe: nobody reads it until the end, and a full pipe would stop the command.
        try Data().write(to: log)
        let output = try FileHandle(forWritingTo: log)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", text]
        process.currentDirectoryURL = folder
        process.environment = ProcessInfo.processInfo.environment.merging(["SUDO_ASKPASS": askpass.path, "NONINTERACTIVE": "1"]) { $1 }
        (process.standardInput, process.standardOutput, process.standardError) = (FileHandle.nullDevice, output, output)
        let (exited, exit) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in exit.finish() }
        try process.run()
        await withTaskCancellationHandler { for await _ in exited {} } onCancel: { process.terminate() }
        let said = String(decoding: (try? Data(contentsOf: log)) ?? Data(), as: UTF8.self)
        return Outcome(status: process.terminationStatus, output: String(said.suffix(Self.limit)).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// What the agent is told afterwards, for the user.
    package func report(_ outcome: Outcome) -> String {
        let how = outcome.status == 0 ? "It finished." : "It failed, with status \(outcome.status)."
        return "I ran this for you:\n\n```\n\(text)\n```\n\n\(how)" + (outcome.output.isEmpty ? "" : " The end of what it printed:\n\n```\n\(outcome.output)\n```")
    }

    package static let refused = "I didn't run that. Go on without it."
}
