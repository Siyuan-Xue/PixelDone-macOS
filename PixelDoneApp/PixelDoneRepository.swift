import Foundation
import PixelDoneDomain
import PixelDoneSyncContract
import SwiftData

enum PixelDonePersistence {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            ChecklistEntity.self,
            TodoEntity.self,
            SettingsEntity.self,
            TombstoneEntity.self,
            OutboxEntity.self,
            SyncMetadataEntity.self,
        ])
        let configuration = ModelConfiguration(
            "PixelDoneLocal",
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("PixelDone SwiftData container failed: \(error)")
        }
    }
}

@ModelActor
actor PixelDoneRepository {
    func loadOrBootstrap(nowMillis: Int64) throws -> PixelDoneSnapshot {
        if let snapshot = try loadSnapshot() {
            return snapshot
        }

        let snapshot = Self.starterSnapshot(nowMillis: nowMillis)
        try persist(snapshot, reason: "bootstrap", enqueueMutation: false)
        return snapshot
    }

    func loadSnapshot() throws -> PixelDoneSnapshot? {
        let checklistEntities = try modelContext.fetch(
            FetchDescriptor<ChecklistEntity>()
        )
        guard !checklistEntities.isEmpty else {
            return nil
        }

        let todoEntities = try modelContext.fetch(FetchDescriptor<TodoEntity>())
        let tombstoneEntities = try modelContext.fetch(
            FetchDescriptor<TombstoneEntity>()
        )
        let settingsEntity = try modelContext.fetch(
            FetchDescriptor<SettingsEntity>()
        ).first

        let checklists = checklistEntities.map {
            PixelDoneChecklist(
                id: $0.localID,
                sortIndex: $0.sortIndex,
                name: $0.name,
                createdAtMillis: $0.createdAtMillis,
                updatedAtMillis: $0.updatedAtMillis,
                remoteVersion: $0.remoteVersion
            )
        }
        let todos = todoEntities.compactMap(Self.makeTodo)
        let tombstones = tombstoneEntities.compactMap { entity in
            TombstoneRecordType(rawValue: entity.recordType).map {
                PixelDoneTombstone(
                    recordType: $0,
                    localID: entity.localID,
                    deletedAtMillis: entity.deletedAtMillis,
                    remoteVersion: entity.remoteVersion
                )
            }
        }

        return PixelDoneSnapshot(
            checklists: checklists,
            todos: todos,
            tombstones: tombstones,
            settings: Self.makeSettings(settingsEntity)
        )
    }

    func persist(
        _ snapshot: PixelDoneSnapshot,
        reason: String,
        enqueueMutation: Bool = true
    ) throws {
        for entity in try modelContext.fetch(FetchDescriptor<ChecklistEntity>()) {
            modelContext.delete(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<TodoEntity>()) {
            modelContext.delete(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<SettingsEntity>()) {
            modelContext.delete(entity)
        }
        for entity in try modelContext.fetch(FetchDescriptor<TombstoneEntity>()) {
            modelContext.delete(entity)
        }

        for checklist in snapshot.checklists {
            modelContext.insert(
                ChecklistEntity(
                    localID: checklist.id,
                    sortIndex: checklist.sortIndex,
                    name: checklist.name,
                    createdAtMillis: checklist.createdAtMillis,
                    updatedAtMillis: checklist.updatedAtMillis,
                    remoteVersion: checklist.remoteVersion
                )
            )
        }
        for todo in snapshot.todos {
            let attachment = todo.attachment
            modelContext.insert(
                TodoEntity(
                    localID: todo.id,
                    checklistID: todo.checklistID,
                    sortIndex: todo.sortIndex,
                    title: todo.title,
                    priority: todo.priority.rawValue,
                    dueAtMillis: todo.dueAtMillis,
                    completed: todo.completed,
                    createdAtMillis: todo.createdAtMillis,
                    updatedAtMillis: todo.updatedAtMillis,
                    reminderRepeat: todo.reminderRepeat.rawValue,
                    trashedFromChecklistID: todo.trashedFromChecklistID,
                    trashedFromChecklistName: todo.trashedFromChecklistName,
                    trashedAtMillis: todo.trashedAtMillis,
                    remoteVersion: todo.remoteVersion,
                    attachmentID: attachment?.attachmentID,
                    attachmentObjectPath: attachment?.objectPath,
                    attachmentSHA256: attachment?.contentSHA256,
                    attachmentContentType: attachment?.contentType,
                    attachmentByteSize: attachment?.byteSize,
                    attachmentUpdatedAtMillis: attachment?.updatedAtMillis,
                    attachmentDeletedAtMillis: attachment?.deletedAtMillis,
                    attachmentRemoteVersion: attachment?.remoteVersion
                )
            )
        }

        let settings = snapshot.settings
        modelContext.insert(
            SettingsEntity(
                selectedChecklistID: settings.selectedChecklistID,
                sortMode: settings.sortMode.rawValue,
                languageMode: settings.languageMode.rawValue,
                appearanceMode: settings.appearanceMode.rawValue,
                dockPlacement: settings.dock.plusPlacement.rawValue,
                dockActionsCSV: settings.dock.actions.map(\.rawValue).joined(
                    separator: ","
                ),
                showDeadlineCountdown: settings.showDeadlineCountdown,
                hideCompleted: settings.hideCompleted,
                quickDelete: settings.quickDelete
            )
        )

        for tombstone in snapshot.tombstones {
            modelContext.insert(
                TombstoneEntity(
                    compoundID: tombstone.id,
                    recordType: tombstone.recordType.rawValue,
                    localID: tombstone.localID,
                    deletedAtMillis: tombstone.deletedAtMillis,
                    remoteVersion: tombstone.remoteVersion
                )
            )
        }

        if enqueueMutation {
            modelContext.insert(
                OutboxEntity(
                    mutationUUID: UUID().uuidString.lowercased(),
                    reason: reason,
                    payload: try JSONEncoder().encode(snapshot),
                    createdAtMillis: Self.nowMillis
                )
            )
        }

        try modelContext.save()
    }

    private static func makeTodo(_ entity: TodoEntity) -> PixelDoneTodo? {
        guard let priority = TodoPriority(rawValue: entity.priority),
              let reminderRepeat = ReminderRepeat(
                rawValue: entity.reminderRepeat
              ) else {
            return nil
        }

        let attachment: PixelDoneAttachment?
        if let updatedAtMillis = entity.attachmentUpdatedAtMillis {
            attachment = PixelDoneAttachment(
                todoLocalID: entity.localID,
                attachmentID: entity.attachmentID,
                objectPath: entity.attachmentObjectPath,
                contentSHA256: entity.attachmentSHA256,
                contentType: entity.attachmentContentType,
                byteSize: entity.attachmentByteSize,
                updatedAtMillis: updatedAtMillis,
                deletedAtMillis: entity.attachmentDeletedAtMillis,
                remoteVersion: entity.attachmentRemoteVersion
            )
        } else {
            attachment = nil
        }

        return PixelDoneTodo(
            id: entity.localID,
            checklistID: entity.checklistID,
            sortIndex: entity.sortIndex,
            title: entity.title,
            priority: priority,
            dueAtMillis: entity.dueAtMillis,
            completed: entity.completed,
            createdAtMillis: entity.createdAtMillis,
            updatedAtMillis: entity.updatedAtMillis,
            reminderRepeat: reminderRepeat,
            trashedFromChecklistID: entity.trashedFromChecklistID,
            trashedFromChecklistName: entity.trashedFromChecklistName,
            trashedAtMillis: entity.trashedAtMillis,
            remoteVersion: entity.remoteVersion,
            attachment: attachment
        )
    }

    private static func makeSettings(_ entity: SettingsEntity?) -> PixelDoneSettings {
        guard let entity else {
            return PixelDoneSettings()
        }
        let actions = entity.dockActionsCSV
            .split(separator: ",")
            .compactMap { DockAction(rawValue: String($0)) }

        return PixelDoneSettings(
            selectedChecklistID: entity.selectedChecklistID,
            sortMode: TodoSortMode(rawValue: entity.sortMode) ?? .priority,
            languageMode: LanguageMode(rawValue: entity.languageMode) ?? .system,
            appearanceMode: AppearanceMode(rawValue: entity.appearanceMode) ?? .light,
            dock: PixelDoneDockConfiguration(
                plusPlacement: DockPlacement(
                    rawValue: entity.dockPlacement
                ) ?? .center,
                actions: actions
            ),
            showDeadlineCountdown: entity.showDeadlineCountdown,
            hideCompleted: entity.hideCompleted,
            quickDelete: entity.quickDelete
        )
    }

    private static func starterSnapshot(nowMillis: Int64) -> PixelDoneSnapshot {
        let day: Int64 = 86_400_000
        return PixelDoneSnapshot(
            checklists: [
                PixelDoneChecklist(
                    id: PixelDoneProductBaseline.defaultChecklistID,
                    sortIndex: 0,
                    name: "MAIN",
                    createdAtMillis: nowMillis,
                    updatedAtMillis: nowMillis
                ),
                PixelDoneChecklist(
                    id: "personal",
                    sortIndex: 1,
                    name: "PERSONAL",
                    createdAtMillis: nowMillis,
                    updatedAtMillis: nowMillis
                ),
                PixelDoneChecklist(
                    id: PixelDoneProductBaseline.trashChecklistID,
                    sortIndex: 10_000,
                    name: "TRASH",
                    createdAtMillis: nowMillis,
                    updatedAtMillis: nowMillis
                ),
                PixelDoneChecklist(
                    id: PixelDoneProductBaseline.settingsChecklistID,
                    sortIndex: 10_001,
                    name: "SETTINGS",
                    createdAtMillis: nowMillis,
                    updatedAtMillis: nowMillis
                ),
            ],
            todos: [
                PixelDoneTodo(
                    id: UUID().uuidString.lowercased(),
                    checklistID: PixelDoneProductBaseline.defaultChecklistID,
                    sortIndex: 0,
                    title: "Explore the Apple-native PixelDone",
                    priority: .xHigh,
                    dueAtMillis: nowMillis + day,
                    createdAtMillis: nowMillis,
                    updatedAtMillis: nowMillis
                ),
                PixelDoneTodo(
                    id: UUID().uuidString.lowercased(),
                    checklistID: PixelDoneProductBaseline.defaultChecklistID,
                    sortIndex: 1,
                    title: "Create your first checklist",
                    priority: .medium,
                    dueAtMillis: nowMillis + (day * 2),
                    createdAtMillis: nowMillis,
                    updatedAtMillis: nowMillis
                ),
            ]
        )
    }

    private static var nowMillis: Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
}
