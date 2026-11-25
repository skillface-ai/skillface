import Foundation

/// An app made from a skill, or from a repository of them: a folder. Everything about it is a
/// file there, so the builder changes it by editing files, and nothing is kept anywhere else.
///
///     SKILL.md         the skill, as it was added, in an app made from one
///     source/          the repository, as it came, in an app made from several: read, never written
///     APP.md           what the builder adds for the agent running it: which memory to keep, and how
///     app.json         its name, symbol, and how far the build is
///     interface.html   what the user sees
///     demo.json        sample memory and messages, for the design's preview
///     designs/         the versions the builder drew to choose from: `A.html`…, and `index.json`
///     sketches/        a rough picture of each answer to the question being asked: `1.html`…
///     memory/          what outlives every session; the running agent's one folder
///     work/            where its commands run and what they make, if the user lets it run any
///     sessions/        every conversation, one JSON file each
package struct SkillApp: Identifiable, Equatable, Sendable {
    /// Its folder's name.
    package let id: String
    package let folder: URL
    package let info: Info

    package var skill: URL { folder.appending(path: "SKILL.md") }
    package var source: URL { folder.appending(path: "source") }
    package var rules: URL { folder.appending(path: "APP.md") }
    package var interface: URL { folder.appending(path: "interface.html") }
    package var demo: URL { folder.appending(path: "demo.json") }
    package var designs: URL { folder.appending(path: "designs") }
    package var sketches: URL { folder.appending(path: "sketches") }
    package var memory: URL { folder.appending(path: "memory") }
    package var work: URL { folder.appending(path: "work") }
    package var sessions: URL { folder.appending(path: "sessions") }

    package func with(_ info: Info) -> SkillApp { SkillApp(id: id, folder: folder, info: info) }

    /// The build's steps, in order. `done` is an app in use.
    package enum Stage: String, Codable, CaseIterable, Sendable {
        case interview, design, adjust, implement, done
    }

    /// `app.json`. The builder writes it too, so whatever it leaves out or gets wrong falls back
    /// rather than losing the app.
    package struct Info: Codable, Equatable, Sendable {
        package let name: String
        /// An SF Symbol's name.
        package let symbol: String
        package let stage: Stage
        /// The session the app was built in, kept so changing the interface later picks it up.
        package let buildSession: String?

        package init(name: String, symbol: String = "sparkles", stage: Stage = .interview, buildSession: String? = nil) {
            (self.name, self.symbol, self.stage, self.buildSession) = (name, symbol, stage, buildSession)
        }

        package init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? values.decode(String.self, forKey: .name)) ?? "Untitled"
            symbol = (try? values.decode(String.self, forKey: .symbol)) ?? "sparkles"
            stage = (try? values.decode(Stage.self, forKey: .stage)) ?? .interview
            buildSession = try? values.decode(String.self, forKey: .buildSession)
        }

        package func at(_ stage: Stage) -> Info { Info(name: name, symbol: symbol, stage: stage, buildSession: buildSession) }
        package func built(in session: String) -> Info { Info(name: name, symbol: symbol, stage: stage, buildSession: session) }

        /// As the user renamed it: one line, not too long, and never nothing. Only what it's
        /// called changes; its folder keeps the name it was made with.
        package func named(_ name: String) -> Info {
            let line = name.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return line.isEmpty ? self : Info(name: String(line.prefix(Self.nameLimit)), symbol: symbol, stage: stage, buildSession: buildSession)
        }

        static let nameLimit = 60
    }
}

/// One version of an app's interface, drawn for the user to choose from.
package struct Design: Identifiable, Equatable, Sendable {
    /// Its file's name in `designs/`, without the `.html`: "A".
    package let id: String
    /// What the builder calls it: "Focus".
    package let name: String
    /// What it's for, in a line.
    package let idea: String
    package let html: String

    package init(id: String, name: String, idea: String, html: String) {
        (self.id, self.name, self.idea, self.html) = (id, name, idea, html)
    }
}

/// One of the skills of an app made from several: where it is in `source/`, and what it says.
package struct SourceSkill: Identifiable, Equatable, Sendable {
    /// Its SKILL.md's path in `source/`: "skills/review/SKILL.md".
    package let path: String
    package let skill: Skill
    package var id: String { path }

    package init(path: String, skill: Skill) { (self.path, self.skill) = (path, skill) }
}

/// A file as the app shows it: a memory, the skill, the rules.
package struct TextFile: Identifiable, Equatable, Sendable {
    /// Its path in its folder.
    package let name: String
    package let text: String
    package var id: String { name }

    package init(name: String, text: String) { (self.name, self.text) = (name, text) }
}

/// One conversation with an app, or with the builder about it. Claude Code keeps its own record
/// under the same id, which is how the next message continues it; this is what Yokan shows.
package struct Session: Codable, Identifiable, Equatable, Sendable {
    package enum Kind: String, Codable, Sendable { case build, use }
    package enum Role: String, Codable, Sendable { case user, assistant }

    package struct Message: Codable, Equatable, Sendable {
        package let role: Role
        package let text: String
        package let provider: AgentProvider?
        package init(role: Role, text: String, provider: AgentProvider? = nil) {
            (self.role, self.text, self.provider) = (role, text, provider)
        }
    }

    package let id: String
    package let kind: Kind
    package let created: Date
    package let updated: Date
    package let messages: [Message]
    /// Whether Claude Code has it yet: the first message starts it, every later one resumes it.
    package let started: Bool

    package init(
        id: String = UUID().uuidString.lowercased(), kind: Kind, created: Date = .now, updated: Date = .now,
        messages: [Message] = [], started: Bool = false
    ) {
        (self.id, self.kind, self.created, self.updated, self.messages, self.started) = (id, kind, created, updated, messages, started)
    }

    /// What the user first said, which is what a session is about.
    package var title: String {
        guard let first = messages.first(where: { $0.role == .user })?.text.split(whereSeparator: \.isNewline).first else { return "New Session" }
        return first.count > 60 ? first.prefix(60) + "…" : String(first)
    }

    package func adding(_ message: Message) -> Session {
        Session(id: id, kind: kind, created: created, updated: .now, messages: messages + [message], started: started)
    }

    /// What the user said last, if nothing answered it: a turn that failed, to be tried again.
    package var unanswered: String? {
        messages.last.flatMap { $0.role == .user ? $0.text : nil }
    }

    /// Without its last message.
    package func retracting() -> Session {
        Session(id: id, kind: kind, created: created, updated: updated, messages: Array(messages.dropLast()), started: started)
    }

    /// Once Claude Code has answered in it.
    package func begun() -> Session {
        Session(id: id, kind: kind, created: created, updated: updated, messages: messages, started: true)
    }
}

/// The answers a question offers, written as a checklist closing the message: the builder's
/// chat draws them as buttons.
package enum Choices {
    package static func split(_ text: String) -> (body: String, choices: [String]) {
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let choices = lines.reversed().prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [ ]") }.reversed()
            .map { $0.trimmingCharacters(in: .whitespaces).dropFirst(5).trimmingCharacters(in: .whitespaces) }
        let body = lines.dropLast(choices.count).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (body, choices.filter { !$0.isEmpty })
    }
}
