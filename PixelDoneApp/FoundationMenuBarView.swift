import AppKit
import SwiftUI

struct FoundationMenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open PixelDone") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit PixelDone") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
