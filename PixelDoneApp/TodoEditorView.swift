import PixelDoneDomain
import SwiftUI

struct TodoEditorView: View {
    @Bindable var store: PixelDoneStore
    let presentation: EditorPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoDraft

    init(store: PixelDoneStore, presentation: EditorPresentation) {
        self.store = store
        self.presentation = presentation
        _draft = State(initialValue: store.draft(for: presentation))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(title)
                    .font(.title2.weight(.bold))
                Spacer()
                Button("Close", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }

            Form {
                Section("Task") {
                    TextField(
                        "What needs to be done?",
                        text: $draft.title,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    Picker("Priority", selection: $draft.priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Deadline") {
                    DatePicker(
                        "Due",
                        selection: $draft.dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Picker("Repeat", selection: $draft.reminderRepeat) {
                        Text("None").tag(ReminderRepeat.none)
                        Text("Daily").tag(ReminderRepeat.daily)
                        Text("Weekly").tag(ReminderRepeat.weekly)
                    }
                }

                Section {
                    Label(
                        "Attachments use the native file importer and app-private normalized copies.",
                        systemImage: "paperclip"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .buttonStyle(.glassProminent)
                .tint(.pixelDoneClay)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    draft.title.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 520, height: 520)
    }

    private var title: String {
        switch presentation {
        case .create: "New task"
        case .edit: "Edit task"
        }
    }

    private func save() {
        Task {
            switch presentation {
            case .create:
                await store.send(.createTodo(draft))
            case let .edit(todo):
                await store.send(.updateTodo(id: todo.id, draft: draft))
            }
            dismiss()
        }
    }
}

struct TodoInspectorView: View {
    @Bindable var store: PixelDoneStore
    let todo: PixelDoneTodo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TASK")
                            .font(.caption.weight(.black))
                            .foregroundStyle(todo.priority.color)
                        Text(todo.title)
                            .font(.title2.weight(.bold))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Close inspector", systemImage: "xmark") {
                        store.inspectedTodoID = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("Priority").foregroundStyle(.secondary)
                        Text(todo.priority.displayName)
                            .fontWeight(.bold)
                            .foregroundStyle(todo.priority.color)
                    }
                    GridRow {
                        Text("Due").foregroundStyle(.secondary)
                        Text(
                            Date(
                                timeIntervalSince1970:
                                    Double(todo.dueAtMillis) / 1_000
                            ),
                            format: .dateTime.year().month().day().hour().minute()
                        )
                    }
                    GridRow {
                        Text("Repeat").foregroundStyle(.secondary)
                        Text(todo.reminderRepeat.rawValue.capitalized)
                    }
                    GridRow {
                        Text("State").foregroundStyle(.secondary)
                        Text(todo.completed ? "Completed" : "Active")
                    }
                }

                Spacer(minLength: 8)

                if store.selectedChecklistID
                    == PixelDoneProductBaseline.trashChecklistID {
                    Button("Restore", systemImage: "arrow.uturn.backward") {
                        Task { await store.send(.restoreTodo(todo.id)) }
                    }
                    .buttonStyle(.glassProminent)

                    Button(
                        "Delete Forever",
                        systemImage: "trash.slash",
                        role: .destructive
                    ) {
                        Task {
                            await store.send(.permanentlyDelete(todo.id))
                        }
                    }
                } else {
                    Button("Edit Task", systemImage: "pencil") {
                        store.editorPresentation = .edit(todo)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pixelDoneClay)

                    Button(
                        "Move to Trash",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        Task { await store.send(.moveToTrash(todo.id)) }
                    }
                }
            }
            .padding(20)
        }
    }
}
