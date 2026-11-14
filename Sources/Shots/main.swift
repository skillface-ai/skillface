import AppKit
import SwiftUI
import WebKit
import YonkaCore
import YonkaUI

// Dev-only: `swift run shots <dir>`. Draws every screen offscreen on a throwaway home with
// sample data, so a change to the UI can be looked at without an agent or anyone's real apps.
// It can't see the toolbar: check that by running the app.

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/shots")
MainActor.assumeIsolated {
    do { try Flow.run(into: out) } catch {
        print("shots: \(error.localizedDescription)")
        exit(1)
    }
}

@MainActor enum Flow {
    static let skill = """
        ---
        name: socratic-tutor
        description: Structured Socratic tutoring to mastery of a topic.
        ---

        # Socratic Tutor

        Teach by asking questions, one at a time. Track each subskill at levels 0-5.
        """

    static func run(into out: URL) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // `swift run shots <dir> <home>`: a real home's first app instead, as it stands.
        if let real = CommandLine.arguments.dropFirst(2).first {
            let model = AppModel(home: YonkaHome(root: URL(fileURLWithPath: real)))
            draw(model, "app", into: out)
            draw(model, "app-dark", appearance: .darkAqua, into: out)
            model.editInterface()
            return draw(model, "app-preview", into: out)
        }
        let home = YonkaHome(root: FileManager.default.temporaryDirectory.appending(path: "yonka-shots-\(UUID().uuidString)"))
        draw(AppModel(home: home), "1-welcome", into: out)

        // A skill just added: the builder is asking its first question.
        let app = try home.create(Skill(text: skill))
        let build = home.sessions(of: app)[0]
        try home.save(build.adding(.init(role: .user, text: Agent.begin)).adding(.init(role: .assistant, text: """
            I've read the skill. It teaches by questions and tracks a **skill map** with a level for each subskill, which is what the app should remember.

            What do you want in view while you're being taught?

            - [ ] The skill map, always, beside the conversation
            - [ ] Only the question, and the map when I ask
            - [ ] The map on top, the conversation under it
            """)), in: app)
        draw(AppModel(home: home), "2-interview", into: out)
        draw(AppModel(home: home), "2-interview-dark", appearance: .darkAqua, into: out)

        // Built and in use: two sessions, and what it remembers.
        try home.save(app.info.at(.done), of: app)
        try home.remember(#"{ "topic": "Rust lifetimes", "subskills": [{ "name": "Borrowing", "level": 4 }, { "name": "Elision", "level": 2 }] }"#, as: "skill-map.json", in: app)
        try home.remember("- Mixes up `'static` with \"lives forever\".\n- Prefers examples before rules.", as: "notes.md", in: app)
        try home.save(Session(kind: .use, updated: .now.addingTimeInterval(-86_400), messages: [.init(role: .user, text: "Teach me SQL window functions")]), in: app)
        try home.save(Session(kind: .use, messages: [
            .init(role: .user, text: "Teach me Rust lifetimes"),
            .init(role: .assistant, text: "Last time you had **borrowing** at 4 and **elision** at 2, so let's pick up at elision.\n\nWhat does the compiler infer for this signature, and why?\n\n```\nfn first(s: &str) -> &str\n```"),
            .init(role: .user, text: "The output borrows from s?"),
        ]), in: app)
        let model = AppModel(home: home)
        draw(model, "3-sessions", into: out)
        draw(model, "3-sessions-dark", appearance: .darkAqua, into: out)
        model.tab = .memory
        draw(model, "4-memory", into: out)
        model.tab = .skill
        draw(model, "5-skill", into: out)
        model.editInterface()
        draw(model, "6-edit-interface", into: out)
        draw(NewAppSheet(model: model), "7-new-app", size: NSSize(width: 520, height: 520), into: out)
    }

    static func draw(_ model: AppModel, _ name: String, appearance: NSAppearance.Name = .aqua, into folder: URL) {
        draw(RootView(model: model), name, size: NSSize(width: 1200, height: 780), appearance: appearance, into: folder)
    }

    static func draw(_ view: some View, _ name: String, size: NSSize, appearance: NSAppearance.Name = .aqua, into folder: URL) {
        let size = NSRect(origin: .zero, size: size)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = size
        let window = NSWindow(contentRect: size, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let loaded = Date().addingTimeInterval(5)
        while views(WKWebView.self, in: host).contains(where: \.isLoading), Date() < loaded { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.displayIfNeeded()
        defer {
            window.contentView = nil
            window.close()
        }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return print("couldn't draw \(name)") }
        host.cacheDisplay(in: host.bounds, to: rep)
        // A web view draws in a process of its own, where `cacheDisplay` can't see it.
        for web in views(WKWebView.self, in: host) {
            // Offscreen, a page's animations never start, and what they fade in stays invisible.
            var still = false
            web.evaluateJavaScript("document.head.insertAdjacentHTML('beforeend', '<style>* { animation: none !important; transition: none !important }</style>')") { _, _ in still = true }
            while !still { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            var snapshot: NSImage?
            web.takeSnapshot(with: nil) { image, _ in snapshot = image }
            let deadline = Date().addingTimeInterval(3)
            while snapshot == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            snapshot?.draw(in: web.convert(web.bounds, to: nil))
            NSGraphicsContext.restoreGraphicsState()
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name).png"))
    }

    static func views<V: NSView>(_ type: V.Type, in view: NSView) -> [V] {
        (view as? V).map { [$0] } ?? [] + view.subviews.flatMap { views(type, in: $0) }
    }
}
