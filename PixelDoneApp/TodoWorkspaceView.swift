import PixelDoneDomain
import SwiftUI

struct TodoWorkspaceView: View {
    @Bindable var store: PixelDoneStore

    var body: some View {
        Group {
            if store.visibleTodos.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if canCreate {
                        Button("new_task") {
                            store.editorPresentation = .create
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.pixelDoneClay)
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.visibleTodos) { todo in
                                TodoRowView(store: store, todo: todo)
                                    .id(todo.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: store.highlightedTodoID) { _, id in
                        guard let id else { return }
                        withAnimation(.snappy) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .navigationTitle(store.selectedChecklist?.name ?? "PixelDone")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker(
                        "sort",
                        selection: Binding(
                            get: { store.snapshot.settings.sortMode },
                            set: { mode in
                                Task { await store.send(.setSortMode(mode)) }
                            }
                        )
                    ) {
                        Label("field_priority", systemImage: "flag")
                            .tag(TodoSortMode.priority)
                        Label("deadline_short", systemImage: "clock")
                            .tag(TodoSortMode.time)
                    }
                } label: {
                    Label("sort", systemImage: "arrow.up.arrow.down")
                }

                if canCreate {
                    Button("new_task", systemImage: "plus") {
                        store.editorPresentation = .create
                    }
                    .keyboardShortcut("n")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.selectedChecklistID
                != PixelDoneProductBaseline.trashChecklistID {
                PixelDoneDock(store: store)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
    }

    private var canCreate: Bool {
        store.selectedChecklistID != PixelDoneProductBaseline.trashChecklistID
    }

    private var emptyTitle: LocalizedStringKey {
        store.selectedChecklistID == PixelDoneProductBaseline.trashChecklistID
            ? "trash_empty"
            : "new_task"
    }

    private var emptySymbol: String {
        store.selectedChecklistID == PixelDoneProductBaseline.trashChecklistID
            ? "trash"
            : "checkmark.square"
    }

    private var emptyDescription: LocalizedStringKey {
        store.selectedChecklistID == PixelDoneProductBaseline.trashChecklistID
            ? "trash_retention"
            : "add_task_to_begin"
    }
}

private struct TodoRowView: View {
    @Bindable var store: PixelDoneStore
    let todo: PixelDoneTodo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await store.send(.toggleTodo(todo.id)) }
            } label: {
                Image(
                    systemName: todo.completed
                        ? "checkmark.square.fill"
                        : "square"
                )
                .font(.title3)
                .foregroundStyle(
                    todo.completed ? .pixelDoneSuccess : todo.priority.color
                )
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                todo.completed
                    ? "Reactivate \(todo.title)"
                    : "Complete \(todo.title)"
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(todo.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(todo.completed)
                    .foregroundStyle(
                        todo.completed ? .secondary : .primary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !todo.completed {
                    HStack(spacing: 8) {
                        Text(todo.priority.localizedName)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(todo.priority.color)

                        if store.snapshot.settings.showDeadlineCountdown {
                            DeadlineLabel(dueAtMillis: todo.dueAtMillis)
                        } else {
                            Text(
                                Date(
                                    timeIntervalSince1970:
                                        Double(todo.dueAtMillis) / 1_000
                                ),
                                format: .dateTime.month(.abbreviated)
                                    .day()
                                    .hour()
                                    .minute()
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if todo.reminderRepeat != .none {
                            Image(systemName: "repeat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(
                                    "Repeats \(todo.reminderRepeat.rawValue.lowercased())"
                                )
                        }
                    }
                }
            }

            if store.selectedChecklistID
                == PixelDoneProductBaseline.trashChecklistID {
                Menu {
                    Button("restore_task", systemImage: "arrow.uturn.backward") {
                        Task { await store.send(.restoreTodo(todo.id)) }
                    }
                    Button(
                        "delete_task",
                        systemImage: "trash.slash",
                        role: .destructive
                    ) {
                        Task {
                            await store.send(.permanentlyDelete(todo.id))
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
            } else {
                Button("Inspect", systemImage: "sidebar.right") {
                    store.inspectedTodoID = todo.id
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
            }
        }
        .padding(14)
        .background(
            todo.id == store.inspectedTodoID
                ? Color.pixelDoneClay.opacity(0.12)
                : Color.primary.opacity(0.035),
            in: .rect(cornerRadius: 4)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(todo.priority.color.opacity(0.75), lineWidth: 1)
        }
        .contentShape(.rect)
        .onTapGesture {
            store.inspectedTodoID = todo.id
        }
        .contextMenu {
            if store.selectedChecklistID
                == PixelDoneProductBaseline.trashChecklistID {
                Button("restore_task", systemImage: "arrow.uturn.backward") {
                    Task { await store.send(.restoreTodo(todo.id)) }
                }
                Button(
                    "delete_task",
                    systemImage: "trash.slash",
                    role: .destructive
                ) {
                    Task { await store.send(.permanentlyDelete(todo.id)) }
                }
            } else {
                Button("edit_task", systemImage: "pencil") {
                    store.editorPresentation = .edit(todo)
                }
                Button(
                    "field_trash",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    Task { await store.send(.moveToTrash(todo.id)) }
                }
            }
        }
    }
}

private struct DeadlineLabel: View {
    let dueAtMillis: Int64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let due = Date(
                timeIntervalSince1970: Double(dueAtMillis) / 1_000
            )
            let interval = due.timeIntervalSince(context.date)
            Text(countdown(interval))
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    interval <= 0 ? Color.pixelDoneError : Color.secondary
                )
        }
    }

    private func countdown(_ interval: TimeInterval) -> String {
        let minutes = Int(abs(interval) / 60)
        let hours = minutes / 60
        let days = hours / 24
        let value: String
        if days > 0 {
            value = "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            value = "\(hours)h \(minutes % 60)m"
        } else {
            value = "\(minutes)m"
        }
        return interval <= 0 ? "OVERDUE \(value)" : value
    }
}
