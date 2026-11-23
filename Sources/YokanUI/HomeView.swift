import AppKit
import SwiftUI
import YokanCore

/// Home: the one thing to do, and the apps already made. Dropping a skill anywhere makes an
/// app; the dock opens one, and All Apps is the dock, risen.
struct HomeView: View {
    @Bindable var model: AppModel
    @State private var pasted = ""
    @State private var picking = false
    @State private var targeted = false
    @State private var working = false

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Text("Yokan").font(Theme.serif(20))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Theme.lights + 8).padding(.top, 5)
                Spacer()
                VStack(spacing: 18) {
                    Text("Drop a skill.").font(Theme.serif(80)).tracking(-3)
                        .foregroundStyle(model.showingAll ? AnyShapeStyle(Theme.rule) : AnyShapeStyle(.primary))
                    Text("It becomes an app with its own screen and a memory.")
                        .font(.system(size: 17)).foregroundStyle(Theme.soft)
                    VStack(spacing: 8) {
                        // Vertical, so a pasted skill keeps its lines: its frontmatter needs them.
                        TextField("or paste a skill, or a link to one, or to a repository of them", text: $pasted, axis: .vertical)
                            .textFieldStyle(.plain).lineLimit(1...3).multilineTextAlignment(.center)
                            .font(.system(size: 15)).onSubmit { make(pasted) }
                        Rectangle().fill(targeted ? Theme.accent : Theme.rule).frame(height: 1.5)
                        Button { picking = true } label: {
                            Text("or choose one Claude Code already has").underline().foregroundStyle(Theme.dim)
                        }
                        .buttonStyle(.plain).padding(.top, 4)
                        .popover(isPresented: $picking, arrowEdge: .bottom) {
                            SkillPicker { picking = false; make($0) }
                        }
                    }
                    .frame(width: 440).padding(.top, 8)
                    ProgressView().controlSize(.small).opacity(working ? 1 : 0)
                }
                .opacity(model.showingAll ? 0.35 : 1)
                Spacer()
                if !model.apps.isEmpty { Dock(model: model).padding(.bottom, 28).opacity(model.showingAll ? 0 : 1) }
            }
            if model.showingAll {
                AllApps(model: model).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.12), value: model.showingAll)
        .disabled(working)
        // The whole window takes a skill: its file, or the folder it's in. A folder that isn't
        // one skill is a folder of them.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let folder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let file = folder ? url.appending(path: "SKILL.md") : url
            if folder, !FileManager.default.fileExists(atPath: file.path) {
                run { await model.add(folder: url) }
            } else {
                make((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            }
            return true
        } isTargeted: { targeted = $0 }
    }

    private func make(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        run { await model.add(pasted: text) }
    }

    /// Stays home if it couldn't, with why said at the bottom of the window.
    private func run(_ add: @escaping () async -> Bool) {
        working = true
        Task {
            if await add() { pasted = "" }
            working = false
        }
    }
}

/// The first apps, and the way to the rest: in the order the user put them in All Apps, or the
/// ones used last until they have.
private struct Dock: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach((model.hasArrangement ? model.arranged : model.recent).prefix(8)) { app in
                AppButton(model: model, app: app)
            }
            Rectangle().fill(Theme.line).frame(width: 1, height: 62).padding(.horizontal, 8).padding(.top, 8)
            Button { model.showingAll = true } label: {
                VStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1.5)
                        .frame(width: 46, height: 46)
                        .overlay { Text("\(model.apps.count)").font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.soft) }
                    Text("All apps").font(.system(size: 11.5)).foregroundStyle(Theme.soft)
                }
                .frame(width: 92).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
    }
}

