import Foundation
import Testing

@testable import YokanCore

private func temporaryHome() -> YokanHome {
    YokanHome(root: FileManager.default.temporaryDirectory.appending(path: "yokan-tests-\(UUID().uuidString)"))
}

private let tutor = """
    ---
    name: "socratic-tutor"
    description: "Structured Socratic tutoring: teach me, quiz me."
    ---

    # Socratic Tutor

    Ask ONE question at a time.
    """

struct SkillTests {
    @Test func readsItsNameAndDescription() throws {
        let skill = try Skill(text: tutor)
        #expect(skill.name == "Socratic Tutor")
        #expect(skill.description == "Structured Socratic tutoring: teach me, quiz me.")
        #expect(try Skill(text: "---\nname: code-review\n---\nReview it.").name == "Code Review")
    }

    @Test func refusesWhatIsNotASkill() {
        #expect(throws: YokanError.self) { try Skill(text: "  \n") }
        #expect(throws: YokanError.self) { try Skill(text: "just some words") }
        #expect(throws: YokanError.self) { try Skill(text: "# Big\n" + String(repeating: "x", count: 200_001)) }
    }

    @Test func aLinkToARepositoryIsAllOfIt() throws {
        let repo = try #require(Repo("https://github.com/janestreet/agent_skills"))
        #expect(repo.archive.absoluteString == "https://codeload.github.com/janestreet/agent_skills/tar.gz/HEAD")
        #expect(repo.title == "Agent Skills" && repo.path.isEmpty)
        let folder = try #require(Repo("https://github.com/anthropics/skills.git/tree/main/skills/document-skills/"))
        #expect(folder.archive.absoluteString == "https://codeload.github.com/anthropics/skills/tar.gz/main")
        #expect(folder.path == "skills/document-skills" && folder.title == "Document Skills")
        // One file is one skill, and nothing in a link gets out of its folder.
        #expect(Repo("https://github.com/janestreet/agent_skills/blob/master/socratic-tutor/SKILL.md") == nil)
        #expect(Repo("https://github.com/a/b/tree/main/../../etc") == nil)
        #expect(Repo("https://github.com/a/b/tree/main/.git") == nil)
        #expect(Repo("https://example.com/a/b") == nil)
        #expect(Repo("https://github.com/a") == nil)
        #expect(Repo(tutor) == nil)
    }

    @Test func aRepositoryUnpacksWithoutItsOuterFolder() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "yokan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work.appending(path: "repo-main/tutor"), withIntermediateDirectories: true)
        try Data(tutor.utf8).write(to: work.appending(path: "repo-main/tutor/SKILL.md"))
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", work.appending(path: "repo.tar.gz").path, "-C", work.path, "repo-main"]
        try tar.run()
        tar.waitUntilExit()
        try Repo.unpack(work.appending(path: "repo.tar.gz"), into: work.appending(path: "out"))
        #expect(try String(contentsOf: work.appending(path: "out/tutor/SKILL.md"), encoding: .utf8) == tutor)
        #expect(throws: YokanError.self) { try Repo.unpack(work.appending(path: "repo-main/tutor/SKILL.md"), into: work.appending(path: "bad")) }
    }

    @Test func aNameIsAFolderName() {
        #expect(Skill.slug("Socratic Tutor!") == "socratic-tutor")
        #expect(Skill.slug("../../etc") == "etc")
        #expect(Skill.slug("…") == "app")
    }

    @Test func aGitHubPageIsItsFile() {
        let page = "https://github.com/janestreet/agent_skills/blob/master/socratic-tutor/SKILL.md"
        #expect(Skill.source(page)?.absoluteString == "https://raw.githubusercontent.com/janestreet/agent_skills/master/socratic-tutor/SKILL.md")
        #expect(Skill.source(page + "#socratic-tutor")?.absoluteString == "https://raw.githubusercontent.com/janestreet/agent_skills/master/socratic-tutor/SKILL.md")
        #expect(Skill.source("https://example.com/SKILL.md")?.host() == "example.com")
        #expect(Skill.source("http://example.com/SKILL.md") == nil)
        #expect(Skill.source(tutor) == nil)
    }
}

