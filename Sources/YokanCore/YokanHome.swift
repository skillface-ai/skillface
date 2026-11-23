import Foundation

/// Where everything lives: `~/Library/Application Support/Yokan`, or `$YOKAN_HOME`. Every read
/// and write of an app's folder is here.
///
/// Yokan was called Yonka, and people have apps from then: the old home moves to the new name
/// once (`adoptFormer`), and `$YONKA_HOME` still says where a home is.
package struct YokanHome: Sendable {
    package let root: URL

    package init(root: URL) { self.root = root }

    package static func standard() -> YokanHome {
        if let path = given { return YokanHome(root: URL(fileURLWithPath: path)) }
        return YokanHome(root: URL.applicationSupportDirectory.appending(path: "Yokan"))
    }

    private static var given: String? {
        let environment = ProcessInfo.processInfo.environment
        return environment["YOKAN_HOME"] ?? environment["YONKA_HOME"]
    }

    /// The standard home under its old name, moved to its new one. A home the environment names
    /// is wherever it was put, so it stays.
    package static func adoptFormer() throws {
        guard given == nil else { return }
        try adopt(URL.applicationSupportDirectory.appending(path: "Yonka"), as: standard().root)
    }

    /// Moves a home to a new place, once: only while the new place is empty, so a home that's
    /// been used since is never written over.
    static func adopt(_ old: URL, as new: URL) throws {
        guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { return }
        do { try files.moveItem(at: old, to: new) } catch {
            throw YokanError("Couldn't bring your apps over from Yonka. They're still in \(old.path): \(error.localizedDescription)")
        }
    }

    private var appsFolder: URL { root.appending(path: "Apps") }
    /// The builder's skills, as the Claude Code plugin a build runs with.
    package var plugin: URL { root.appending(path: "Builder/plugin") }
    /// What Claude Code last said on stderr, for when a turn fails.
    package var errors: URL { root.appending(path: "agent-errors.log") }

    private static var files: FileManager { .default }
    /// ponytail: memory is text the agent reads whole at a session's start. A file past this is
    /// skipped; page it once an app keeps more than that.
    static let memoryLimit = 256_000

    // MARK: Apps

    package func apps() -> [SkillApp] {
        let folders = (try? Self.files.contentsOfDirectory(at: appsFolder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "app.json")),
                  let info = try? JSONDecoder().decode(SkillApp.Info.self, from: data)
            else { return nil }
            return SkillApp(id: folder.lastPathComponent, folder: folder, info: info)
        }
        .sorted { $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending }
    }

    /// When an app was last used: when a session of it was last written. Its sessions folder
    /// changes each time one is, since every save replaces the file.
    package func lastUsed(_ app: SkillApp) -> Date {
        (try? app.sessions.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// A new app from a skill: the starter interface, no memory, and the session it'll be built in.
    package func create(_ skill: Skill) throws -> SkillApp {
        let app = try create(named: skill.name)
        try Data(skill.text.utf8).write(to: app.skill)
        return app
    }

    /// A new app with everything but what it's made from.
    private func create(named name: String) throws -> SkillApp {
        let slug = Skill.slug(name)
        let taken = Set(apps().map(\.id))
        let id = ([slug] + (2...999).map { "\(slug)-\($0)" }).first { !taken.contains($0) } ?? UUID().uuidString.lowercased()
        let build = Session(kind: .build)
        let app = SkillApp(id: id, folder: appsFolder.appending(path: id), info: SkillApp.Info(name: name, buildSession: build.id))
        try Self.files.createDirectory(at: app.memory, withIntermediateDirectories: true)
        try Self.files.createDirectory(at: app.sessions, withIntermediateDirectories: true)
        try Data(Interface.starter.utf8).write(to: app.interface)
        try Data(Interface.starterDemo.utf8).write(to: app.demo)
        try save(app.info, of: app)
        try save(build, in: app)
        return app
    }

    // MARK: A repository of skills

    /// ponytail: a file past this is left out, and a folder past these isn't taken at all.
    /// Raise them when a real repository of skills is turned away.
    static let sourceFileLimit = 1_000_000
    static let sourceLimit = (files: 5_000, bytes: 50_000_000)

    /// A new app from a folder of skills, a repository unpacked or a folder dropped: all of it
    /// copied to the app's `source/`, for the builder to read and its agent after. The folder is
    /// a stranger's, so only its plain files come: nothing hidden, no link to anywhere else.
    /// Then it's made read-only, files and folders both, which is what keeps an agent that can
    /// read it from ever changing it.
    package func create(from folder: URL, named name: String) throws -> SkillApp {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let found = Self.files.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let base = folder.standardizedFileURL.path + "/"
        let files = (found?.allObjects as? [URL] ?? []).compactMap { url -> (path: String, url: URL, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, size <= Self.sourceFileLimit
            else { return nil }
            return (String(url.standardizedFileURL.path.dropFirst(base.count)), url, size)
        }
        guard files.contains(where: { $0.url.lastPathComponent == "SKILL.md" }) else {
            throw YokanError("There are no skills in there: nothing in it is a SKILL.md")
        }
        guard files.count <= Self.sourceLimit.files, files.reduce(0, { $0 + $1.size }) <= Self.sourceLimit.bytes else {
            throw YokanError("That's too big to make an app from: over 5,000 files or 50 MB")
        }
        let app = try create(named: name)
        do {
            for file in files {
                let copy = app.source.appending(path: file.path)
                try Self.files.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Self.files.copyItem(at: file.url, to: copy)
            }
            guard !skills(of: app).isEmpty else { throw YokanError("There are no skills in there: no SKILL.md in it reads as one") }
            let copied = Self.files.enumerator(at: app.source, includingPropertiesForKeys: [.isDirectoryKey])?.allObjects as? [URL] ?? []
            for url in copied + [app.source] {
                let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                try Self.files.setAttributes([.posixPermissions: folder ? 0o555 : 0o444], ofItemAtPath: url.path)
            }
        } catch {
            try? Self.files.removeItem(at: app.folder)
            throw error
        }
        return app
    }

    /// The skills of an app made from several, by where each is in `source/`. Empty for an app
    /// made from one.
    package func skills(of app: SkillApp) -> [SourceSkill] {
        let found = Self.files.enumerator(at: app.source, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
        let base = app.source.standardizedFileURL.path + "/"
        return found.filter { $0.lastPathComponent == "SKILL.md" }.compactMap { url -> SourceSkill? in
            guard let text = try? String(contentsOf: url, encoding: .utf8), let skill = try? Skill(text: text) else { return nil }
            return SourceSkill(path: String(url.standardizedFileURL.path.dropFirst(base.count)), skill: skill)
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    package func save(_ info: SkillApp.Info, of app: SkillApp) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: app.folder.appending(path: "app.json"), options: .atomic)
    }

    /// To the Trash, memory and sessions with it, so it can be put back.
    package func delete(_ app: SkillApp) throws {
        try Self.files.trashItem(at: app.folder, resultingItemURL: nil)
        // An app made later under the same name starts without what this one was allowed.
        try allow(app, toRun: false)
    }

    // MARK: Who may run commands

    /// The apps the user let run commands, by id. Beside the apps and not inside one: an app's
    /// folder is its builder's to write, and a skill is untrusted, so this is only the user's to say.
    private var runnersFile: URL { root.appending(path: "terminal.json") }

    package func runs(_ app: SkillApp) -> Bool {
        ((try? JSONDecoder().decode([String].self, from: Data(contentsOf: runnersFile))) ?? []).contains(app.id)
    }

    package func allow(_ app: SkillApp, toRun: Bool) throws {
        let others = ((try? JSONDecoder().decode([String].self, from: Data(contentsOf: runnersFile))) ?? []).filter { $0 != app.id }
        try JSONEncoder().encode(others + (toRun ? [app.id] : [])).write(to: runnersFile, options: .atomic)
    }

    // MARK: The user's arrangement

    /// All Apps as the user arranged it: the apps' ids, in order.
    private var arrangementFile: URL { root.appending(path: "arrangement.json") }

    /// Empty until they've moved one. Only ever matched against the apps there are.
    package func arrangement() -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(contentsOf: arrangementFile))) ?? []
    }

    package func arrange(_ ids: [String]) throws {
        try JSONEncoder().encode(ids).write(to: arrangementFile, options: .atomic)
    }

    /// The apps in the user's order. One made since they arranged them comes after, by name.
    package static func arranged(_ apps: [SkillApp], by ids: [String]) -> [SkillApp] {
        let place = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = apps.enumerated().map { (app: $1, at: place[$1.id] ?? ids.count + $0) }
        return placed.sorted { $0.at < $1.at }.map(\.app)
    }

    /// `ids` with one in another's place, and those between making way.
    package static func moving(_ id: String, to target: String, in ids: [String]) -> [String] {
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return ids }
        let rest = ids.filter { $0 != id }
        return Array(rest[..<to]) + [id] + rest[to...]
    }

    // MARK: Designs

    /// The versions the builder drew, in order. Each is an `.html` in `designs/`; `index.json`
    /// names them, and whatever it leaves out or gets wrong, the file's own name stands in.
    package func designs(of app: SkillApp) -> [Design] {
        let read = try? JSONSerialization.jsonObject(with: Data(contentsOf: app.designs.appending(path: "index.json")))
        let index = (read as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let found = (try? Self.files.contentsOfDirectory(at: app.designs, includingPropertiesForKeys: nil)) ?? []
        return found.filter { $0.pathExtension == "html" }.compactMap { file -> Design? in
            let id = file.deletingPathExtension().lastPathComponent
            guard let html = try? String(contentsOf: file, encoding: .utf8), !html.isEmpty else { return nil }
            let about = index.first { $0["id"] as? String == id }
            return Design(id: id, name: about?["name"] as? String ?? id, idea: about?["idea"] as? String ?? "", html: html)
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// The version the user chose becomes the app's interface. The others stay, to go back to.
    package func use(_ design: Design, in app: SkillApp) throws {
        try Data(design.html.utf8).write(to: app.interface, options: .atomic)
    }

    /// A rough picture of each answer to the builder's question, in the answers' order: `1.html`,
    /// `2.html`… as far as they run without a gap.
    package func sketches(of app: SkillApp) -> [String] {
        (1...9).lazy.map { try? String(contentsOf: app.sketches.appending(path: "\($0).html"), encoding: .utf8) }
            .prefix { $0?.isEmpty == false }.compactMap { $0 }
    }

    /// Once a question is answered its sketches are gone, so the next question never shows them.
    package func clearSketches(of app: SkillApp) {
        try? Self.files.removeItem(at: app.sketches)
    }

    // MARK: Files

    package func text(at url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Every text file in the app's memory, by its path there.
    package func memory(of app: SkillApp) -> [TextFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let found = Self.files.enumerator(at: app.memory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let base = app.memory.standardizedFileURL.path + "/"
        return (found?.allObjects as? [URL] ?? []).compactMap { url -> TextFile? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  (values.fileSize ?? 0) <= Self.memoryLimit, let text = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }
            return TextFile(name: String(url.standardizedFileURL.path.dropFirst(base.count)), text: text)
        }
        .sorted { $0.name < $1.name }
    }

    /// A memory's file, from a name that can only be inside the app's memory.
    private func memoryFile(_ name: String, of app: SkillApp) throws -> URL {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else { throw YokanError("“\(name)” isn't a name memory can have") }
        return app.memory.appending(path: name)
    }

    package func remember(_ text: String, as name: String, in app: SkillApp) throws {
        let file = try memoryFile(name, of: app)
        try Self.files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .atomic)
    }

    package func forget(_ name: String, in app: SkillApp) throws {
        try Self.files.trashItem(at: try memoryFile(name, of: app), resultingItemURL: nil)
    }

    // MARK: Sessions

    private static func coder<Coder>(_ make: () -> Coder, _ set: (Coder) -> Void) -> Coder {
        let coder = make()
        set(coder)
        return coder
    }

    /// Newest first.
    package func sessions(of app: SkillApp) -> [Session] {
        let decoder = Self.coder(JSONDecoder.init) { $0.dateDecodingStrategy = .iso8601 }
        let found = (try? Self.files.contentsOfDirectory(at: app.sessions, includingPropertiesForKeys: nil)) ?? []
        return found.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Session.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }

    private func file(of session: Session, in app: SkillApp) throws -> URL {
        // The id names a file and is handed to Claude Code as a flag: only ever a UUID.
        guard UUID(uuidString: session.id) != nil else { throw YokanError("That session's id isn't one") }
        return app.sessions.appending(path: "\(session.id).json")
    }

    package func save(_ session: Session, in app: SkillApp) throws {
        let encoder = Self.coder(JSONEncoder.init) {
            $0.dateEncodingStrategy = .iso8601
            $0.outputFormatting = [.prettyPrinted]
        }
        try encoder.encode(session).write(to: try file(of: session, in: app), options: .atomic)
    }

    package func delete(_ session: Session, in app: SkillApp) throws {
        try Self.files.trashItem(at: try file(of: session, in: app), resultingItemURL: nil)
    }
}
