import AppKit
import SwiftUI

struct PixelDoneMenuBarView: View {
    @Bindable var store: PixelDoneStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LabeledContent("status_active", value: "\(activeCount)")

        Divider()

        Button("new_task", systemImage: "plus") {
            openMainWindow()
            store.editorPresentation = .create
        }

        Button("shell_open_app") {
            openMainWindow()
        }

        Divider()

        Button("shell_quit_app") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var activeCount: Int {
        store.snapshot.todos.filter { !$0.completed }.count
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
