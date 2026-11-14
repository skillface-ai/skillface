import AppKit
import SwiftUI
import YonkaCore

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
                Text("Yonka").font(Theme.serif(20))
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
                        TextField("or paste a skill, or a link to one", text: $pasted, axis: .vertical)
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
        // The whole window takes a skill: its file, or the folder it's in.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let file = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? url.appending(path: "SKILL.md") : url
            make((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            return true
        } isTargeted: { targeted = $0 }
    }

    /// Stays home if it couldn't, with why said at the bottom of the window.
    private func make(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        working = true
        Task {
            if await model.add(pasted: text) { pasted = "" }
            working = false
        }
    }
}

/// The apps used last, and the way to the rest.
private struct Dock: View {
    let model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(model.recent.prefix(8)) { app in
                AppButton(app: app) { model.selected = app.id }
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

/// An app as an icon with its name under it, as the dock and All Apps both show it.
private struct AppButton: View {
    let app: SkillApp
    var lit = false
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                AppTile(app: app)
                Text(app.info.name).font(.system(size: 11.5)).foregroundStyle(Theme.soft).lineLimit(1)
            }
            .frame(width: 92).padding(.vertical, 8)
            .background(lit || hovered ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(app.info.stage == .done ? app.info.name : "\(app.info.name), still being built")
    }
}

/// Every app, with the box to find one already taking the keyboard: a few letters and Return.
private struct AllApps: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var byName = false
    @State private var deleting: SkillApp?
    @FocusState private var focused: Bool

    private var apps: [SkillApp] {
        let all = byName ? model.apps : model.recent
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
                    order("Recent", on: !byName) { byName = false }
                    order("A to Z", on: byName) { byName = true }
                }
                Button { model.showingAll = false } label: {
                    Text("esc").font(Theme.label).foregroundStyle(Theme.dim).padding(.horizontal, 12).frame(height: 32)
                        .overlay { Capsule().strokeBorder(Theme.rule, lineWidth: 1) }.contentShape(Capsule()).fixedSize()
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 4)], spacing: 6) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        // The first is what Return opens.
                        AppButton(app: app, lit: index == 0 && !query.isEmpty) { model.selected = app.id }
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.folder]) }
                                Button("Delete…", role: .destructive) { deleting = app }
                            }
                    }
                }
            }
            HStack {
                Text(apps.isEmpty ? "No app by that name" : "\(apps.count) apps · a dashed icon is still being built")
                Spacer()
                Text("return opens the first · right-click for more")
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
        .confirmationDialog(
            "Delete \(deleting?.info.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { app in
            Button("Delete", role: .destructive) { model.delete(app) }
        } message: { _ in
            Text("Its memory and sessions go to the Trash with it.")
        }
    }

    private func order(_ title: String, on: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
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
