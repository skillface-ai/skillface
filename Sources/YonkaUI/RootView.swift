import SwiftUI
import YonkaCore

/// The window: home, or the app that's open.
package struct RootView: View {
    @Bindable var model: AppModel

    package init(model: AppModel) { self.model = model }

    package var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if let app = model.app {
                AppScreen(model: model, app: app).transition(.opacity)
            } else {
                HomeView(model: model).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.selected)
        // What went wrong, said over whatever's showing and never in the way.
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.callout).lineLimit(3)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.raised, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.rule, lineWidth: 1) }
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
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
        // Always dark, and every app in it with it.
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }
}
