import Foundation

/// A repository on GitHub, as a link to it says: the whole of it, or one folder in it. An app
/// made from one has all its skills, not one.
package struct Repo: Equatable, Sendable {
    package let owner: String
    package let name: String
    /// The branch or tag the link is to. Nil is the default branch.
    package let ref: String?
    /// The folder the link is to, inside it. Empty is all of it.
    package let path: String

    /// What GitHub will send whole. A repository of skills is text, and far under this.
    static let limit = 50_000_000

    /// From `https://github.com/owner/name`, with or without `/tree/<ref>/<folder>`. Nil for
    /// anything else, a file's page among them: that is one skill, which `Skill.source` reads.
    ///
    /// ponytail: a branch with a slash in its name reads as a branch and a folder. Ask GitHub
    /// for the branches when someone's link is to one.
    package init?(_ pasted: String) {
        let pasted = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pasted.contains(where: \.isWhitespace), let url = URL(string: pasted), url.scheme == "https", url.host() == "github.com"
        else { return nil }
        let parts = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        // Each part goes into a link or names a folder, so each is only ever a plain name.
        let plain = { (part: String) in
            !part.hasPrefix(".") && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
        }
        guard parts.count == 2 || (parts.count >= 4 && parts[2] == "tree"), parts.allSatisfy(plain) else { return nil }
        let name = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard !name.isEmpty else { return nil }
        (owner, self.name) = (parts[0], name)
        (ref, path) = (parts.count >= 4 ? parts[3] : nil, parts.dropFirst(4).joined(separator: "/"))
    }

    /// All of it at that branch, as one file.
    package var archive: URL {
        URL(string: "https://codeload.github.com/\(owner)/\(name)/tar.gz/\(ref ?? "HEAD")")!
    }

    /// What an app made from it is called until the builder names it: "Agent Skills".
    package var title: String {
        let title = Skill.title(path.split(separator: "/").last.map(String.init) ?? name)
        return title.isEmpty ? "Skills" : title
    }

    /// Fetches it and unpacks it in `folder`. Returns the folder the link is to.
    package func download(into folder: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: archive)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw YokanError("Couldn't read \(owner)/\(name) from GitHub. Yokan reads public repositories: check the link")
        }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.limit else { throw YokanError("\(owner)/\(name) is too big to make an app from: over 50 MB") }
        try Self.unpack(file, into: folder)
        let linked = folder.appending(path: path)
        guard (try? linked.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw YokanError("\(owner)/\(name) has no folder \(path)")
        }
        return linked
    }

    /// A `.tar.gz` as GitHub makes them, one folder holding everything, unpacked without that
    /// folder. The Mac's own tar leaves out anything that would land outside `folder`; what it
    /// unpacks is still a stranger's, and `YokanHome.create(from:named:)` takes only plain files.
    ///
    /// ponytail: only the download is measured, not what it unpacks to. Count the bytes as they
    /// come out if someone's repository is ever a bomb.
    static func unpack(_ archive: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", folder.path, "--strip-components", "1"]
        (tar.standardInput, tar.standardOutput, tar.standardError) = (FileHandle.nullDevice, FileHandle.nullDevice, FileHandle.nullDevice)
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw YokanError("Couldn't unpack that repository") }
    }
}
