import AppKit
import SwiftUI

package struct YonkaApp: App {
    @State private var model = AppModel()

    package init() {
        // Run from `swift run`, the binary isn't in an app bundle and would start as a background process.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    package var body: some Scene {
        Window("Yonka", id: "main") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { NSApp.activate() }
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            // App-wide shortcuts are menu items, so they work whatever is showing.
            CommandGroup(replacing: .newItem) {
                Button("New Session") { model.newSession() }.keyboardShortcut("n")
                    .disabled(model.app?.info.stage != .done)
                Button("New App…") { model.adding = true }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
