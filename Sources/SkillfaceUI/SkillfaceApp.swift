import AppKit
import SwiftUI

package struct SkillfaceApp: App {
    @State private var model = AppModel()

    package init() {
        // Run from `swift run`, the binary isn't in an app bundle and would start as a background process.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    package var body: some Scene {
        Window("Skillface", id: "main") {
            RootView(model: model)
                .frame(minWidth: 980, minHeight: 640)
                // Under the title bar, which is hidden: the window is all content.
                .ignoresSafeArea(edges: .top)
                .onAppear { NSApp.activate() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            // App-wide shortcuts are menu items, so they work whatever is showing.
            CommandGroup(replacing: .newItem) {
                Button("New Session") { model.newSession() }.keyboardShortcut("n")
                    .disabled(model.app?.info.stage != .done)
                Button("Home") { model.selected = nil }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("All Apps") {
                    model.selected = nil
                    model.showingAll = true
                }
                .keyboardShortcut("k")
            }
        }
    }
}
