import Foundation
import Observation
import PixelDoneDesignFoundation
import PixelDoneDomain
import SwiftUI

struct TodoDraft: Equatable, Sendable {
    var title = ""
    var priority: TodoPriority = .medium
    var dueDate = Date().addingTimeInterval(86_400)
    var reminderRepeat: ReminderRepeat = .none
}

enum EditorPresentation: Identifiable, Equatable {
    case create
    case edit(PixelDoneTodo)

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(todo): todo.id
        }
    }
}

enum PixelDoneIntent: Sendable {
    case selectChecklist(String)
    case createChecklist(String)
    case renameChecklist(id: String, name: String)
    case deleteChecklist(String)
    case createTodo(TodoDraft)
    case updateTodo(id: String, draft: TodoDraft)
    case toggleTodo(String)
    case moveToTrash(String)
    case restoreTodo(String)
    case permanentlyDelete(String)
    case setSortMode(TodoSortMode)
    case setAppearance(AppearanceMode)
    case setLanguage(LanguageMode)
    case setDockPlacement(DockPlacement)
    case setDockActions([DockAction])
    case toggleDeadline
    case toggleHideCompleted
    case toggleQuickDelete
    case cleanCompleted
}

@MainActor
@Observable
final class PixelDoneStore {
    private let repository: PixelDoneRepository
    private var completionHoldTask: Task<Void, Never>?
    private var heldTodoOrder: [String] = []

    var snapshot = PixelDoneSnapshot(checklists: [], todos: [])
    var isLoaded = false
    var isWorking = false
    var editorPresentation: EditorPresentation?
    var inspectedTodoID: String?
    var highlightedTodoID: String?
    var notice: String?
    var errorMessage: String?

    init(repository: PixelDoneRepository) {
        self.repository = repository
    }

    var selectedChecklistID: String {
        snapshot.settings.selectedChecklistID
    }

    var selectedChecklist: PixelDoneChecklist? {
        snapshot.checklists.first { $0.id == selectedChecklistID }
    }

    var inspectedTodo: PixelDoneTodo? {
        snapshot.todos.first { $0.id == inspectedTodoID }
    }

