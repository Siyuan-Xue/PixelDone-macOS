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
    var attachment: NormalizedAttachment?
    var removeAttachment = false
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
    private let notificationService: PixelDoneNotificationService?
    private let attachmentService: PixelDoneAttachmentService?
    private var completionHoldTask: Task<Void, Never>?
    private var heldTodoOrder: [String] = []
    let cloud: CloudCoordinator

    var snapshot = PixelDoneSnapshot(checklists: [], todos: [])
    var isLoaded = false
    var isWorking = false
    var editorPresentation: EditorPresentation?
    var inspectedTodoID: String?
    var highlightedTodoID: String?
    var notice: String?
    var errorMessage: String?
    var notificationStatus = "Not requested"

    init(
        repository: PixelDoneRepository,
        notificationService: PixelDoneNotificationService? = nil,
        attachmentService: PixelDoneAttachmentService? = nil,
        cloudCoordinator: CloudCoordinator? = nil
    ) {
        self.repository = repository
        self.notificationService = notificationService
        self.attachmentService = attachmentService
        cloud = cloudCoordinator ?? CloudCoordinator(
            configuration: nil,
            bundleIdentifier: "com.milesxue.pixeldone.macos.tests"
        )
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

    var appLocale: Locale {
        switch snapshot.settings.languageMode {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .arabic: Locale(identifier: "ar")
        case .french: Locale(identifier: "fr")
        case .russian: Locale(identifier: "ru")
        case .spanish: Locale(identifier: "es")
        }
    }

    var appLayoutDirection: LayoutDirection {
        snapshot.settings.languageMode == .arabic
            ? .rightToLeft
            : .leftToRight
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
            cloud.setInvalidationHandler { [weak self] in
                await self?.synchronizeCloud()
            }
            await cloud.restoreSession()
            if let notificationService {
                await notificationService.configureCategories()
                await notificationService.synchronize(todos: loaded.todos)
                await refreshNotificationStatus()
            }
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
            let attachment = await makeAttachment(
                from: draft.attachment,
                todoID: id,
                nowMillis: now
            )
            if draft.attachment != nil && attachment == nil {
                return
            }
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
                    reminderRepeat: draft.reminderRepeat,
                    attachment: attachment
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
            if let normalized = draft.attachment {
                guard let attachment = await makeAttachment(
                    from: normalized,
                    todoID: id,
                    nowMillis: now
                ) else {
                    return
                }
                proposed.todos[index].attachment = attachment
            } else if draft.removeAttachment,
                      proposed.todos[index].attachment != nil {
                proposed.todos[index].attachment = PixelDoneAttachment(
                    todoLocalID: id,
                    updatedAtMillis: now,
                    deletedAtMillis: now
                )
            }
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
            if cloud.isConfigured {
                cloud.needsSync = true
            }
            await notificationService?.synchronize(todos: proposed.todos)
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

    private func makeAttachment(
        from normalized: NormalizedAttachment?,
        todoID: String,
        nowMillis: Int64
    ) async -> PixelDoneAttachment? {
        guard let normalized else {
            return nil
        }
        guard let attachmentService else {
            errorMessage = AttachmentError.normalizationFailed
                .localizedDescription
            return nil
        }
        let attachmentID = UUID().uuidString.lowercased()
        do {
            _ = try await attachmentService.storeLocally(
                normalized,
                attachmentID: attachmentID
            )
            return PixelDoneAttachment(
                todoLocalID: todoID,
                attachmentID: attachmentID,
                contentSHA256: normalized.contentSHA256,
                contentType: normalized.contentType,
                byteSize: normalized.byteSize,
                updatedAtMillis: nowMillis
            )
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func requestNotificationAuthorization() async {
        guard let notificationService else {
            notificationStatus = "Unavailable"
            return
        }
        do {
            _ = try await notificationService.requestAuthorization()
            await refreshNotificationStatus()
            await notificationService.synchronize(todos: snapshot.todos)
        } catch {
            notificationStatus = "Unavailable"
            errorMessage = error.localizedDescription
        }
    }

    func snoozeNotification(todoID: String) async {
        guard let todo = snapshot.todos.first(
            where: { $0.id == todoID }
        ), let notificationService else {
            return
        }
        do {
            try await notificationService.snooze(todo: todo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func synchronizeCloud() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let mutationUUID = try await repository.pendingMutationUUID()
            guard let merged = await cloud.synchronize(
                snapshot: snapshot,
                mutationUUID: mutationUUID
            ) else {
                return
            }
            try await repository.persist(
                merged,
                reason: "remote-sync",
                enqueueMutation: false
            )
            try await repository.acknowledgePendingMutations()
            snapshot = merged
            await notificationService?.synchronize(todos: merged.todos)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resolveCloudConflicts(keepingDevice: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let resolved = await cloud.resolveConflicts(
            keepingDevice: keepingDevice,
            localSnapshot: snapshot
        ) else {
            return
        }
        do {
            try await repository.persist(
                resolved,
                reason: "resolve-conflicts",
                enqueueMutation: false
            )
            try await repository.acknowledgePendingMutations()
            snapshot = resolved
            await notificationService?.synchronize(todos: resolved.todos)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func attachmentData(for todo: PixelDoneTodo) async -> Data? {
        guard let attachmentService,
              let attachmentID = todo.attachment?.attachmentID,
              todo.attachment?.deletedAtMillis == nil else {
            return nil
        }
        return try? await attachmentService.loadLocalData(
            attachmentID: attachmentID
        )
    }

    private func refreshNotificationStatus() async {
        guard let notificationService else {
            notificationStatus = "Unavailable"
            return
        }
        switch await notificationService.authorizationState() {
        case .notDetermined:
            notificationStatus = "Not requested"
        case .denied:
            notificationStatus = "Denied"
        case .authorized:
            notificationStatus = "Authorized"
        case .provisional:
            notificationStatus = "Provisional"
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
