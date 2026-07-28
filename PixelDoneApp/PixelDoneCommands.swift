import PixelDoneDomain
import SwiftUI

struct PixelDoneCommands: Commands {
    let store: PixelDoneStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                store.editorPresentation = .create
            }
            .keyboardShortcut("n")

            Button("New Checklist") {
                store.notice =
                    "Use the New Checklist button in the sidebar to name it."
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Tasks") {
            Button("Sort by Priority") {
                Task { await store.send(.setSortMode(.priority)) }
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button("Sort by Deadline") {
                Task { await store.send(.setSortMode(.time)) }
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Divider()

            Button("Toggle Deadline Countdown") {
                Task { await store.send(.toggleDeadline) }
            }

            Button("Hide Completed") {
                Task { await store.send(.toggleHideCompleted) }
            }

            Button("Clean Completed") {
                Task { await store.send(.cleanCompleted) }
            }
        }
    }
}