struct HomeTests {
    @Test func theHomeFromBeforeTheRenameMovesOnce() throws {
        let files = FileManager.default
        let work = files.temporaryDirectory.appending(path: "yokan-tests-\(UUID().uuidString)")
        let (old, new) = (work.appending(path: "Yonka"), work.appending(path: "Yokan"))
        try YokanHome.adopt(old, as: new)
        #expect(!files.fileExists(atPath: new.path))

        let app = try YokanHome(root: old).create(Skill(text: tutor))
        try YokanHome.adopt(old, as: new)
        #expect(!files.fileExists(atPath: old.path))
        #expect(YokanHome(root: new).apps().map(\.id) == [app.id])

        // A new home that's there is never written over.
        _ = try YokanHome(root: old).create(Skill(text: tutor))
        try YokanHome.adopt(old, as: new)
        #expect(files.fileExists(atPath: old.path))
        #expect(YokanHome(root: new).apps().count == 1)
    }

    @Test func anAppIsAFolderThatStartsReadyToBuild() throws {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        #expect(app.id == "socratic-tutor")
        #expect(home.apps().map(\.id) == [app.id])
        #expect(app.info.stage == .interview)
        #expect(home.text(at: app.skill).hasPrefix("---"))
        #expect(home.text(at: app.interface) == Interface.starter)
        #expect(home.memory(of: app).isEmpty)
        #expect(home.sessions(of: app).map(\.id) == [app.info.buildSession])
        #expect(try home.create(Skill(text: tutor)).id == "socratic-tutor-2")
    }

