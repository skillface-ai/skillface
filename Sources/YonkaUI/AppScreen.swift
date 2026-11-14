import SwiftUI
import YonkaCore

/// One app: being built, or in use, where it's its sessions, its memory and its skill.
struct AppScreen: View {
    @Bindable var model: AppModel
    let app: SkillApp

    private var building: Bool { app.info.stage != .done }

    var body: some View {
        Group {
            if building {
                BuilderView(model: model, app: app)
            } else {
                switch model.tab {
                case .sessions: SessionsPane(model: model)
                case .memory:
                    FilesPane(
                        files: model.memory, symbol: "brain",
                        empty: ("Nothing remembered yet", "What \(app.info.name) learns about you and your work appears here, and every session starts from it."),
                        save: { model.save($1, as: $0, in: .memory) }, delete: model.forget)
                case .skill:
                    FilesPane(
                        files: model.skillFiles, symbol: "doc.text", empty: ("No skill", ""),
                        save: { model.save($1, as: $0, in: .skill) })
                }
            }
        }
        .navigationTitle(app.info.name)
        .toolbar {
            if building {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { model.finish() }
                        .buttonStyle(.borderedProminent)
                        // Nothing to call done until there's a design, or while it's still being made.
                        .disabled(app.info.stage == .interview || app.info.stage == .design || model.buildSession.map { model.live[$0.id] != nil } ?? true)
                        .help("The design is right: finish the app")
                }
            } else {
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $model.tab) {
                        ForEach(AppModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit Interface", systemImage: "paintbrush") { model.editInterface() }
                        .help("Change how \(app.info.name) looks and works")
                }
            }
        }
    }
}

/// Every session down the side, and the one that's open in the app's own interface.
private struct SessionsPane: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Button { model.newSession() } label: {
                    Label("New Session", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 12)
                Divider()
                List(selection: $model.sessionID) {
                    ForEach(model.useSessions) { session in
                        SessionRow(session: session, working: model.live[session.id] != nil)
                            .tag(session.id)
                            .contextMenu { Button("Delete", role: .destructive) { model.delete(session) } }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 240)
            Divider()
            if let session = model.session {
                InterfaceView(html: model.interface, state: model.state(of: session), send: { model.send($0, in: session.id) }, failed: model.interfaceFailed)
                    // A page is one session's, as one design drew it.
                    .id(session.id + model.interface)
            } else {
                Color.clear
            }
        }
    }
}

private struct SessionRow: View {
    let session: Session
    let working: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title).lineLimit(1)
            HStack(spacing: 6) {
                if working { ProgressView().controlSize(.mini) }
                Text(working ? "Answering" : session.updated.formatted(.relative(presentation: .named)))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Files down the side and the open one's text, which saves as it's typed: an app's memory,
/// and its skill.
struct FilesPane: View {
    let files: [TextFile]
    let symbol: String
    let empty: (title: String, detail: String)
    let save: (String, String) -> Void
    var delete: ((String) -> Void)?

    @State private var selected: String?
    @State private var draft = ""

    private var text: String? { files.first { $0.name == selected }?.text }

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView(empty.title, systemImage: symbol, description: Text(empty.detail))
            } else {
                HStack(spacing: 0) {
                    List(files, selection: $selected) { file in
                        Label(file.name, systemImage: "doc.text").lineLimit(1).tag(file.name)
                            .contextMenu {
                                if let delete { Button("Delete", role: .destructive) { delete(file.name) } }
                            }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(width: 240)
                    Divider()
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 20).padding(.vertical, 16)
                }
            }
        }
        .onAppear(perform: show)
        // The agent may have written it since.
        .onChange(of: files) { show() }
        .onChange(of: selected) { show() }
        .onChange(of: draft) {
            if let selected, let text, draft != text { save(selected, draft) }
        }
    }

    private func show() {
        if text == nil { selected = files.first?.name }
        if let text, draft != text { draft = text }
    }
}
