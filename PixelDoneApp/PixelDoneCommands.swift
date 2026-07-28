import PixelDoneDomain
import SwiftUI

struct PixelDoneCommands: Commands {
    let store: PixelDoneStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("new_task") {
                store.editorPresentation = .create
            }
            .keyboardShortcut("n")

            Button("new_list") {
                store.notice =
                    "Use the New Checklist button in the sidebar to name it."
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("app") {
            Button("field_priority") {
                Task { await store.send(.setSortMode(.priority)) }
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button("deadline_short") {
                Task { await store.send(.setSortMode(.time)) }
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Divider()

            Button("toggle_deadline") {
                Task { await store.send(.toggleDeadline) }
            }

            Button("hide_done") {
                Task { await store.send(.toggleHideCompleted) }
            }

            Button("clean_done") {
                Task { await store.send(.cleanCompleted) }
            }
        }
    }
}
