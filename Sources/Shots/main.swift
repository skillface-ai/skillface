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
            draw(model, "home", into: out)
            model.selected = model.recent.first?.id
            draw(model, "app", into: out)
            // Each answer's sketch, where a question is open.
            for index in model.sketches.indices.dropFirst() {
                model.sketched = index
                draw(model, "app-sketch-\(index + 1)", into: out)
            }
            return
        }
        let home = YonkaHome(root: FileManager.default.temporaryDirectory.appending(path: "yonka-shots-\(UUID().uuidString)"))
        draw(AppModel(home: home), "1-home-empty", into: out)

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
        try FileManager.default.createDirectory(at: app.sketches, withIntermediateDirectories: true)
        let sketch = { (map: String) in """
            <style>body { display: flex; height: 100%; padding: 28px; gap: 16px } .b { background: var(--surface); border-radius: var(--radius); padding: 14px; font: 11px var(--mono); color: var(--secondary) } .q { flex: 1; display: flex; flex-direction: column; gap: 16px } h2 { font-size: 26px; margin: 0 } .hot { outline: 1.5px solid var(--accent) }</style>
            <div class="q"><div class="b" style="flex: 1">question<h2>What does the compiler infer here?</h2></div><div class="b">answer box</div></div>\(map)
            """ }
        for (index, map) in [#"<div class="b hot" style="width: 260px">skill map</div>"#, "", #"<div class="b hot" style="width: 60px">map</div>"#].enumerated() {
            try Data(sketch(map).utf8).write(to: app.sketches.appending(path: "\(index + 1).html"))
        }
        draw(open(app, in: home), "2-read", into: out)

        // The builder drew three versions: the user is choosing.
        try FileManager.default.createDirectory(at: app.designs, withIntermediateDirectories: true)
        let page = { (layout: String) in """
            <style>body { display: flex; \(layout) gap: 24px; padding: 40px } h1 { font-size: 26px; margin: 0 0 12px } .map { background: var(--surface); border-radius: var(--radius); padding: 20px; min-width: 240px } .bar { height: 4px; border-radius: 2px; background: var(--accent); margin: 8px 0 16px }</style>
            <div style="flex: 2"><div style="color: var(--secondary)">Elision · question 4</div><h1>What does the compiler infer for this signature?</h1><pre>fn first(s: &str) -> &str</pre></div>
            <div class="map"><b>Rust lifetimes</b><p>Borrowing</p><div class="bar" style="width: 80%"></div><p>Elision</p><div class="bar" style="width: 40%"></div></div>
            """ }
        for (id, layout) in [("A", ""), ("B", "flex-direction: column-reverse;"), ("C", "flex-direction: row-reverse;")] {
            try Data(page(layout).utf8).write(to: app.designs.appending(path: "\(id).html"))
        }
        try Data(#"[{"id":"A","name":"Focus","idea":"One question fills the screen, the map quiet beside it."},{"id":"B","name":"Dashboard","idea":"Your levels first, the next question under them."},{"id":"C","name":"Notebook","idea":"Reads like a page of notes."}]"#.utf8)
            .write(to: app.designs.appending(path: "index.json"))
        try home.save(app.info.at(.design), of: app)
        draw(open(app, in: home), "3-draw", into: out)

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
        let model = open(app, in: home)
        draw(model, "4-in-use", into: out)
        model.knowing = true
        draw(model, "5-what-it-knows", into: out)
        model.editInterface()
        draw(model, "6-shape", into: out)

        // Home, with apps of every kind on the dock, and all of them.
        for name in ["Code Reviewer", "Weekly Planner", "Contract Reader", "Meeting Notes", "Spec Writer", "Running Log", "Bug Triage", "Paper Reader", "Cold Email", "Debate Coach", "Grant Writer", "Meal Planner"] {
            let made = try home.create(Skill(text: "# \(name)\n\nDo it well."))
            if name != "Grant Writer" { try home.save(made.info.at(.done), of: made) }
        }
        let wall = AppModel(home: home)
        draw(wall, "7-home", into: out)
        wall.showingAll = true
        draw(wall, "8-all-apps", into: out)
        wall.arranging = true
        draw(wall, "9-all-apps-loose", into: out)
    }

    /// The model as it is with that app open.
    static func open(_ app: SkillApp, in home: YonkaHome) -> AppModel {
        let model = AppModel(home: home)
        model.selected = app.id
        return model
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
