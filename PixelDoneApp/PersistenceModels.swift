import Foundation
import SwiftData

@Model
final class ChecklistEntity {
    @Attribute(.unique) var localID: String
    var sortIndex: Int
    var name: String
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
    var remoteVersion: Int64?

    init(
        localID: String,
        sortIndex: Int,
        name: String,
        createdAtMillis: Int64,
        updatedAtMillis: Int64,
        remoteVersion: Int64?
    ) {
        self.localID = localID
        self.sortIndex = sortIndex
        self.name = name
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
        self.remoteVersion = remoteVersion
    }
}

@Model
final class TodoEntity {
    @Attribute(.unique) var localID: String
    var checklistID: String
    var sortIndex: Int
    var title: String
    var priority: String
    var dueAtMillis: Int64
    var completed: Bool
    var createdAtMillis: Int64
    var updatedAtMillis: Int64
    var reminderRepeat: String
    var trashedFromChecklistID: String?
    var trashedFromChecklistName: String?
    var trashedAtMillis: Int64?
    var remoteVersion: Int64?
    var attachmentID: String?
    var attachmentObjectPath: String?
    var attachmentSHA256: String?
    var attachmentContentType: String?
    var attachmentByteSize: Int64?
    var attachmentUpdatedAtMillis: Int64?
    var attachmentDeletedAtMillis: Int64?
    var attachmentRemoteVersion: Int64?

    init(
        localID: String,
        checklistID: String,
        sortIndex: Int,
        title: String,
        priority: String,
        dueAtMillis: Int64,
        completed: Bool,
        createdAtMillis: Int64,
        updatedAtMillis: Int64,
        reminderRepeat: String,
        trashedFromChecklistID: String?,
        trashedFromChecklistName: String?,
        trashedAtMillis: Int64?,
        remoteVersion: Int64?,
        attachmentID: String?,
        attachmentObjectPath: String?,
        attachmentSHA256: String?,
        attachmentContentType: String?,
        attachmentByteSize: Int64?,
        attachmentUpdatedAtMillis: Int64?,
        attachmentDeletedAtMillis: Int64?,
        attachmentRemoteVersion: Int64?
    ) {
        self.localID = localID
        self.checklistID = checklistID
        self.sortIndex = sortIndex
        self.title = title
        self.priority = priority
        self.dueAtMillis = dueAtMillis
        self.completed = completed
        self.createdAtMillis = createdAtMillis
        self.updatedAtMillis = updatedAtMillis
        self.reminderRepeat = reminderRepeat
        self.trashedFromChecklistID = trashedFromChecklistID
        self.trashedFromChecklistName = trashedFromChecklistName
        self.trashedAtMillis = trashedAtMillis
        self.remoteVersion = remoteVersion
        self.attachmentID = attachmentID
        self.attachmentObjectPath = attachmentObjectPath
        self.attachmentSHA256 = attachmentSHA256
        self.attachmentContentType = attachmentContentType
        self.attachmentByteSize = attachmentByteSize
        self.attachmentUpdatedAtMillis = attachmentUpdatedAtMillis
        self.attachmentDeletedAtMillis = attachmentDeletedAtMillis
        self.attachmentRemoteVersion = attachmentRemoteVersion
    }
}

@Model
final class SettingsEntity {
    @Attribute(.unique) var localID: String
    var selectedChecklistID: String
    var sortMode: String
    var languageMode: String
    var appearanceMode: String
    var dockPlacement: String
    var dockActionsCSV: String
    var showDeadlineCountdown: Bool
    var hideCompleted: Bool
    var quickDelete: Bool

    init(
        selectedChecklistID: String,
        sortMode: String,
        languageMode: String,
        appearanceMode: String,
        dockPlacement: String,
        dockActionsCSV: String,
        showDeadlineCountdown: Bool,
        hideCompleted: Bool,
        quickDelete: Bool
    ) {
        localID = "settings"
        self.selectedChecklistID = selectedChecklistID
        self.sortMode = sortMode
        self.languageMode = languageMode
        self.appearanceMode = appearanceMode
        self.dockPlacement = dockPlacement
        self.dockActionsCSV = dockActionsCSV
        self.showDeadlineCountdown = showDeadlineCountdown
        self.hideCompleted = hideCompleted
        self.quickDelete = quickDelete
    }
}

@Model
final class TombstoneEntity {
    @Attribute(.unique) var compoundID: String
    var recordType: String
    var localID: String
    var deletedAtMillis: Int64
    var remoteVersion: Int64?

    init(
        compoundID: String,
        recordType: String,
        localID: String,
        deletedAtMillis: Int64,
        remoteVersion: Int64?
    ) {
        self.compoundID = compoundID
        self.recordType = recordType
        self.localID = localID
        self.deletedAtMillis = deletedAtMillis
        self.remoteVersion = remoteVersion
    }
}

@Model
final class OutboxEntity {
    @Attribute(.unique) var mutationUUID: String
    var reason: String
    var payload: Data
    var createdAtMillis: Int64
    var state: String

    init(
        mutationUUID: String,
        reason: String,
        payload: Data,
        createdAtMillis: Int64,
        state: String = "pending"
    ) {
        self.mutationUUID = mutationUUID
        self.reason = reason
        self.payload = payload
        self.createdAtMillis = createdAtMillis
        self.state = state
    }
}

@Model
final class SyncMetadataEntity {
    @Attribute(.unique) var localID: String
    var cursor: Int64
    var schemaVersion: String
    var lastSyncAtMillis: Int64?

    init(
        cursor: Int64 = 0,
        schemaVersion: String,
        lastSyncAtMillis: Int64? = nil
    ) {
        localID = "sync"
        self.cursor = cursor
        self.schemaVersion = schemaVersion
        self.lastSyncAtMillis = lastSyncAtMillis
    }
}