    var ordinaryChecklists: [PixelDoneChecklist] {
        snapshot.checklists
            .filter { !ChecklistRules.isFixed($0.id) }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var visibleTodos: [PixelDoneTodo] {
        var todos = snapshot.todos.filter { $0.checklistID == selectedChecklistID }
        if snapshot.settings.hideCompleted {
            todos.removeAll(where: \.completed)
        }
        let sorted = TodoSortRules.sorted(
            todos,
            mode: snapshot.settings.sortMode
        )
        guard !heldTodoOrder.isEmpty else {
            return sorted
        }
        let order = Dictionary(
            uniqueKeysWithValues: heldTodoOrder.enumerated().map { ($1, $0) }
        )
        return sorted.sorted {
            (order[$0.id] ?? .max) < (order[$1.id] ?? .max)
        }
    }

    var preferredColorScheme: ColorScheme {
        snapshot.settings.appearanceMode == .dark ? .dark : .light
    }

    func load() async {
        guard !isLoaded else {
            return
        }
        isWorking = true
        defer {
            isWorking = false
            isLoaded = true
        }

        do {
            let now = Self.nowMillis
            var loaded = try await repository.loadOrBootstrap(nowMillis: now)
            let expiredIDs = Set(
                TrashRules.expiredTodos(
                    in: loaded.todos,
                    nowMillis: now
                ).map(\.id)
            )
            if !expiredIDs.isEmpty {
                loaded.todos.removeAll { expiredIDs.contains($0.id) }
                for id in expiredIDs {
                    loaded.tombstones.append(
                        PixelDoneTombstone(
                            recordType: .item,
                            localID: id,
                            deletedAtMillis: now
                        )
                    )
                }
                try await repository.persist(
                    loaded,
                    reason: "trash-retention"
                )
            }
            snapshot = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ intent: PixelDoneIntent) async {
        guard !isWorking else {
            return
        }

        var proposed = snapshot
        let now = Self.nowMillis
        var reason = "settings"
        var nextHighlight: String?

        switch intent {
        case let .selectChecklist(id):
            proposed.settings.selectedChecklistID = id
            inspectedTodoID = nil
            reason = "select-checklist"

        case let .createChecklist(rawName):
            let name = rawName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !name.isEmpty else { return }
            let id = UUID().uuidString.lowercased()
            proposed.checklists.append(
                PixelDoneChecklist(
                    id: id,
                    sortIndex: proposed.checklists.count,
                    name: name.uppercased(),
                    createdAtMillis: now,
                    updatedAtMillis: now
                )
            )
            proposed.settings.selectedChecklistID = id
            reason = "create-checklist"

        case let .renameChecklist(id, rawName):
            guard !ChecklistRules.isFixed(id),
                  let index = proposed.checklists.firstIndex(
                    where: { $0.id == id }
                  ) else {
                return
            }
            let name = rawName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !name.isEmpty else { return }
            proposed.checklists[index].name = name.uppercased()
            proposed.checklists[index].updatedAtMillis = now
            reason = "rename-checklist"

        case let .deleteChecklist(id):
            guard ChecklistRules.canDelete(
                checklistID: id,
                from: proposed.checklists
            ) else {
                notice = "At least one ordinary checklist must remain."
                return
            }
            proposed.checklists.removeAll { $0.id == id }
            proposed.todos.removeAll { $0.checklistID == id }
            proposed.tombstones.append(
                PixelDoneTombstone(
                    recordType: .checklist,
                    localID: id,
                    deletedAtMillis: now
                )
            )
            proposed.settings.selectedChecklistID =
                PixelDoneProductBaseline.defaultChecklistID
            reason = "delete-checklist"

        case let .createTodo(draft):
            let title = draft.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !title.isEmpty,
                  selectedChecklistID
                    != PixelDoneProductBaseline.trashChecklistID,
                  selectedChecklistID
                    != PixelDoneProductBaseline.settingsChecklistID else {
                return
            }
            let id = UUID().uuidString.lowercased()
            proposed.todos.append(
                PixelDoneTodo(
                    id: id,
                    checklistID: selectedChecklistID,
                    sortIndex: proposed.todos.count,
                    title: title,
                    priority: draft.priority,
                    dueAtMillis: Self.millis(from: draft.dueDate),
                    createdAtMillis: now,
                    updatedAtMillis: now,
                    reminderRepeat: draft.reminderRepeat
                )
            )
            reason = "create-todo"
            nextHighlight = id

        case let .updateTodo(id, draft):
            guard let index = proposed.todos.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            let title = draft.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !title.isEmpty else { return }
            proposed.todos[index].title = title
            proposed.todos[index].priority = draft.priority
            proposed.todos[index].dueAtMillis = Self.millis(
                from: draft.dueDate
            )
            proposed.todos[index].reminderRepeat = draft.reminderRepeat
            proposed.todos[index].updatedAtMillis = now
            reason = "update-todo"
            nextHighlight = id

        case let .toggleTodo(id):
            guard let index = proposed.todos.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            heldTodoOrder = visibleTodos.map(\.id)
            proposed.todos[index].completed.toggle()
            proposed.todos[index].updatedAtMillis = now
            reason = proposed.todos[index].completed
                ? "complete-todo"
                : "reactivate-todo"
            nextHighlight = id

        case let .moveToTrash(id):
            guard let index = proposed.todos.firstIndex(
                where: { $0.id == id }
            ),
            let origin = proposed.checklists.first(
                where: { $0.id == proposed.todos[index].checklistID }
            ) else {
                return
            }
            proposed.todos[index].trashedFromChecklistID = origin.id
            proposed.todos[index].trashedFromChecklistName = origin.name
            proposed.todos[index].trashedAtMillis = now
            proposed.todos[index].checklistID =
                PixelDoneProductBaseline.trashChecklistID
            proposed.todos[index].updatedAtMillis = now
            inspectedTodoID = nil
            reason = "trash-todo"

        case let .restoreTodo(id):
            guard let index = proposed.todos.firstIndex(
                where: { $0.id == id }
            ) else {
                return
            }
            let originID = proposed.todos[index].trashedFromChecklistID
                ?? PixelDoneProductBaseline.defaultChecklistID
            if !proposed.checklists.contains(where: { $0.id == originID }) {
                proposed.checklists.append(
                    PixelDoneChecklist(
                        id: originID,
                        sortIndex: proposed.checklists.count,
                        name: proposed.todos[index]
                            .trashedFromChecklistName ?? "RESTORED",
                        createdAtMillis: now,
                        updatedAtMillis: now
                    )
                )
            }
            proposed.todos[index].checklistID = originID
            proposed.todos[index].trashedFromChecklistID = nil
            proposed.todos[index].trashedFromChecklistName = nil
            proposed.todos[index].trashedAtMillis = nil
            proposed.todos[index].updatedAtMillis = now
            inspectedTodoID = nil
            reason = "restore-todo"
            nextHighlight = id

        case let .permanentlyDelete(id):
            proposed.todos.removeAll { $0.id == id }
            proposed.tombstones.append(
                PixelDoneTombstone(
                    recordType: .item,
                    localID: id,
                    deletedAtMillis: now
                )
            )
            inspectedTodoID = nil
            reason = "purge-todo"

        case let .setSortMode(mode):
            proposed.settings.sortMode = mode
            reason = "sort-mode"

        case let .setAppearance(mode):
            proposed.settings.appearanceMode = mode
            reason = "appearance"

        case let .setLanguage(mode):
            proposed.settings.languageMode = mode
            reason = "language"

        case let .setDockPlacement(placement):
            proposed.settings.dock.plusPlacement = placement
            reason = "dock-placement"

        case let .setDockActions(actions):
            proposed.settings.dock.actions = Array(actions.prefix(4))
            reason = "dock-actions"

        case .toggleDeadline:
            proposed.settings.showDeadlineCountdown.toggle()
            reason = "deadline-mode"

        case .toggleHideCompleted:
            proposed.settings.hideCompleted.toggle()
            reason = "hide-completed"

        case .toggleQuickDelete:
            proposed.settings.quickDelete.toggle()
            reason = "quick-delete"

        case .cleanCompleted:
            let visibleIDs = Set(visibleTodos.filter(\.completed).map(\.id))
            for index in proposed.todos.indices
                where visibleIDs.contains(proposed.todos[index].id) {
                proposed.todos[index].trashedFromChecklistID =
                    selectedChecklist?.id
                proposed.todos[index].trashedFromChecklistName =
                    selectedChecklist?.name
                proposed.todos[index].trashedAtMillis = now
                proposed.todos[index].checklistID =
                    PixelDoneProductBaseline.trashChecklistID
                proposed.todos[index].updatedAtMillis = now
            }
            reason = "clean-completed"
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.persist(proposed, reason: reason)
            snapshot = proposed
            highlightedTodoID = nextHighlight
            if reason == "complete-todo" || reason == "reactivate-todo" {
                completionHoldTask?.cancel()
                completionHoldTask = Task { [weak self] in
                    try? await Task.sleep(
                        for: .milliseconds(
                            PixelDoneDesignFoundation.completedHoldMilliseconds
                        )
                    )
                    guard !Task.isCancelled else { return }
                    self?.heldTodoOrder = []
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func draft(for presentation: EditorPresentation) -> TodoDraft {
        switch presentation {
        case .create:
            TodoDraft()
        case let .edit(todo):
            TodoDraft(
                title: todo.title,
                priority: todo.priority,
                dueDate: Date(
                    timeIntervalSince1970: Double(todo.dueAtMillis) / 1_000
                ),
                reminderRepeat: todo.reminderRepeat
            )
        }
    }

    private static var nowMillis: Int64 {
        millis(from: Date())
    }

    private static func millis(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
