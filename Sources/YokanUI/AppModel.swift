import Foundation
import Observation
import YokanCore

/// Every workflow, and every failure as a `notice`. The disk is the truth: each change is
/// written through `YokanHome`, then read back with `refresh`, which is also how the screens
/// catch up with what an agent wrote.
@MainActor @Observable
package final class AppModel {
    /// Which of an app's files is being changed.
    package enum Files { case memory, skill }

    /// An answer on its way.
    package struct Live: Equatable {
        package let text: String
        package let status: String
    }

    package let home: YokanHome
    package private(set) var provider: AgentProvider
    private let agent: AgentProcess

    package private(set) var apps: [SkillApp] = []
    /// The apps' ids in the order the user put them. Read from the disk like the rest, and kept
    /// here because a move changes nothing else: the same apps, so no screen would hear of it.
    package private(set) var arrangement: [String] = []
    /// The app that's open. Nil is home.
    package var selected: String? { didSet { if selected != oldValue { open() } } }
    /// Home's sheet of every app.
    package var showingAll = false { didSet { if !showingAll { (arranging, renaming) = (false, nil) } } }
    /// All Apps with its apps loose: to be moved, deleted and renamed.
    package var arranging = false
    /// The app whose name is being typed.
    package var renaming: String?
    /// An open app's memory, beside it.
    package var knowing = false
    package var showingSkill = false
    /// The selected app's, newest first, the one it's built in among them.
    package private(set) var sessions: [Session] = []
    package var sessionID: String?
    package private(set) var memory: [TextFile] = []
    package private(set) var interface = ""
    package private(set) var demo = ""
    /// The versions the builder drew to choose from, and the one being looked at.
    package private(set) var designs: [Design] = []
    package var designID: String?
    /// A rough picture of each answer to the builder's question, and the answer being pointed at.
    package private(set) var sketches: [String] = []
    package var sketched = 0
    /// What's typed and not yet sent, by session: it outlives the view, which goes when the app is shown.
    package var drafts: [String: String] = [:]
    package private(set) var skill = ""
    /// The skills of an app made from a repository of them. Then `skill` is empty.
    package private(set) var skills: [SourceSkill] = []
    package private(set) var rules = ""
    /// Whether the user let this app run commands.
    package private(set) var terminal = false
    /// Whether the user is being asked to let the open app run commands, and what is said, in
    /// which session, once they say yes: the agent that asked goes on, or a new app rehearses.
    package var allowing = false
    /// A command the open app's agent asked to have run outside its sandbox, for the user to
    /// read and say yes or no to.
    package struct Proposal: Identifiable, Equatable {
        package let session: String
        package let command: Command
        package var id: String { session }
    }
    package var proposed: Proposal?
    private var waiting: (session: String, message: String)?
    package var notice: String?
    package var adding = false
    /// The sessions whose agent is answering, by id, whichever app they're in.
    package private(set) var live: [String: Live] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    package init(home given: YokanHome? = nil, agent: AgentProcess? = nil) {
        // First, for the standard home: anything written would make the new folder, and the old
        // one would never be moved to it.
        let moved = given == nil ? Result { try YokanHome.adoptFormer() } : .success(())
        let home = given ?? .standard()
        self.provider = home.provider
        self.home = home
        self.agent = agent ?? AgentProcess(errors: home.errors)
        attempt { try BuilderSkills.write(to: home.plugin) }
        if case .failure(let error) = moved { notice = error.localizedDescription }
        (apps, arrangement) = (home.apps(), home.arrangement())
    }

    // MARK: What's showing

    package var app: SkillApp? { apps.first { $0.id == selected } }
    /// Every app, the one used last first.
    package var recent: [SkillApp] {
        apps.map { ($0, home.lastUsed($0)) }.sorted { $0.1 > $1.1 }.map(\.0)
    }
    /// Every app, in the order the user put them, if they have.
    package var arranged: [SkillApp] { YokanHome.arranged(apps, by: arrangement) }
    package var hasArrangement: Bool { !arrangement.isEmpty }
    package var useSessions: [Session] { sessions.filter { $0.kind == .use } }
    package var session: Session? { useSessions.first { $0.id == sessionID } }
    package var buildSession: Session? { sessions.first { $0.id == app?.info.buildSession } }

    /// A session's messages, with the answer on its way as the last.
    package func messages(of session: Session) -> [Session.Message] {
        guard let text = live[session.id]?.text, !text.isEmpty else { return session.messages }
        return session.messages + [Session.Message(role: .assistant, text: text)]
    }

    package func state(of session: Session) -> Interface.State {
        Interface.State(
            app: app?.info.name ?? "", session: session.title, messages: messages(of: session), memory: memory,
            busy: live[session.id] != nil, status: live[session.id]?.status ?? "")
    }

    package var design: Design? { designs.first { $0.id == designID } ?? designs.first }
    /// While the user is choosing between versions, rather than changing the one they chose.
    package var choosing: Bool { app?.info.stage == .design && !designs.isEmpty }

    package var preview: Interface.State { Interface.preview(of: app?.info.name ?? "", demo: demo) }

    /// What the app is made from, and what the builder added. A repository's skills go by
    /// where they are, and after the workflow that says how they're used.
    package var skillFiles: [TextFile] {
        let added = TextFile(name: "APP.md", text: rules)
        guard !skills.isEmpty else { return [TextFile(name: "SKILL.md", text: skill), added] }
        return [added] + skills.map { TextFile(name: "source/" + $0.path, text: $0.skill.text) }
    }

    /// An interface's own script failed. Said in words the user can hand to the builder.
    package func interfaceFailed(_ error: String) {
        notice = "The interface has an error: \(error)"
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { notice = error.localizedDescription }
    }

    /// Reads the selected app again: what the user changed, or its agent did.
    package func refresh() {
        (apps, arrangement) = (home.apps(), home.arrangement())
        guard let app else {
            (sessions, memory, interface, demo, skill, rules, designs, sketches, skills) = ([], [], "", "", "", "", [], [], [])
            terminal = false
            if selected != nil { selected = nil }
            return
        }
        terminal = home.runs(app)
        sessions = home.sessions(of: app)
        memory = home.memory(of: app)
        (interface, demo) = (home.text(at: app.interface), home.text(at: app.demo))
        designs = home.designs(of: app)
        sketches = home.sketches(of: app)
        (skill, rules) = (home.text(at: app.skill), home.text(at: app.rules))
        // ponytail: walks `source/` each time, which nothing changes. Read it once per app if a
        // big repository makes a build's screen slow.
        skills = home.skills(of: app)
        // An app in use always has a session to type into.
        if app.info.stage == .done, session == nil {
            if let newest = useSessions.first { sessionID = newest.id } else { newSession() }
        }
    }

    private func open() {
        (sessionID, designID, showingAll, knowing, showingSkill) = (nil, nil, false, false, false)
        refresh()
    }

    package func selectProvider(_ choice: AgentProvider) {
        attempt { try home.selectProvider(choice) }
        provider = home.provider
    }

    // MARK: Apps

    /// A new app from what was pasted: a skill, a link to one, or a link to a repository of
    /// them. Its build starts at once.
    package func add(pasted: String) async -> Bool {
        await adding {
            if let repo = Repo(pasted) {
                let unpacked = FileManager.default.temporaryDirectory.appending(path: "yokan-repo-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: unpacked) }
                return try home.create(from: try await repo.download(into: unpacked), named: repo.title)
            }
            let link = Skill.source(pasted)
            let text = if let link { try await Skill.fetch(link) } else { pasted }
            return try home.create(Skill(text: text))
        }
    }

    /// A new app from a folder of skills on this Mac.
    package func add(folder: URL) async -> Bool {
        await adding { try home.create(from: folder, named: Skill.title(folder.lastPathComponent)) }
    }

    private func adding(_ create: () async throws -> SkillApp) async -> Bool {
        do {
            let app = try await create()
            apps = home.apps()
            selected = app.id
            if let build = app.info.buildSession { send(skills.isEmpty ? Agent.begin : Agent.beginAll, in: build) }
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    package func delete(_ app: SkillApp) {
        for session in home.sessions(of: app) { stop(session.id) }
        attempt { try home.delete(app) }
        if selected == app.id { selected = nil }
        refresh()
    }

    /// One app takes another's place in `shown`, the order they're in on screen, which becomes
    /// the user's arrangement.
    package func move(_ id: String, to target: String, in shown: [SkillApp]) {
        attempt { try home.arrange(YokanHome.moving(id, to: target, in: shown.map(\.id))) }
        refresh()
    }

    /// Lets the open app run commands, or stops it. It holds from the next message.
    package func allowTerminal(_ on: Bool) {
        guard let app else { return }
        attempt { try home.allow(app, toRun: on) }
        refresh()
        let asked = waiting
        waiting = nil
        if terminal, let asked { send(asked.message, in: asked.session) }
    }

    /// A new app tries itself out before its user needs it to work, if the builder left it a
    /// rehearsal. It runs commands, so the user is asked first, and saying no only skips it.
    private func rehearse() {
        guard Agent.rehearses(rules), useSessions.allSatisfy(\.messages.isEmpty), let id = sessionID else { return }
        if terminal { send(Agent.rehearse, in: id) } else { (waiting, allowing) = ((id, Agent.rehearse), true) }
    }

    package func rename(_ app: SkillApp, to name: String) {
        attempt { try home.save(app.info.named(name), of: app) }
        refresh()
    }

    /// Back to the builder, in the session it was built in, so it knows what's there and why.
    package func editInterface() {
        guard let app else { return }
        attempt {
            let build = buildSession ?? Session(kind: .build)
            if buildSession == nil { try home.save(build, in: app) }
            try home.save(app.info.at(.adjust).built(in: build.id), of: app)
        }
        refresh()
    }

    /// The version being looked at becomes the app's interface, and the builder is told which.
    package func choose() {
        guard let app, let design, let build = buildSession, live[build.id] == nil else { return }
        attempt { try home.use(design, in: app) }
        send(Agent.chose(design), in: build.id)
    }

    /// The design is right. A first build still has its last step to do; an app that already
    /// runs goes straight back to running.
    package func finish() {
        guard let app, let build = buildSession, live[build.id] == nil else { return }
        if rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            send(Agent.finish, in: build.id)
        } else {
            attempt { try home.save(app.info.at(.done), of: app) }
            refresh()
        }
    }

    package func save(_ text: String, as name: String, in files: Files) {
        guard let app else { return }
        attempt {
            switch (files, name) {
            case (.memory, _): try home.remember(text, as: name, in: app)
            case (_, "SKILL.md"): try Data(text.utf8).write(to: app.skill, options: .atomic)
            case (_, "APP.md"): try Data(text.utf8).write(to: app.rules, options: .atomic)
            // A repository's skills stay as they came.
            default: break
            }
        }
        refresh()
    }

    package func forget(_ name: String) {
        guard let app else { return }
        attempt { try home.forget(name, in: app) }
        refresh()
    }

    // MARK: Sessions

    /// The empty one if there is one, so pressing it twice doesn't leave two.
    package func newSession() {
        guard let app else { return }
        if let empty = useSessions.first(where: \.messages.isEmpty) { return sessionID = empty.id }
        let session = Session(kind: .use)
        attempt {
            try home.save(session, in: app)
            sessions = home.sessions(of: app)
            sessionID = session.id
        }
    }

    package func delete(_ session: Session) {
        guard let app else { return }
        stop(session.id)
        attempt { try home.delete(session, in: app) }
        if sessionID == session.id { sessionID = nil }
        refresh()
    }

    /// Says again what a failed turn left unanswered.
    package func retry(_ id: String) {
        guard let app, live[id] == nil, let session = sessions.first(where: { $0.id == id }), let text = session.unanswered else { return }
        attempt { try home.save(session.retracting(), in: app) }
        refresh()
        send(text, in: id)
    }

    /// The user's answer to a proposed command. Yes runs it, exactly as shown, and tells the
    /// agent how it ended; no tells it to go on without.
    package func answer(_ proposal: Proposal, run: Bool) {
        proposed = nil
        let id = proposal.session
        guard let app, live[id] == nil else { return }
        guard run else { return send(Command.refused, in: id) }
        live[id] = Live(text: "", status: "Running " + proposal.command.text.prefix(60))
        tasks[id] = Task { [weak self, home] in
            let report: String
            do {
                let outcome = try await proposal.command.run(log: home.root.appending(path: "command.log"), askpass: home.root.appending(path: "askpass.sh"))
                report = proposal.command.report(outcome)
            } catch {
                report = "That command couldn't be started: \(error.localizedDescription)"
            }
            guard let self else { return }
            (self.live[id], self.tasks[id]) = (nil, nil)
            // ponytail: the agent hears only if its app is still the open one. Keep what's owed
            // on the disk if people leave during long installs.
            if self.selected == app.id { self.send(report, in: id) } else { self.notice = "\(app.info.name)'s command ended. Open it and say so." }
        }
    }

    package func stop(_ session: String) {
        tasks[session]?.cancel()
    }

    /// Says it in the session and hears the answer as it comes. The agent may write the app's
    /// files as it goes, so the screens read them again each time a tool finishes.
    package func send(_ text: String, in id: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app, !text.isEmpty, live[id] == nil, let asked = sessions.first(where: { $0.id == id }) else { return }
        let session = asked.adding(Session.Message(role: .user, text: text, provider: provider))
        do { try home.save(session, in: app) } catch { return notice = error.localizedDescription }
        // The question they were for is answered.
        if asked.kind == .build {
            home.clearSketches(of: app)
            sketched = 0
        }
        // The turn carries the session as Claude Code has it: `started` says whether to resume.
        let turn = AgentTurn(app: app, session: asked, message: text, memory: memory, skill: skill, skills: skills, terminal: terminal, rules: rules, plugin: home.plugin, provider: provider)
        live[id] = Live(text: "", status: "")
        refresh()
        tasks[id] = Task { [weak self, agent] in
            var (reply, heard, failure) = (Reply(), false, String?.none)
            do {
                for try await event in agent.events(for: turn) {
                    (reply, heard) = (reply.applying(event), true)
                    self?.live[id] = Live(text: Agent.asking(reply.text).text, status: reply.status)
                    if event == .touched, self?.selected == app.id { self?.refresh() }
                }
            } catch {
                failure = error.localizedDescription
            }
            self?.finished(id, in: app, provider: turn.provider, reply: reply, heard: heard, failure: failure ?? reply.error)
        }
    }

    /// Keeps whatever was said, even from a turn that was stopped or failed part-way.
    private func finished(_ id: String, in app: SkillApp, provider: AgentProvider, reply: Reply, heard: Bool, failure: String?) {
        (live[id], tasks[id]) = (nil, nil)
        if let session = home.sessions(of: app).first(where: { $0.id == id }) {
            let said = Agent.asking(reply.text)
            let asked = Command.asked(in: said.text)
            let answered = asked.text.isEmpty ? session : session.adding(Session.Message(role: .assistant, text: asked.text, provider: provider))
            attempt { try home.save(heard && provider == .claude ? answered.begun() : answered, in: app) }
            // It needs a command run: the user is asked, right where they are.
            if said.asks, session.kind == .use, selected == app.id, !home.runs(app) { (waiting, allowing) = ((id, Agent.allowed), true) }
            // It needs one run outside the sandbox: the user reads it and decides.
            if let command = asked.command, session.kind == .use, selected == app.id, home.runs(app) { proposed = Proposal(session: id, command: command) }
        }
        if let failure { notice = failure }
        guard selected == app.id else { return }
        refresh()
        // `app` is as it was when the turn began: this turn is the one that finished the build.
        if app.info.stage != .done, self.app?.info.stage == .done { rehearse() }
    }
}
