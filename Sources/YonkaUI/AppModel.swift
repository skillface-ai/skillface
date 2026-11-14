import Foundation
import Observation
import YonkaCore

/// Every workflow, and every failure as a `notice`. The disk is the truth: each change is
/// written through `YonkaHome`, then read back with `refresh`, which is also how the screens
/// catch up with what an agent wrote.
@MainActor @Observable
package final class AppModel {
    package enum Tab: String, CaseIterable, Identifiable {
        case sessions = "Sessions", memory = "Memory", skill = "Skill"
        package var id: String { rawValue }
    }

    /// An answer on its way.
    package struct Live: Equatable {
        package let text: String
        package let status: String
    }

    package let home: YonkaHome
    private let agent: AgentProcess

    package private(set) var apps: [SkillApp] = []
    package var selected: String? { didSet { if selected != oldValue { open() } } }
    package var tab = Tab.sessions
    /// The selected app's, newest first, the one it's built in among them.
    package private(set) var sessions: [Session] = []
    package var sessionID: String?
    package private(set) var memory: [TextFile] = []
    package private(set) var interface = ""
    package private(set) var demo = ""
    package private(set) var skill = ""
    package private(set) var rules = ""
    package var notice: String?
    package var adding = false
    /// The sessions whose agent is answering, by id, whichever app they're in.
    package private(set) var live: [String: Live] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    package init(home: YonkaHome = .standard(), agent: AgentProcess? = nil) {
        self.home = home
        self.agent = agent ?? AgentProcess(errors: home.errors)
        attempt { try BuilderSkills.write(to: home.plugin) }
        apps = home.apps()
        selected = apps.first?.id
        // `didSet` doesn't run from an init.
        open()
    }

    // MARK: What's showing

    package var app: SkillApp? { apps.first { $0.id == selected } }
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

    package var preview: Interface.State { Interface.preview(of: app?.info.name ?? "", demo: demo) }

    package var skillFiles: [TextFile] { [TextFile(name: "SKILL.md", text: skill), TextFile(name: "APP.md", text: rules)] }

    /// An interface's own script failed. Said in words the user can hand to the builder.
    package func interfaceFailed(_ error: String) {
        notice = "The interface has an error: \(error)"
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { notice = error.localizedDescription }
    }

    /// Reads the selected app again: what the user changed, or its agent did.
    package func refresh() {
        apps = home.apps()
        guard let app else {
            (sessions, memory, interface, demo, skill, rules) = ([], [], "", "", "", "")
            if selected != nil { selected = apps.first?.id }
            return
        }
        sessions = home.sessions(of: app)
        memory = home.memory(of: app)
        (interface, demo) = (home.text(at: app.interface), home.text(at: app.demo))
        (skill, rules) = (home.text(at: app.skill), home.text(at: app.rules))
        // An app in use always has a session to type into.
        if app.info.stage == .done, session == nil {
            if let newest = useSessions.first { sessionID = newest.id } else { newSession() }
        }
    }

    private func open() {
        (tab, sessionID) = (.sessions, nil)
        refresh()
    }

    // MARK: Apps

    /// A new app from what was pasted: a skill, or a link to one. Its build starts at once.
    package func add(pasted: String) async -> Bool {
        do {
            let link = Skill.source(pasted)
            let text = if let link { try await Skill.fetch(link) } else { pasted }
            let app = try home.create(Skill(text: text))
            apps = home.apps()
            selected = app.id
            if let build = app.info.buildSession { send(Agent.begin, in: build) }
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    package func delete(_ app: SkillApp) {
        for session in home.sessions(of: app) { stop(session.id) }
        attempt { try home.delete(app) }
        if selected == app.id { selected = home.apps().first?.id }
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

    package func save(_ text: String, as name: String, in tab: Tab) {
        guard let app else { return }
        attempt {
            switch (tab, name) {
            case (.memory, _): try home.remember(text, as: name, in: app)
            case (_, "SKILL.md"): try Data(text.utf8).write(to: app.skill, options: .atomic)
            default: try Data(text.utf8).write(to: app.rules, options: .atomic)
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
        tab = .sessions
        if let empty = useSessions.first(where: \.messages.isEmpty) { return sessionID = empty.id }
        let session = Session(kind: .use)
        attempt { try home.save(session, in: app) }
        sessionID = session.id
        refresh()
    }

    package func delete(_ session: Session) {
        guard let app else { return }
        stop(session.id)
        attempt { try home.delete(session, in: app) }
        if sessionID == session.id { sessionID = nil }
        refresh()
    }

    package func stop(_ session: String) {
        tasks[session]?.cancel()
    }

    /// Says it in the session and hears the answer as it comes. The agent may write the app's
    /// files as it goes, so the screens read them again each time a tool finishes.
    package func send(_ text: String, in id: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app, !text.isEmpty, live[id] == nil, let asked = sessions.first(where: { $0.id == id }) else { return }
        let session = asked.adding(Session.Message(role: .user, text: text))
        do { try home.save(session, in: app) } catch { return notice = error.localizedDescription }
        // The turn carries the session as Claude Code has it: `started` says whether to resume.
        let turn = AgentTurn(app: app, session: asked, message: text, memory: memory, skill: skill, rules: rules, plugin: home.plugin)
        live[id] = Live(text: "", status: "")
        refresh()
        tasks[id] = Task { [weak self, agent] in
            var (reply, heard, failure) = (Reply(), false, String?.none)
            do {
                for try await event in agent.events(for: turn) {
                    (reply, heard) = (reply.applying(event), true)
                    self?.live[id] = Live(text: reply.text, status: reply.status)
                    if event == .touched, self?.selected == app.id { self?.refresh() }
                }
            } catch {
                failure = error.localizedDescription
            }
            self?.finished(id, in: app, reply: reply, heard: heard, failure: failure ?? reply.error)
        }
    }

    /// Keeps whatever was said, even from a turn that was stopped or failed part-way.
    private func finished(_ id: String, in app: SkillApp, reply: Reply, heard: Bool, failure: String?) {
        (live[id], tasks[id]) = (nil, nil)
        if let session = home.sessions(of: app).first(where: { $0.id == id }) {
            let answered = reply.text.isEmpty ? session : session.adding(Session.Message(role: .assistant, text: reply.text))
            attempt { try home.save(heard ? answered.begun() : answered, in: app) }
        }
        if let failure { notice = failure }
        if selected == app.id { refresh() }
    }
}
