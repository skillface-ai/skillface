import AppKit
import SwiftUI
import SkillfaceCore

/// One app, open: being built, or in use, where its sessions run along the top as one
/// lifeline and what it remembers opens beside it.
struct AppScreen: View {
    @Bindable var model: AppModel
    let app: SkillApp
    @State private var deleting: SkillApp?

    private var building: Bool { app.info.stage != .done }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { model.selected = nil } label: {
                    Label("Home", systemImage: "chevron.left").font(.system(size: 13)).foregroundStyle(Theme.dim).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(app.info.name).font(Theme.serif(19)).lineLimit(1).fixedSize()
                if building {
                    Steps(stage: app.info.stage)
                    Spacer()
                    // Nothing to ship until a version is chosen, or while it's still being made.
                    if app.info.stage == .adjust || app.info.stage == .implement {
                        Button { model.finish() } label: { Text("It's right. Ship it").pill(filled: true) }
                            .buttonStyle(.plain)
                            .disabled(model.buildSession.map { model.live[$0.id] != nil } ?? true)
                    }
                } else {
                    Lifeline(model: model)
                    Button { model.knowing.toggle() } label: { Text("What it knows").pill(on: model.knowing) }.buttonStyle(.plain)
                    Button { model.editInterface() } label: { Text("Reshape").pill() }.buttonStyle(.plain)
                        .help("Change how \(app.info.name) looks and works")
                }
                Menu {
                    ProviderPicker(model: model)
                    Divider()
                    Button(model.skills.isEmpty ? "Skill…" : "Skills…") { model.showingSkill = true }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.folder]) }
                    // Turning it on is asked about: turning it off never is.
                    Toggle(Agent.switchName, isOn: Binding(get: { model.terminal }, set: { if $0 { model.allowing = true } else { model.allowTerminal(false) } }))
                    Divider()
                    Button("Delete…", role: .destructive) { deleting = app }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.dim)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(.leading, Theme.lights + 8).padding(.trailing, 18).frame(height: 52)

            if building {
                BuilderView(model: model, app: app)
            } else {
                HStack(spacing: 14) {
                    if let session = model.session {
                        InterfaceView(html: model.interface, state: model.state(of: session), send: { model.send($0, in: session.id) }, failed: model.interfaceFailed)
                            // A page is one session's, as one design drew it.
                            .id(session.id + model.interface)
                            .stage()
                    }
                    if model.knowing { Knows(model: model, app: app).transition(.move(edge: .trailing).combined(with: .opacity)) }
                }
                .padding([.horizontal, .bottom], 14)
                .animation(.spring(duration: 0.35, bounce: 0.1), value: model.knowing)
            }
        }
        .confirmsDeleting($deleting, in: model)
        .confirmationDialog("Let \(app.info.name) run commands on this Mac?", isPresented: $model.allowing) {
            Button("Let It") { model.allowTerminal(true) }
        } message: {
            Text("It runs what its skill says to, without asking each time, in a sandbox: it can download Python packages and reach nothing else on the network, and it can write only in its own memory and work folder. It can read most other files on this Mac.")
        }
        .sheet(item: $model.proposed) { proposal in
            VStack(alignment: .leading, spacing: 14) {
                Text("Run this on your Mac?").font(Theme.serif(24))
                Text("\(app.info.name) asks for it. It runs outside the sandbox, as you, with nothing held back. Any file it names in the app's folder was written by the app. Read it first.").foregroundStyle(Theme.dim)
                ScrollView { Text(proposal.command.text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Spacer()
                    // No default: Return shouldn't run a stranger's command.
                    Button("Don't Run") { model.answer(proposal, run: false) }.keyboardShortcut(.cancelAction)
                    Button("Run") { model.answer(proposal, run: true) }
                }
            }
            .padding(24).frame(width: 560, height: 320).interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.showingSkill) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.skills.isEmpty ? "The skill" : "The skills").font(Theme.serif(24))
                // A repository's skills stay as they came: to read, not to change.
                FilesEditor(files: model.skillFiles, save: { model.save($1, as: $0, in: .skill) }, fixed: { $0.hasPrefix("source/") })
                Button("Done") { model.showingSkill = false }.keyboardShortcut(.defaultAction).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(24).frame(width: 720, height: 600)
        }
    }
}

/// Where the build is: its four steps as words, the current one marked.
private struct Steps: View {
    let stage: SkillApp.Stage
    private static let names: [(SkillApp.Stage, String)] = [(.interview, "Read"), (.design, "Draw"), (.adjust, "Shape"), (.implement, "Ship")]