/// An app as an icon with its name under it, as the dock and All Apps both show it: a click
/// opens it, a right-click has the rest. Loose, as All Apps has them while they're arranged,
/// it's not a button: it shakes, has a cross to delete it, and its name is there to change.
private struct AppButton: View {
    let model: AppModel
    let app: SkillApp
    var lit = false
    var loose = false
    /// Where it is among the others, so they don't all shake as one.
    var index = 0
    @State private var hovered = false
    @State private var deleting: SkillApp?
    @State private var draft = ""
    @State private var tilted = false
    @FocusState private var typing: Bool
    @Environment(\.accessibilityReduceMotion) private var still

    private var renaming: Bool { model.renaming == app.id }
    private var shaking: Bool { loose && !still && !renaming }

    var body: some View {
        Group {
            if loose {
                label
            } else {
                // Held until they came loose, the release isn't a click.
                Button { if !model.arranging { model.selected = app.id } } label: { label }.buttonStyle(.plain)
            }
        }
        .rotationEffect(.degrees(shaking ? (tilted ? 1.6 : -1.6) : 0))
        .animation(shaking ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true).delay(Double(index % 3) * 0.04) : .default, value: tilted)
        .onChange(of: shaking, initial: true) { tilted = shaking }
        .onHover { hovered = $0 }
        .help(app.info.stage == .done ? app.info.name : "\(app.info.name), still being built")
        .contextMenu {
            Button("Rename…") { model.renaming = app.id }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.folder]) }
            Divider()
            Button("Delete…", role: .destructive) { deleting = app }
        }
        .confirmsDeleting($deleting, in: model)
    }

    private var label: some View {
        VStack(spacing: 8) {
            AppTile(app: app).overlay(alignment: .topLeading) {
                if loose {
                    Button { deleting = app } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme.ink)
                            .frame(width: 18, height: 18).background(Theme.soft, in: Circle())
                            .overlay { Circle().strokeBorder(Theme.panel, lineWidth: 1.5) }
                    }
                    .buttonStyle(.plain).offset(x: -7, y: -7)
                    .accessibilityLabel("Delete \(app.info.name)")
                }
            }
            name.font(.system(size: 11.5)).frame(height: 16)
        }
        .frame(width: 92).padding(.vertical, 8)
        .background(lit || hovered ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Typed over where it stands, as Finder does: Return or a click elsewhere keeps it, Escape doesn't.
    @ViewBuilder private var name: some View {
        if renaming {
            TextField("Name", text: $draft).textFieldStyle(.plain).multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1) }
                .focused($typing)
                .onAppear { (draft, typing) = (app.info.name, true) }
                .onSubmit(keep)
                .onExitCommand { model.renaming = nil }
                .onChange(of: typing) { if !typing { keep() } }
        } else {
            Text(app.info.name).foregroundStyle(Theme.soft).lineLimit(1)
                // Only loose: on a button, the name is part of what's pressed.
                .gesture(TapGesture().onEnded { model.renaming = app.id }, including: loose ? .all : .subviews)
        }
    }

    private func keep() {
        guard renaming else { return }
        model.renaming = nil
        model.rename(app, to: draft)
    }
}

