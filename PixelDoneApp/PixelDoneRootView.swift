import PixelDoneDomain
import SwiftUI

struct PixelDoneRootView: View {
    @Bindable var store: PixelDoneStore
    @Environment(\.openSettings) private var openSettings
    @State private var newChecklistName = ""
    @State private var renamedChecklistName = ""
    @State private var checklistToRename: PixelDoneChecklist?
    @State private var checklistToDelete: PixelDoneChecklist?
    @State private var isAddingChecklist = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            Group {
                if !store.isLoaded {
                    ProgressView("Opening PixelDone…")
                        .controlSize(.large)
                } else if store.selectedChecklistID
                            == PixelDoneProductBaseline.settingsChecklistID {
                    SettingsShortcutView(openSettings: openSettings)
                } else {
                    TodoWorkspaceView(store: store)
                }
            }
            .background(Color.pixelDoneWorkspace)
        }
        .inspector(
            isPresented: Binding(
                get: { store.inspectedTodo != nil },
                set: { if !$0 { store.inspectedTodoID = nil } }
            )
        ) {
            if let todo = store.inspectedTodo {
                TodoInspectorView(store: store, todo: todo)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
            }
        }
        .tint(.pixelDoneClay)
        .task {
            await store.load()
        }
        .sheet(item: $store.editorPresentation) { presentation in
            TodoEditorView(store: store, presentation: presentation)
        }
        .alert("New checklist", isPresented: $isAddingChecklist) {
            TextField("Name", text: $newChecklistName)
            Button("Cancel", role: .cancel) {
                newChecklistName = ""
            }
            Button("Create") {
                let name = newChecklistName
                newChecklistName = ""
                Task { await store.send(.createChecklist(name)) }
            }
        } message: {
            Text("Give this checklist a short, recognizable name.")
        }
        .alert(
            "Rename checklist",
            isPresented: Binding(
                get: { checklistToRename != nil },
                set: { if !$0 { checklistToRename = nil } }
            )
        ) {
            TextField("Name", text: $renamedChecklistName)
            Button("Cancel", role: .cancel) {
                checklistToRename = nil
            }
            Button("Rename") {
                guard let checklist = checklistToRename else { return }
                let name = renamedChecklistName
                checklistToRename = nil
                Task {
                    await store.send(
                        .renameChecklist(id: checklist.id, name: name)
                    )
                }
            }
        }
        .alert(
            "Delete checklist?",
            isPresented: Binding(
                get: { checklistToDelete != nil },
                set: { if !$0 { checklistToDelete = nil } }
            ),
            presenting: checklistToDelete
        ) { checklist in
            Button("Cancel", role: .cancel) {
                checklistToDelete = nil
            }
            Button("Delete", role: .destructive) {
                checklistToDelete = nil
                Task { await store.send(.deleteChecklist(checklist.id)) }
            }
        } message: { checklist in
            Text("“\(checklist.name)” and its tasks will be permanently removed.")
        }
        .alert(
            "PixelDone",
            isPresented: Binding(
                get: { store.notice != nil || store.errorMessage != nil },
                set: {
                    if !$0 {
                        store.notice = nil
                        store.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.notice = nil
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? store.notice ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section("Workspace") {
                sidebarRow(
                    id: PixelDoneProductBaseline.defaultChecklistID,
                    title: "MAIN",
                    symbol: "checklist"
                )
            }

            Section("Checklists") {
                ForEach(store.ordinaryChecklists) { checklist in
                    sidebarRow(
                        id: checklist.id,
                        title: checklist.name,
                        symbol: "square.stack.3d.up"
                    )
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            renamedChecklistName = checklist.name
                            checklistToRename = checklist
                        }
                        Button(
                            "Delete",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            checklistToDelete = checklist
                        }
                    }
                }
            }

            Section("System") {
                sidebarRow(
                    id: PixelDoneProductBaseline.trashChecklistID,
                    title: "TRASH",
                    symbol: "trash"
                )
                sidebarRow(
                    id: PixelDoneProductBaseline.settingsChecklistID,
                    title: "SETTINGS",
                    symbol: "gearshape"
                )
            }

            Section("Connection") {
                LabeledContent {
                    Text(syncMode)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
        .navigationTitle("PixelDone")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New checklist", systemImage: "folder.badge.plus") {
                    isAddingChecklist = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedChecklistID },
            set: { id in
                guard let id, id != store.selectedChecklistID else { return }
                Task { await store.send(.selectChecklist(id)) }
            }
        )
    }

    private func sidebarRow(
        id: String,
        title: String,
        symbol: String
    ) -> some View {
        Label(title, systemImage: symbol)
            .tag(id)
            .accessibilityAddTraits(
                store.selectedChecklistID == id ? .isSelected : []
            )
    }

    private var syncMode: String {
        AppConfiguration.current == nil ? "Local only" : "Configured"
    }
}

private extension Color {
    static var pixelDoneWorkspace: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

private struct SettingsShortcutView: View {
    let openSettings: OpenSettingsAction

    var body: some View {
        ContentUnavailableView {
            Label("PixelDone Settings", systemImage: "gearshape")
        } description: {
            Text("Settings use a dedicated native macOS window.")
        } actions: {
            Button("Open Settings") {
                openSettings()
            }
            .buttonStyle(.glassProminent)
            .tint(.pixelDoneClay)
        }
    }
}