    var body: some View {
        let current = Self.names.firstIndex { $0.0 == stage } ?? Self.names.count
        HStack(spacing: 18) {
            ForEach(Array(Self.names.enumerated()), id: \.offset) { index, step in
                Text(step.1).font(Theme.serif(19))
                    .foregroundStyle(index == current ? AnyShapeStyle(.primary) : AnyShapeStyle(index < current ? Theme.dim : Theme.rule))
                    .padding(.bottom, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(index == current ? Theme.accent : .clear).frame(height: 2) }
            }
        }
        .padding(.leading, 10)
        .animation(.easeInOut(duration: 0.25), value: stage)
        .accessibilityElement()
        .accessibilityLabel("Step \(min(current + 1, 4)) of 4: \(stage.rawValue)")
    }
}

/// An app's sessions as one thread, oldest to newest: its life so far. The open one is lit.
///
/// ponytail: the last five are on the thread and the rest are in a menu. Make the thread
/// scroll, or scale by time, once apps have long lives.
private struct Lifeline: View {
    @Bindable var model: AppModel
    private static let shown = 5

    var body: some View {
        let chapters = Array(model.useSessions.reversed())
        let earlier = chapters.dropLast(Self.shown)
        HStack(spacing: 4) {
            if !earlier.isEmpty {
                Menu("Earlier") {
                    ForEach(earlier.reversed()) { session in Button(label(session)) { model.sessionID = session.id } }
                }
                .menuStyle(.borderlessButton).fixedSize().font(Theme.label).foregroundStyle(Theme.dim)
            }
            ForEach(chapters.suffix(Self.shown)) { session in
                let current = session.id == model.sessionID
                Button { model.sessionID = session.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(current ? Theme.accent : Theme.rule).frame(height: 4)
                        HStack(spacing: 5) {
                            if model.live[session.id] != nil { ProgressView().controlSize(.mini) }
                            Text(label(session)).font(Theme.label).lineLimit(1).foregroundStyle(current ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.dim))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Delete", role: .destructive) { model.delete(session) } }
            }
            Button { model.newSession() } label: {
                Text("+ New").font(.system(size: 12.5)).foregroundStyle(Theme.soft).padding(.horizontal, 12).frame(height: 28)
                    .overlay { Capsule().strokeBorder(Theme.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }.contentShape(Capsule())
            }
            .buttonStyle(.plain).padding(.leading, 8)
        }
        .padding(.horizontal, 10)
    }

    private func label(_ session: Session) -> String {
        session.messages.isEmpty ? "New" : "\(session.updated.formatted(.dateTime.weekday(.abbreviated))) · \(session.title)"
    }
}

/// What the app remembers, beside it: the files every session starts from, to read and to put right.
private struct Knows: View {
    let model: AppModel
    let app: SkillApp

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What it knows").font(Theme.serif(26))
                Text("Every session starts from this. Change what's wrong.").foregroundStyle(Theme.dim)
            }
            if model.memory.isEmpty {
                Text("Nothing yet. What \(app.info.name) learns about you and your work appears here.")
                    .foregroundStyle(Theme.soft).frame(maxHeight: .infinity, alignment: .top)
            } else {
                FilesEditor(files: model.memory, save: { model.save($1, as: $0, in: .memory) }, delete: model.forget)
            }
            Text("Kept as files on this Mac. Only this app's agent writes them.").font(Theme.label).foregroundStyle(Theme.dim)
        }
        .padding(22)
        .frame(width: 380)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
    }
}

/// A few files, one open at a time, saved as it's typed: an app's memory, and its skill.
struct FilesEditor: View {
    let files: [TextFile]
    let save: (String, String) -> Void
    var delete: ((String) -> Void)?
    /// The files that are only to read.
    var fixed: (String) -> Bool = { _ in false }

    @State private var selected: String?
    @State private var draft = ""

    private var text: String? { files.first { $0.name == selected }?.text }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(files) { file in
                        let on = file.name == selected
                        Button { selected = file.name } label: {
                            Text(file.name).font(Theme.label).foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.dim))
                                .padding(.horizontal, 10).frame(height: 26)
                                .background(on ? Theme.raised : .clear, in: Capsule()).contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let delete { Button("Delete", role: .destructive) { delete(file.name) } }
                        }
                    }
                }
            }
            Group {
                if let selected, fixed(selected) {
                    ScrollView { Text(draft).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(5) }
                } else {
                    TextEditor(text: $draft).scrollContentBackground(.hidden)
                }
            }
            .font(.system(size: 12.5, design: .monospaced))
            .padding(10)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .onAppear(perform: show)
        // The agent may have written it since.
        .onChange(of: files) { show() }
        .onChange(of: selected) { show() }
        .onChange(of: draft) {
            if let selected, !fixed(selected), let text, draft != text { save(selected, draft) }
        }
    }

    private func show() {
        if text == nil { selected = files.first?.name }
        if let text, draft != text { draft = text }
    }
}