/// A loose app dragged over another takes its place.
private struct Mover: DropDelegate {
    let target: String
    @Binding var dragged: String?
    let move: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropEntered(info: DropInfo) { if let dragged, dragged != target { move(dragged) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

extension View {
    /// Asks before an app goes: wherever one can be deleted from, it's the same question.
    func confirmsDeleting(_ app: Binding<SkillApp?>, in model: AppModel) -> some View {
        confirmationDialog(
            "Delete \(app.wrappedValue?.info.name ?? "")?", isPresented: Binding(get: { app.wrappedValue != nil }, set: { if !$0 { app.wrappedValue = nil } }),
            presenting: app.wrappedValue
        ) { app in
            Button("Delete", role: .destructive) { model.delete(app) }
        } message: { _ in
            Text("Its memory and sessions go to the Trash with it, so it can be put back.")
        }
    }
}

/// Every app, with the box to find one already taking the keyboard: a few letters and Return.
/// Edit, or holding one, lets them loose, the way a Mac's or a phone's apps come loose: drag one
/// to move it, its cross deletes it, its name is there to change.
private struct AllApps: View {
    private enum Order { case recent, name, arranged }

    @Bindable var model: AppModel
    @State private var query = ""
    @State private var order: Order
    @State private var dragged: String?
    @FocusState private var focused: Bool

    /// As they left them, if they've arranged them.
    init(model: AppModel) {
        self.model = model
        _order = State(initialValue: model.hasArrangement ? .arranged : .recent)
    }

    private var all: [SkillApp] {
        switch order {
        case .recent: model.recent
        case .name: model.apps
        case .arranged: model.arranged
        }
    }

    private var apps: [SkillApp] {
        let all = all
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : all.filter { $0.info.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 16) {
                VStack(spacing: 6) {
                    TextField("Find an app", text: $query).textFieldStyle(.plain).font(Theme.serif(28))
                        .focused($focused).onSubmit { if let first = apps.first { model.selected = first.id } }
                    Rectangle().fill(Theme.accent).frame(height: 2)
                }
                HStack(spacing: 4) {
                    pick("Recent", .recent)
                    pick("A to Z", .name)
                    if model.hasArrangement { pick("Arranged", .arranged) }
                }
                Button { model.arranging.toggle() } label: { Text(model.arranging ? "Done" : "Edit").pill(filled: model.arranging) }
                    .buttonStyle(.plain)
                // Escape puts the apps back before it leaves.
                Button { if model.arranging { model.arranging = false } else { model.showingAll = false } } label: {
                    Text("esc").font(Theme.label).foregroundStyle(Theme.dim).padding(.horizontal, 12).frame(height: 32)
                        .overlay { Capsule().strokeBorder(Theme.rule, lineWidth: 1) }.contentShape(Capsule()).fixedSize()
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 4)], spacing: 6) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        // The first is what Return opens.
                        let tile = AppButton(model: model, app: app, lit: index == 0 && !query.isEmpty, loose: model.arranging, index: index)
                        if model.arranging {
                            tile.onDrag {
                                dragged = app.id
                                return NSItemProvider(object: app.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: Mover(target: app.id, dragged: $dragged) { id in
                                // From the order on screen, which is theirs from here.
                                withAnimation(.spring(duration: 0.3)) {
                                    model.move(id, to: app.id, in: all)
                                    order = .arranged
                                }
                            })
                        } else {
                            tile.simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in model.arranging = true })
                        }
                    }
                }
            }
            HStack {
                Text(apps.isEmpty ? "No app by that name" : "\(apps.count) apps · a dashed icon is still being built")
                Spacer()
                Text(model.arranging ? "drag to move · the cross deletes · click a name to rename" : "return opens the first · hold an app to rearrange")
            }
            .font(Theme.label).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 30).padding(.top, 26).padding(.bottom, 20)
        .frame(maxWidth: 1080, maxHeight: .infinity)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.line, lineWidth: 1) }
        .shadow(color: .black.opacity(0.5), radius: 40, y: -10)
        .padding(.horizontal, 40).padding(.top, 150).padding(.bottom, 28)
        .onAppear { focused = true }
    }

    private func pick(_ title: String, _ choice: Order) -> some View {
        let on = order == choice
        return Button { order = choice } label: {
            Text(title).font(.system(size: 13)).foregroundStyle(on ? .primary : Theme.dim)
                .padding(.horizontal, 14).frame(height: 32)
                .background(on ? Theme.raised : .clear, in: Capsule()).contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The skills Claude Code already has on this Mac: the nearest place to find one.
private struct SkillPicker: View {
    let pick: (String) -> Void
    @State private var skills: [Skill] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(skills, id: \.name) { skill in
                    Button { pick(skill.text) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.name)
                            Text(skill.description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7).padding(.horizontal, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                if skills.isEmpty { Text("Claude Code has no skills here yet.").foregroundStyle(.secondary).padding(20) }
            }
        }
        .frame(width: 380, height: 340)
        .task { skills = Skill.installed() }
    }
}
