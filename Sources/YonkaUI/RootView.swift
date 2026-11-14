import AppKit
import SwiftUI
import YonkaCore

/// The window: the apps on the left, the selected one on the right.
package struct RootView: View {
    @Bindable var model: AppModel

    package init(model: AppModel) { self.model = model }

    package var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            Group {
                if let app = model.app { AppScreen(model: model, app: app) } else { Welcome(model: model) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            // What went wrong, said over whatever's showing and never in the way.
            .overlay(alignment: .bottom) {
                if let notice = model.notice {
                    Text(notice)
                        .font(.callout)
                        .lineLimit(3)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        .padding(24)
                        .onTapGesture { model.notice = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: notice) {
                            try? await Task.sleep(for: .seconds(8))
                            if model.notice == notice { model.notice = nil }
                        }
                }
            }
            .animation(.spring(duration: 0.35), value: model.notice)
        }
        .sheet(isPresented: $model.adding) { NewAppSheet(model: model) }
    }
}

private struct Sidebar: View {
    @Bindable var model: AppModel
    @State private var deleting: SkillApp?

    var body: some View {
        List(selection: $model.selected) {
            ForEach(model.apps) { app in
                Label {
                    Text(app.info.name).lineLimit(1)
                } icon: {
                    AppTile(app: app, size: 22)
                }
                .tag(app.id)
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.folder]) }
                    Button("Delete…", role: .destructive) { deleting = app }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { model.adding = true } label: {
                Label("New App", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .confirmationDialog(
            "Delete \(deleting?.info.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { app in
            Button("Delete", role: .destructive) { model.delete(app) }
        } message: { _ in
            Text("Its memory and sessions go to the Trash with it.")
        }
    }
}

/// With no app yet: the one thing to do.
private struct Welcome: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Text("Turn a skill into an app.")
                .font(.system(size: 34, weight: .semibold)).tracking(-0.6)
            Text("Its own interface, a memory that lasts, and every session kept.")
                .font(.title3).foregroundStyle(.secondary)
            Button("New App") { model.adding = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding(.top, 18)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}

/// An app's icon: its symbol on a swatch of its own colour, the same on every Mac.
struct AppTile: View {
    let app: SkillApp
    var size: CGFloat = 44

    var body: some View {
        let hash = app.id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        // The builder picks the symbol, and may name one this Mac doesn't have.
        let symbol = NSImage(systemSymbolName: app.info.symbol, accessibilityDescription: nil) == nil ? "sparkles" : app.info.symbol
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.8).gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
            }
    }
}
