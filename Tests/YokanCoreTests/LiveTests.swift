import Foundation
import Testing

@testable import YokanCore

/// The whole flow with the real Claude Code, on the user's plan, so only when asked for:
/// `YOKAN_LIVE=<folder> YOKAN_SKILL=<SKILL.md> swift test --filter Live`. It builds the skill
/// into an app in that folder, answering each question with its first choice and picking the
/// second of the versions drawn, then uses it in
/// two sessions, and prints what was said. What it proves is that the second session starts
/// from what the first one learned. With `YOKAN_REPO=<link>` too it builds that repository into
/// an app instead, and then lets it run commands and rehearse: what that proves is that a
/// skill that runs things works before anyone uses it.
struct LiveTests {
    private static let folder = ProcessInfo.processInfo.environment["YOKAN_LIVE"]

    private func say(_ message: String, in id: String, of app: SkillApp, home: YokanHome, agent: AgentProcess) async throws -> String {
        let app = try #require(home.apps().first { $0.id == app.id })
        let session = try #require(home.sessions(of: app).first { $0.id == id })
        let turn = AgentTurn(
            app: app, session: session, message: message, memory: home.memory(of: app),
            skill: home.text(at: app.skill), skills: home.skills(of: app), terminal: home.runs(app),
            rules: home.text(at: app.rules), plugin: home.plugin)
        var reply = Reply()
        let began = Date.now
        for try await event in agent.events(for: turn) {
            reply = reply.applying(event)
            if case .doing(let what) = event { print("    · \(what)") }
        }
        try home.save(session.adding(.init(role: .user, text: message)).adding(.init(role: .assistant, text: reply.text)).begun(), in: app)
        print("\n> \(message)\n\n\(reply.text)\n\(reply.error.map { "ERROR: \($0)" } ?? "")\n[\(Int(Date.now.timeIntervalSince(began)))s]")
        return reply.text
    }

    /// A real repository, fetched and made into an app's folder: `YOKAN_REPO=<link> swift test
    /// --filter Live`. It asks GitHub, and nothing of Claude Code.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YOKAN_REPO"] != nil))
    func aRepositoryOnGitHubBecomesAnAppsSource() async throws {
        let repo = try #require(Repo(ProcessInfo.processInfo.environment["YOKAN_REPO"] ?? ""))
        let work = FileManager.default.temporaryDirectory.appending(path: "yokan-live-\(UUID().uuidString)")
        let home = YokanHome(root: work.appending(path: "home"))
        let app = try home.create(from: try await repo.download(into: work.appending(path: "repo")), named: repo.title)
        let skills = home.skills(of: app)
        print("\n\(app.info.name): \(skills.count) skills in \(app.source.path)\n\(skills.map { "  \($0.path): \($0.skill.name)" }.joined(separator: "\n"))")
        #expect(!skills.isEmpty)
    }

    @Test(.enabled(if: folder != nil), .timeLimit(.minutes(90)))
    func aSkillBecomesAnAppThatRemembers() async throws {
        let home = YokanHome(root: URL(fileURLWithPath: try #require(Self.folder)))
        let agent = AgentProcess(errors: home.errors)
        try BuilderSkills.write(to: home.plugin)
        let repo = Repo(ProcessInfo.processInfo.environment["YOKAN_REPO"] ?? "")
        let skill = try repo == nil ? String(contentsOfFile: try #require(ProcessInfo.processInfo.environment["YOKAN_SKILL"]), encoding: .utf8) : ""
        let app = if let repo {
            try home.create(from: try await repo.download(into: FileManager.default.temporaryDirectory.appending(path: "yokan-live-\(UUID().uuidString)")), named: repo.title)
        } else {
            try home.create(Skill(text: skill))
        }
        let build = try #require(app.info.buildSession)
        func stage() -> SkillApp.Stage? { home.apps().first { $0.id == app.id }?.info.stage }

        var said = try await say(repo == nil ? Agent.begin : Agent.beginAll, in: build, of: app, home: home, agent: agent)
        // Its first question comes with a rough sketch of each answer.
        print("\nSKETCHES: \(home.sketches(of: app).count) for \(Choices.split(said).choices.count) choices")
        #expect(home.sketches(of: app).count == Choices.split(said).choices.count)
        try? FileManager.default.copyItem(at: app.sketches, to: home.root.appending(path: "first-sketches"))
        for _ in 0..<6 where home.designs(of: app).isEmpty {
            said = try await say(Choices.split(said).choices.first ?? "Whatever you think is best. Go on.", in: build, of: app, home: home, agent: agent)
        }
        // Three versions to choose from, and the builder waits for the choice.
        let designs = home.designs(of: app)
        print("\nDESIGNS: \(designs.map { "\($0.id) \($0.name): \($0.idea)" }.joined(separator: " | "))")
        #expect(designs.count == 3)
        #expect(stage() == .design)
        #expect(Set(designs.map(\.html)).count == 3)
        try home.use(designs[1], in: app)
        _ = try await say(Agent.chose(designs[1]), in: build, of: app, home: home, agent: agent)
        #expect(stage() == .adjust)
        #expect(home.text(at: app.interface) != Interface.starter)
        _ = try await say(Agent.finish, in: build, of: app, home: home, agent: agent)
        #expect(stage() == .done)
        #expect(!home.text(at: app.rules).isEmpty)
        #expect(home.memory(of: app).isEmpty, "the builder wrote into the user's memory")
        #expect(home.text(at: app.skill) == skill.trimmingCharacters(in: .whitespacesAndNewlines))

        let first = Session(kind: .use)
        try home.save(first, in: app)
        guard repo == nil else {
            // What the app does once it's built and its user lets it run commands.
            #expect(Agent.rehearses(home.text(at: app.rules)))
            try home.allow(app, toRun: true)
            _ = try await say(Agent.rehearse, in: first.id, of: app, home: home, agent: agent)
            print("\nSETUP: \(home.text(at: app.memory.appending(path: "setup.md")))")
            #expect(!home.text(at: app.memory.appending(path: "setup.md")).isEmpty)
            return
        }
        _ = try await say("Teach me binary search. Yes, teach me properly.", in: first.id, of: app, home: home, agent: agent)
        _ = try await say("It halves a sorted list each step, so it takes about log2(n) steps. I've never implemented it though.", in: first.id, of: app, home: home, agent: agent)
        #expect(!home.memory(of: app).isEmpty)
        print("\nMEMORY: \(home.memory(of: app).map { "\n--- \($0.name)\n\($0.text)" }.joined())")

        let second = Session(kind: .use)
        try home.save(second, in: app)
        let back = try await say("I'm back. Where were we?", in: second.id, of: app, home: home, agent: agent)
        #expect(back.localizedCaseInsensitiveContains("binary search"))
    }
}