    @Test func whatTheBuilderWritesToAppJSONNeverLosesTheApp() throws {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        try Data(#"{ "name": "Tutor", "stage": "polishing", "symbol": 7 }"#.utf8).write(to: app.folder.appending(path: "app.json"))
        let read = try #require(home.apps().first)
        #expect(read.info == SkillApp.Info(name: "Tutor", symbol: "sparkles", stage: .interview, buildSession: nil))
    }

    @Test func memoryStaysInItsFolder() throws {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        try home.remember("{}", as: "skill-map.json", in: app)
        try home.remember("likes examples", as: "notes/user.md", in: app)
        #expect(home.memory(of: app).map(\.name) == ["notes/user.md", "skill-map.json"])
        for name in ["../SKILL.md", "/etc/hosts", ".hidden", "a//b", ""] {
            #expect(throws: YokanError.self) { try home.remember("x", as: name, in: app) }
        }
        #expect(home.text(at: app.skill).hasPrefix("---"))
    }

    @Test func theVersionChosenBecomesTheInterface() throws {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        #expect(home.designs(of: app).isEmpty)
        try FileManager.default.createDirectory(at: app.designs, withIntermediateDirectories: true)
        for id in ["B", "A", "C"] { try Data("<p>\(id)</p>".utf8).write(to: app.designs.appending(path: "\(id).html")) }
        try Data("".utf8).write(to: app.designs.appending(path: "D.html"))
        // The builder writes the index, so one that's half there still names what it can.
        try Data(#"[{"id":"A","name":"Focus","idea":"One question."},{"id":"B","name":7},"junk"]"#.utf8).write(to: app.designs.appending(path: "index.json"))
        let designs = home.designs(of: app)
        #expect(designs.map(\.id) == ["A", "B", "C"])
        #expect(designs.map(\.name) == ["Focus", "B", "C"])
        #expect(designs[0].idea == "One question.")
        try home.use(designs[1], in: app)
        #expect(home.text(at: app.interface) == "<p>B</p>")
        #expect(Agent.chose(designs[0]) == "Use version A, Focus.")
    }

    @Test func sketchesAreTheOpenQuestionsAnswersInOrder() throws {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        #expect(home.sketches(of: app).isEmpty)
        try FileManager.default.createDirectory(at: app.sketches, withIntermediateDirectories: true)
        // 4 is left over from a question with more answers: a gap ends the run.
        for name in ["2", "1", "4"] { try Data("<p>\(name)</p>".utf8).write(to: app.sketches.appending(path: "\(name).html")) }
        #expect(home.sketches(of: app) == ["<p>1</p>", "<p>2</p>"])
        home.clearSketches(of: app)
        #expect(home.sketches(of: app).isEmpty)
    }

    @Test func appsStayWhereTheUserPutThem() throws {
        let home = temporaryHome()
        let made = try ["Bravo", "Alpha", "Charlie"].map { try home.create(Skill(text: "# \($0)\n\nDo it.")) }
        #expect(YokanHome.arranged(home.apps(), by: home.arrangement()).map(\.info.name) == ["Alpha", "Bravo", "Charlie"])
        let ids = home.apps().map(\.id)
        #expect(YokanHome.moving(ids[2], to: ids[0], in: ids) == [ids[2], ids[0], ids[1]])
        #expect(YokanHome.moving(ids[0], to: ids[2], in: ids) == [ids[1], ids[2], ids[0]])
        #expect(YokanHome.moving("gone", to: ids[0], in: ids) == ids)
        // One that's gone is passed over, and one made since comes after.
        try home.arrange([ids[2], "gone", ids[0]])
        #expect(YokanHome.arranged(home.apps(), by: home.arrangement()).map(\.info.name) == ["Charlie", "Alpha", "Bravo"])

        // A new name is one line, and the folder is the one it was made with.
        try home.save(made[0].info.named("  Bravo\nTwo  "), of: made[0])
        let renamed = try #require(home.apps().first { $0.id == made[0].id })
        #expect(renamed.info.name == "Bravo Two" && renamed.info.stage == made[0].info.stage)
        #expect(renamed.info.named(" \n ") == renamed.info)
        #expect(renamed.info.named(String(repeating: "a", count: 200)).name.count == 60)
    }

    @Test func aFolderOfSkillsBecomesOneAppThatOnlyReadsThem() throws {
        let home = temporaryHome()
        let files = FileManager.default
        let repo = files.temporaryDirectory.appending(path: "yokan-tests-\(UUID().uuidString)/agent_skills")
        for folder in ["plan", "review/deep", ".git"] { try files.createDirectory(at: repo.appending(path: folder), withIntermediateDirectories: true) }
        try Data("# Agent skills\n\nPlan, then review.".utf8).write(to: repo.appending(path: "README.md"))
        try Data("---\nname: plan\ndescription: Write the plan.\n---\nPlan it.".utf8).write(to: repo.appending(path: "plan/SKILL.md"))
        try Data("---\nname: review\ndescription: Review what plan wrote.\n---\nSee checklist.md.".utf8).write(to: repo.appending(path: "review/deep/SKILL.md"))
        try Data("- Is it right?".utf8).write(to: repo.appending(path: "review/deep/checklist.md"))
        // What a stranger's folder may also hold: something hidden, a way out, something huge.
        try Data("secret".utf8).write(to: repo.appending(path: ".git/config"))
        try files.createSymbolicLink(at: repo.appending(path: "review/hosts"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try Data(count: YokanHome.sourceFileLimit + 1).write(to: repo.appending(path: "big.bin"))

        let app = try home.create(from: repo, named: Skill.title("agent_skills"))
        #expect(app.info.name == "Agent Skills" && app.id == "agent-skills")
        #expect(home.skills(of: app).map(\.path) == ["plan/SKILL.md", "review/deep/SKILL.md"])
        #expect(home.skills(of: app).map(\.skill.name) == ["Plan", "Review"])
        #expect(home.text(at: app.source.appending(path: "review/deep/checklist.md")) == "- Is it right?")
        for left in [".git/config", "review/hosts", "big.bin"] { #expect(!files.fileExists(atPath: app.source.appending(path: left).path)) }
        // Nothing there can be changed or added to, by anyone.
        #expect(throws: (any Error).self) { try Data("x".utf8).write(to: app.source.appending(path: "plan/SKILL.md")) }
        #expect(throws: (any Error).self) { try Data("x".utf8).write(to: app.source.appending(path: "plan/new.md")) }
        #expect(throws: (any Error).self) { try Data("x".utf8).write(to: app.source.appending(path: "new.md")) }

        // Its agent is told which skills there are and where, and may read there.
        let use = AgentTurn(app: app, session: Session(kind: .use), message: "Go", memory: [], skill: "", skills: home.skills(of: app), rules: "Plan first.", plugin: home.plugin)
        let arguments = Agent.arguments(for: use)
        #expect(arguments[arguments.firstIndex(of: "--add-dir")! + 1] == app.source.path)
        #expect(use.folder == app.memory)
        let told = arguments[arguments.firstIndex(of: "--append-system-prompt")! + 1]
        for part in ["- Review (review/deep/SKILL.md): Review what plan wrote.", app.source.path, "Plan first."] { #expect(told.contains(part)) }
        // The builder is already in the folder that holds them, and starts by reading it all.
        let build = AgentTurn(app: app, session: Session(kind: .build), message: Agent.beginAll, memory: [], skill: "", skills: home.skills(of: app), rules: "", plugin: home.plugin)
        #expect(!Agent.arguments(for: build).contains("--add-dir"))
        #expect(Agent.builder(for: build).contains("before step 1, load yokan:explore"))

        // It runs commands only once the user says so, which is kept where no agent can write,
        // and then only its own agent, in the sandbox, with `source/` still nobody's to change.
        #expect(!arguments.contains("--settings") && !arguments[arguments.firstIndex(of: "--tools")! + 1].contains("Bash"))
        #expect(told.contains("Use the Terminal"))
        #expect(!home.runs(app))
        try home.allow(app, toRun: true)
        #expect(home.runs(app) && !files.fileExists(atPath: app.folder.appending(path: "terminal.json").path))
        let runs = Agent.arguments(for: AgentTurn(app: app, session: Session(kind: .use), message: "Go", memory: [], skill: "", skills: home.skills(of: app), terminal: home.runs(app), rules: "", plugin: home.plugin))
        #expect(runs[runs.firstIndex(of: "--tools")! + 1].hasSuffix(",Bash") && runs.contains(app.work.path))
        let settings = try #require(JSONSerialization.jsonObject(with: Data(runs[runs.firstIndex(of: "--settings")! + 1].utf8)) as? [String: [String: Any]])
        #expect(settings["sandbox"]?["enabled"] as? Bool == true && settings["sandbox"]?["allowUnsandboxedCommands"] as? Bool == false)
        #expect((settings["sandbox"]?["filesystem"] as? [String: [String]])?["denyWrite"] == [app.source.path])
        let building = Agent.arguments(for: AgentTurn(app: app, session: Session(kind: .build), message: "Go", memory: [], skill: "", terminal: true, rules: "", plugin: home.plugin))
        #expect(!building.contains("--settings") && !building[building.firstIndex(of: "--tools")! + 1].contains("Bash"))
        try home.allow(app, toRun: false)
        #expect(!home.runs(app))

        // A folder with no skill in it is no app, and leaves nothing behind.
        try files.removeItem(at: repo.appending(path: "plan"))
        try files.removeItem(at: repo.appending(path: "review"))
        #expect(throws: YokanError.self) { try home.create(from: repo, named: "Nothing") }
        #expect(home.apps().map(\.id) == ["agent-skills"])
        // And an app made from one skill has none of this.
        let one = try home.create(Skill(text: tutor))
        #expect(home.skills(of: one).isEmpty)
    }

    @Test func sessionsComeBackNewestFirst() throws {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        let old = Session(kind: .use, updated: .now.addingTimeInterval(-60), messages: [.init(role: .user, text: "Teach me SQL\nplease")])
        let new = Session(kind: .use).adding(.init(role: .user, text: String(repeating: "long ", count: 30))).begun()
        try home.save(old, in: app)
        try home.save(new, in: app)
        let read = home.sessions(of: app).filter { $0.kind == .use }
        #expect(read.map(\.id) == [new.id, old.id])
        #expect(read[0].started && !read[1].started)
        #expect(read[1].title == "Teach me SQL")
        #expect(read[0].title.count == 61)
        #expect(Session(kind: .use).title == "New Session")
        #expect(throws: YokanError.self) { try home.save(Session(id: "../x", kind: .use), in: app) }
    }
}

struct AgentTests {
    private func turn(_ kind: Session.Kind, started: Bool = false, memory: [TextFile] = []) throws -> AgentTurn {
        let home = temporaryHome()
        let app = try home.create(Skill(text: tutor))
        let session = started ? Session(kind: kind).begun() : Session(kind: kind)
        return AgentTurn(app: app, session: session, message: "Teach me Rust", memory: memory, skill: tutor, rules: "Keep skill-map.json.", plugin: home.plugin)
    }

    @Test func anAppsAgentIsContainedToItsMemory() throws {
        let turn = try turn(.use, memory: [TextFile(name: "skill-map.json", text: #"{"level":3}"#)])
        let arguments = Agent.arguments(for: turn)
        #expect(turn.folder == turn.app.memory)
        #expect(arguments.contains("--restricted"))
        #expect(arguments[arguments.firstIndex(of: "--tools")! + 1] == "Read,Write,Edit,Glob,Grep")
        #expect(!arguments.contains("--plugin-dir"))
        #expect(arguments.suffix(2) == ["--", "Teach me Rust"])
        #expect(arguments.contains("--session-id") && !arguments.contains("--resume"))
        // It never starts empty: the skill, the app's rules and its memory are all there.
        let told = arguments[arguments.firstIndex(of: "--append-system-prompt")! + 1]
        for part in ["Ask ONE question at a time.", "Keep skill-map.json.", "### skill-map.json", #"{"level":3}"#] { #expect(told.contains(part)) }
    }

    @Test func aLaterMessageResumesTheSession() throws {
        let turn = try turn(.use, started: true)
        let arguments = Agent.arguments(for: turn)
        #expect(arguments[arguments.firstIndex(of: "--resume")! + 1] == turn.session.id)
        #expect(!arguments.contains("--session-id"))
    }

    @Test func theBuilderWorksInTheAppsFolderWithItsSkills() throws {
        let turn = try turn(.build)
        let arguments = Agent.arguments(for: turn)
        #expect(turn.folder == turn.app.folder)
        #expect(arguments[arguments.firstIndex(of: "--tools")! + 1].hasSuffix(",Skill"))
        #expect(arguments[arguments.firstIndex(of: "--plugin-dir")! + 1] == turn.plugin.path)
        try BuilderSkills.write(to: turn.plugin)
        let told = arguments[arguments.firstIndex(of: "--append-system-prompt")! + 1]
        for skill in BuilderSkills.all {
            #expect(told.contains("yokan:\(skill.name)"))
            let file = try String(contentsOf: turn.plugin.appending(path: "skills/\(skill.name)/SKILL.md"), encoding: .utf8)
            #expect(file.hasPrefix("---\nname: \(skill.name)\ndescription: "))
            #expect(!skill.description.contains("\n"))
        }
    }

    @Test func theStreamBecomesAReply() {
        let lines = [
            #"{"type":"system","subtype":"init"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hm"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Let me "}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"note that."}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Let me note that."}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/x/memory/skill-map.json"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"What is a borrow?"}}}"#,
        ]
        let events = lines.flatMap(AgentStream.events)
        #expect(events == [
            .delta("Let me "), .delta("note that."), .said("Let me note that."), .doing("Writing skill-map.json"), .touched, .delta("What is a borrow?"),
        ])
        let replies = events.reduce(into: [Reply()]) { $0.append($0[$0.count - 1].applying($1)) }
        #expect(replies[2].text == "Let me note that.")
        #expect(replies[4].status == "Writing skill-map.json")
        #expect(replies.last?.text == "Let me note that.\n\nWhat is a borrow?")
        #expect(AgentStream.events(from: #"{"type":"result","is_error":true,"result":"Out of credit"}"#) == [.done(error: "Out of credit")])
        #expect(AgentStream.events(from: #"{"type":"result","is_error":false,"result":"hi"}"#) == [.done(error: nil)])
        #expect(AgentStream.events(from: "not json").isEmpty)
        // A failed sign-in is the turn's error, never something the agent said.
        let failed = [
            #"{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"Failed to authenticate: OAuth session expired and could not be refreshed"}]}}"#,
            #"{"type":"result","is_error":true,"result":"Failed to authenticate: OAuth session expired and could not be refreshed"}"#,
        ].flatMap(AgentStream.events)
        #expect(failed == [.done(error: "Claude Code is signed out. Run claude in Terminal, sign in with /login, then try again.")])
        #expect(failed.reduce(Reply()) { $0.applying($1) }.text.isEmpty)
        let asked = Session(kind: .build).adding(.init(role: .user, text: "Build it"))
        #expect(asked.unanswered == "Build it" && asked.retracting().messages.isEmpty)
        #expect(asked.adding(.init(role: .assistant, text: "Done")).unanswered == nil)
    }

    /// Through a stand-in for Claude Code: these tests never spend anyone's plan.
    @Test func aTurnRunsClaudeCodeInItsFolder() async throws {
        let turn = try turn(.use)
        let script = turn.app.folder.appending(path: "claude")
        try Data("""
            #!/bin/sh
            pwd > here.txt
            printf '%s\\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}' '{"type":"result","is_error":false}'
            """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let agent = AgentProcess(errors: turn.app.folder.appending(path: "errors.log")) { (script, "/usr/bin:/bin") }
        var events: [AgentEvent] = []
        for try await event in agent.events(for: turn) { events.append(event) }
        #expect(events == [.said("Hello"), .done(error: nil)])
        let here = try String(contentsOf: turn.app.memory.appending(path: "here.txt"), encoding: .utf8)
        #expect(here.trimmingCharacters(in: .newlines).hasSuffix("/memory"))
    }

    @Test func aTurnThatDiesSaysWhy() async throws {
        let turn = try turn(.use)
        let script = turn.app.folder.appending(path: "claude")
        try Data("#!/bin/sh\necho 'Disk is full' >&2\nexit 1\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let agent = AgentProcess(errors: turn.app.folder.appending(path: "errors.log")) { (script, "/usr/bin:/bin") }
        await #expect(throws: YokanError("Disk is full")) {
            for try await _ in agent.events(for: turn) {}
        }
    }
}

struct InterfaceTests {
    @Test func aPageLoadsNothing() {
        let page = Interface.page(Interface.starter)
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(page.contains("default-src 'none'") && page.contains("form-action 'none'"))
        #expect(!Interface.starter.contains("http"))
    }

    @Test func aPageBuiltForYonkaStillRuns() {
        #expect(Interface.bridge.contains("window.yonka = window.yokan"))
        #expect(!Interface.starter.contains("yonka"))
    }

    @Test func stateIsWhatThePageIsHanded() throws {
        let state = Interface.State(
            app: "Tutor", session: "Rust", messages: [.init(role: .assistant, text: "Why?\u{2028}</script>")],
            memory: [TextFile(name: "skill-map.json", text: "{}")], busy: true, status: "Writing")
        let object = try #require(JSONSerialization.jsonObject(with: Data(state.json.utf8)) as? [String: Any])
        #expect((object["memory"] as? [String: String]) == ["skill-map.json": "{}"])
        #expect((object["messages"] as? [[String: String]])?.first?["role"] == "assistant")
        #expect(object["busy"] as? Bool == true)
        #expect(object["preview"] as? Bool == false)
    }

    @Test func aPreviewIsTheDemoHoweverItIsWritten() {
        let demo = #"{ "memory": { "skill-map.json": { "level": 3 }, "notes.md": "likes examples", "bad": 4 }, "messages": [{ "role": "user", "text": "hi" }, { "role": "robot", "text": "no" }] }"#
        let state = Interface.preview(of: "Tutor", demo: demo)
        #expect(state.preview)
        #expect(state.memory.map(\.name) == ["notes.md", "skill-map.json"])
        #expect(state.memory[1].text.contains("\"level\" : 3"))
        #expect(state.messages == [.init(role: .user, text: "hi")])
        #expect(Interface.preview(of: "Tutor", demo: "not json").messages.isEmpty)
    }

    @Test func aQuestionsChoicesAreItsClosingChecklist() {
        let asked = Choices.split("What stays in view?\n\n- [ ] The map, always\n- [ ] Only the question\n")
        #expect(asked.body == "What stays in view?")
        #expect(asked.choices == ["The map, always", "Only the question"])
        #expect(Choices.split("- [ ] not last\nBecause this is.").choices.isEmpty)
        #expect(Choices.split("No choices.").body == "No choices.")
    }
}
