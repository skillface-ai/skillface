import Foundation

/// Where everything lives: `~/Library/Application Support/Yonka`, or `$YONKA_HOME`. Every read
/// and write of an app's folder is here.
package struct YonkaHome: Sendable {
    package let root: URL

    package init(root: URL) { self.root = root }

    package static func standard() -> YonkaHome {
        if let path = ProcessInfo.processInfo.environment["YONKA_HOME"] { return YonkaHome(root: URL(fileURLWithPath: path)) }
        return YonkaHome(root: URL.applicationSupportDirectory.appending(path: "Yonka"))
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
        let slug = Skill.slug(skill.name)
        let taken = Set(apps().map(\.id))
        let id = ([slug] + (2...999).map { "\(slug)-\($0)" }).first { !taken.contains($0) } ?? UUID().uuidString.lowercased()
        let build = Session(kind: .build)
        let app = SkillApp(id: id, folder: appsFolder.appending(path: id), info: SkillApp.Info(name: skill.name, buildSession: build.id))
        try Self.files.createDirectory(at: app.memory, withIntermediateDirectories: true)
        try Self.files.createDirectory(at: app.sessions, withIntermediateDirectories: true)
        try Data(skill.text.utf8).write(to: app.skill)
        try Data(Interface.starter.utf8).write(to: app.interface)
        try Data(Interface.starterDemo.utf8).write(to: app.demo)
        try save(app.info, of: app)
        try save(build, in: app)
        return app
    }

    package func save(_ info: SkillApp.Info, of app: SkillApp) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(info).write(to: app.folder.appending(path: "app.json"), options: .atomic)
    }

    /// To the Trash, memory and sessions with it, so it can be put back.
    package func delete(_ app: SkillApp) throws {
        try Self.files.trashItem(at: app.folder, resultingItemURL: nil)
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
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else { throw YonkaError("“\(name)” isn't a name memory can have") }
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
        guard UUID(uuidString: session.id) != nil else { throw YonkaError("That session's id isn't one") }
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
