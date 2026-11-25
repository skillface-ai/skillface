import Foundation

/// Anything Yokan couldn't do, in words the user reads as they are.
package struct YokanError: LocalizedError, Equatable {
    package let message: String
    package init(_ message: String) { self.message = message }
    package var errorDescription: String? { message }
}

/// A SKILL.md: what an app is made from. Its text comes from a link, a file or a paste, so it's
/// checked here before it names a folder.
package struct Skill: Equatable, Sendable {
    /// What the app is called to begin with: the skill's `name` in words, or its heading.
    package let name: String
    package let description: String
    /// The whole file, frontmatter included, as the app keeps it.
    package let text: String

    static let limit = 200_000

    package init(text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw YokanError("That skill is empty") }
        guard text.utf8.count <= Self.limit else { throw YokanError("That's too long to be a skill: over 200 KB") }
        let lines = text.components(separatedBy: .newlines)
        var front: [String: String] = [:]
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<end] {
                guard let colon = line.firstIndex(of: ":"), line.first?.isWhitespace == false else { continue }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                front[String(line[..<colon])] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        let heading = lines.first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        let named = front["name"].map(Self.title)
        guard let name = [named, heading].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw YokanError("That doesn't look like a skill: it has no name and no heading")
        }
        (self.name, self.description, self.text) = (String(name.prefix(60)), front["description"] ?? "", text)
    }

    /// A name as it's written, in words: "socratic-tutor" is "Socratic Tutor".
    package static func title(_ name: String) -> String {
        name.split { "-_".contains($0) }.joined(separator: " ").capitalized
    }

    /// A name as a folder's: lowercase letters, digits and dashes, never empty.
    package static func slug(_ name: String) -> String {
        let words = name.lowercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return words.isEmpty ? "app" : String(words.joined(separator: "-").prefix(48))
    }

    /// Where a pasted link's text is: itself, or for a file's page on GitHub, the file. Nil for
    /// anything that isn't one line of https.
    package static func source(_ pasted: String) -> URL? {
        let pasted = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.contains(where: \.isWhitespace), let url = URL(string: pasted), url.scheme == "https", let host = url.host()
        else { return nil }
        let parts = url.path(percentEncoded: true).split(separator: "/").map(String.init)
        guard host == "github.com", parts.count > 4, parts[2] == "blob" else { return url }
        return URL(string: "https://raw.githubusercontent.com/" + (parts[0...1] + parts[3...]).joined(separator: "/"))
    }

    package static func fetch(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw YokanError("Couldn't read a skill from \(url.host() ?? "that link")") }
        guard data.count <= limit else { throw YokanError("That's too long to be a skill: over 200 KB") }
        return String(decoding: data, as: UTF8.self)
    }

    package static func installed(for provider: AgentProvider) -> [Skill] {
        guard provider == .codex else { return installed() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codex = URL(fileURLWithPath: (Agent.codexHome as NSString).expandingTildeInPath)
        let skills = installed(in: home.appending(path: ".agents/skills")) + installed(in: codex.appending(path: "skills"))
        var names = Set<String>()
        return skills.filter { names.insert($0.name).inserted }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The skills Claude Code already has on this Mac, by name: the nearest place to find one.
    package static func installed(in folder: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/skills")) -> [Skill] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? String(contentsOf: $0.appending(path: "SKILL.md"), encoding: .utf8) }
            .compactMap { try? Skill(text: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
