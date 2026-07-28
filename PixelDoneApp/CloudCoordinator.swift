import Foundation
import Observation
import PixelDoneDomain
import PixelDoneSyncContract

enum CloudStatus: Equatable, Sendable {
    case localOnly
    case signedOut
    case idle
    case syncing
    case retrying
    case authenticationExpired
    case updateRequired(String)
    case storageError

    var label: String {
        switch self {
        case .localOnly: "Local only"
        case .signedOut: "Signed out"
        case .idle: "Idle"
        case .syncing: "Syncing"
        case .retrying: "Retrying"
        case .authenticationExpired: "Authentication expired"
        case let .updateRequired(version): "Update required (\(version))"
        case .storageError: "Local storage error"
        }
    }
}

@MainActor
@Observable
final class CloudCoordinator {
    private let keychain: KeychainSessionStore
    private let client: SupabaseHTTPClient?
    private let attachmentService: PixelDoneAttachmentService?
    private var realtimeTask: Task<Void, Never>?
    private var invalidationDebounceTask: Task<Void, Never>?
    @ObservationIgnored private var invalidationHandler:
        (@MainActor @Sendable () async -> Void)?
    private var pendingCleanedImagePaths: [String] = []
    private var conflictRemoteSnapshot: PixelDoneSnapshot?

    var session: SupabaseSession?
    var status: CloudStatus
    var conflicts: [SyncConflict] = []
    var errorMessage: String?
    var needsSync = false

    init(
        configuration: SupabaseConfiguration?,
        bundleIdentifier: String,
        attachmentService: PixelDoneAttachmentService? = nil
    ) {
        keychain = KeychainSessionStore(
            bundleIdentifier: bundleIdentifier
        )
        client = configuration.map {
            SupabaseHTTPClient(configuration: $0)
        }
        self.attachmentService = attachmentService
        status = configuration == nil ? .localOnly : .signedOut
    }

    var isConfigured: Bool {
        client != nil
    }

    func setInvalidationHandler(
        _ handler: @escaping @MainActor @Sendable () async -> Void
    ) {
        invalidationHandler = handler
    }

    func restoreSession() async {
        guard client != nil else {
            status = .localOnly
            return
        }
        do {
            session = try await keychain.load()
            status = session == nil ? .signedOut : .idle
            if session != nil {
                startRealtime()
            }
        } catch {
            status = .storageError
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        await authenticate(email: email, password: password, register: false)
    }

    func register(email: String, password: String) async {
        await authenticate(email: email, password: password, register: true)
    }

    func signOut() async {
        guard let client, let session else {
            try? await keychain.clear()
            self.session = nil
            status = isConfigured ? .signedOut : .localOnly
            return
        }
        do {
            try await client.signOutGlobally(session: session)
            try await keychain.clear()
            self.session = nil
            conflicts = []
            realtimeTask?.cancel()
            invalidationDebounceTask?.cancel()
            await client.stopRealtime()
            status = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func changePassword(
        currentPassword: String,
        newPassword: String
    ) async {
        guard let client, let session, let email = session.email else {
            errorMessage = "Sign in before changing the password."
            return
        }
        status = .syncing
        do {
            let verified = try await client.signIn(
                email: email,
                password: currentPassword
            )
            try await client.changePassword(
                to: newPassword,
                session: verified
            )
            try await client.signOutGlobally(session: verified)
            try await keychain.clear()
            self.session = nil
            status = .signedOut
            errorMessage =
                "Password changed. Supabase signed out every session."
        } catch {
            status = .idle
            errorMessage = error.localizedDescription
        }
    }

    func synchronize(
        snapshot: PixelDoneSnapshot,
        mutationUUID: String?
    ) async -> PixelDoneSnapshot? {
        guard let client else {
            status = .localOnly
            return nil
        }
        guard var activeSession = session else {
            status = .signedOut
            return nil
        }
        status = .syncing

        do {
            if activeSession.needsRefresh {
                activeSession = try await client.refresh(
                    activeSession.refreshToken
                )
                try await keychain.save(activeSession)
                session = activeSession
            }

            let preparedSnapshot = try await uploadPendingAttachments(
                in: snapshot,
                userID: activeSession.userID,
                client: client,
                session: activeSession
            )
            if mutationUUID != nil || !pendingCleanedImagePaths.isEmpty {
                let response = try await client.apply(
                    Self.makeMutation(
                        snapshot: preparedSnapshot,
                        userID: activeSession.userID,
                        mutationUUID: mutationUUID ?? UUID().uuidString,
                        cleanedImagePaths: pendingCleanedImagePaths
                    ),
                    session: activeSession
                )
                conflicts = response.conflicts
                if conflicts.isEmpty {
                    pendingCleanedImagePaths = []
                }
            }

            let response = try await client.pull(
                sinceVersion: 0,
                session: activeSession
            )
            let merged = Self.makeSnapshot(
                from: response,
                preserving: snapshot.settings
            )
            await cacheRemoteAttachments(
                from: response,
                client: client,
                session: activeSession
            )
            let cleaned = await deleteCleanupObjects(
                response.imageCleanupPaths,
                client: client,
                session: activeSession
            )
            pendingCleanedImagePaths.append(
                contentsOf: cleaned.filter {
                    !pendingCleanedImagePaths.contains($0)
                }
            )
            if !conflicts.isEmpty {
                conflictRemoteSnapshot = merged
                status = .idle
                needsSync = false
                return nil
            }
            conflictRemoteSnapshot = nil
            status = .idle
            needsSync = !pendingCleanedImagePaths.isEmpty
            return merged
        } catch let error as SupabaseClientError {
            switch error {
            case let .schemaUpdateRequired(version):
                status = .updateRequired(version)
            case .requestFailed(status: 401):
                status = .authenticationExpired
            default:
                status = .retrying
            }
            errorMessage = error.localizedDescription
            return nil
        } catch {
            status = .retrying
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func resolveConflicts(
        keepingDevice: Bool,
        localSnapshot: PixelDoneSnapshot
    ) async -> PixelDoneSnapshot? {
        guard let client, let activeSession = session,
              let remoteSnapshot = conflictRemoteSnapshot else {
            return nil
        }
        if !keepingDevice {
            conflicts = []
            conflictRemoteSnapshot = nil
            status = .idle
            needsSync = false
            return remoteSnapshot
        }

        status = .syncing
        do {
            let rebased = Self.rebase(
                local: localSnapshot,
                remote: remoteSnapshot,
                conflicts: conflicts
            )
            let prepared = try await uploadPendingAttachments(
                in: rebased,
                userID: activeSession.userID,
                client: client,
                session: activeSession
            )
            let result = try await client.apply(
                Self.makeMutation(
                    snapshot: prepared,
                    userID: activeSession.userID,
                    mutationUUID: UUID().uuidString,
                    cleanedImagePaths: pendingCleanedImagePaths
                ),
                session: activeSession
            )
            conflicts = result.conflicts
            guard conflicts.isEmpty else {
                status = .idle
                return nil
            }
            pendingCleanedImagePaths = []
            let response = try await client.pull(
                sinceVersion: 0,
                session: activeSession
            )
            let merged = Self.makeSnapshot(
                from: response,
                preserving: localSnapshot.settings
            )
            await cacheRemoteAttachments(
                from: response,
                client: client,
                session: activeSession
            )
            conflictRemoteSnapshot = nil
            status = .idle
            needsSync = false
            return merged
        } catch {
            status = .retrying
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func authenticate(
        email: String,
        password: String,
        register: Bool
    ) async {
        guard let client else {
            status = .localOnly
            return
        }
        let cleanEmail = email.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }
        status = .syncing
        do {
            let newSession = try await (
                register
                    ? client.signUp(email: cleanEmail, password: password)
                    : client.signIn(email: cleanEmail, password: password)
            )
            try await keychain.save(newSession)
            session = newSession
            status = .idle
            errorMessage = nil
            startRealtime()
        } catch {
            status = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    private func startRealtime() {
        realtimeTask?.cancel()
        guard let client, let session else { return }
        realtimeTask = Task { [weak self] in
            do {
                for try await _ in await client.realtimeInvalidations(
                    session: session
                ) {
                    guard !Task.isCancelled else { return }
                    self?.scheduleInvalidation()
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .retrying
            }
        }
    }

    private func scheduleInvalidation() {
        needsSync = true
        invalidationDebounceTask?.cancel()
        invalidationDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            await self.invalidationHandler?()
        }
    }

    private func uploadPendingAttachments(
        in snapshot: PixelDoneSnapshot,
        userID: String,
        client: SupabaseHTTPClient,
        session: SupabaseSession
    ) async throws -> PixelDoneSnapshot {
        guard let attachmentService else {
            return snapshot
        }
        var prepared = snapshot
        for index in prepared.todos.indices {
            guard var attachment = prepared.todos[index].attachment,
                  attachment.deletedAtMillis == nil,
                  attachment.objectPath == nil,
                  let attachmentID = attachment.attachmentID,
                  let contentSHA256 = attachment.contentSHA256,
                  let contentType = attachment.contentType else {
                continue
            }
            let data = try await attachmentService.loadLocalData(
                attachmentID: attachmentID
            )
            let objectPath =
                "\(userID)/\(prepared.todos[index].id)/\(attachmentID)-\(contentSHA256).jpg"
            try await client.uploadAttachment(
                data,
                objectPath: objectPath,
                contentType: contentType,
                session: session
            )
            attachment.objectPath = objectPath
            prepared.todos[index].attachment = attachment
        }
        return prepared
    }

    private func cacheRemoteAttachments(
        from response: PullChangesResponse,
        client: SupabaseHTTPClient,
        session: SupabaseSession
    ) async {
        guard let attachmentService else { return }
        for attachment in response.attachments {
            guard attachment.deletedAtMillis == nil,
                  let attachmentID = attachment.attachmentID,
                  let objectPath = attachment.objectPath,
                  let contentSHA256 = attachment.contentSHA256 else {
                continue
            }
            if (try? await attachmentService.loadLocalData(
                attachmentID: attachmentID
            )) != nil {
                continue
            }
            do {
                let data = try await client.downloadAttachment(
                    objectPath: objectPath,
                    session: session
                )
                try await attachmentService.storeDownloaded(
                    data,
                    attachmentID: attachmentID,
                    expectedSHA256: contentSHA256
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteCleanupObjects(
        _ paths: [String],
        client: SupabaseHTTPClient,
        session: SupabaseSession
    ) async -> [String] {
        var deleted: [String] = []
        for path in Set(paths) {
            do {
                try await client.deleteAttachment(
                    objectPath: path,
                    session: session
                )
                deleted.append(path)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        return deleted
    }

    private static func rebase(
        local: PixelDoneSnapshot,
        remote: PixelDoneSnapshot,
        conflicts: [SyncConflict]
    ) -> PixelDoneSnapshot {
        var rebased = local
        let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded())

        for conflict in conflicts {
            switch conflict.recordType {
            case "checklist":
                guard let index = rebased.checklists.firstIndex(
                    where: { $0.id == conflict.localID }
                ) else {
                    continue
                }
                if conflict.message == "tombstone_wins" {
                    let oldID = conflict.localID
                    let newID = UUID().uuidString.lowercased()
                    rebased.checklists[index].id = newID
                    rebased.checklists[index].remoteVersion = nil
                    rebased.checklists[index].updatedAtMillis = now
                    for todoIndex in rebased.todos.indices
                        where rebased.todos[todoIndex].checklistID == oldID {
                        rebased.todos[todoIndex].checklistID = newID
                        rebased.todos[todoIndex].remoteVersion = nil
                        rebased.todos[todoIndex].updatedAtMillis = now
                        if var attachment =
                            rebased.todos[todoIndex].attachment {
                            attachment.objectPath = nil
                            attachment.remoteVersion = nil
                            rebased.todos[todoIndex].attachment = attachment
                        }
                    }
                } else {
                    rebased.checklists[index].remoteVersion =
                        remote.checklists.first {
                            $0.id == conflict.localID
                        }?.remoteVersion
                }

            case "item":
                guard let index = rebased.todos.firstIndex(
                    where: { $0.id == conflict.localID }
                ) else {
                    continue
                }
                if conflict.message == "tombstone_wins" {
                    let newID = UUID().uuidString.lowercased()
                    rebased.todos[index].id = newID
                    rebased.todos[index].remoteVersion = nil
                    rebased.todos[index].updatedAtMillis = now
                    if var attachment = rebased.todos[index].attachment {
                        attachment.todoLocalID = newID
                        attachment.objectPath = nil
                        attachment.remoteVersion = nil
                        rebased.todos[index].attachment = attachment
                    }
                } else {
                    rebased.todos[index].remoteVersion =
                        remote.todos.first {
                            $0.id == conflict.localID
                        }?.remoteVersion
                }

            case "attachment":
                guard let index = rebased.todos.firstIndex(
                    where: { $0.id == conflict.localID }
                ), var attachment = rebased.todos[index].attachment else {
                    continue
                }
                attachment.remoteVersion = remote.todos.first {
                    $0.id == conflict.localID
                }?.attachment?.remoteVersion
                rebased.todos[index].attachment = attachment

            case "settings":
                rebased.settings.languageMode =
                    remote.settings.languageMode

            default:
                continue
            }
        }
        return rebased
    }

    private static func makeMutation(
        snapshot: PixelDoneSnapshot,
        userID: String,
        mutationUUID: String,
        cleanedImagePaths: [String] = []
    ) -> SyncMutation {
        let attachments = snapshot.todos.compactMap { todo in
            todo.attachment.map {
                RemoteAttachmentRecord(
                    todoLocalID: todo.id,
                    attachmentID: $0.attachmentID,
                    objectPath: $0.objectPath,
                    contentSHA256: $0.contentSHA256,
                    contentType: $0.contentType,
                    byteSize: $0.byteSize,
                    updatedAtMillis: $0.updatedAtMillis,
                    deletedAtMillis: $0.deletedAtMillis,
                    remoteVersion: $0.remoteVersion
                )
            }
        }
        return SyncMutation(
            mutationUUID: mutationUUID,
            snapshot: RemoteSnapshot(
                checklists: snapshot.checklists.map {
                    RemoteChecklistRecord(
                        localID: $0.id,
                        ownerUserID: userID,
                        sortIndex: $0.sortIndex,
                        name: $0.name,
                        createdAtMillis: $0.createdAtMillis,
                        updatedAtMillis: $0.updatedAtMillis,
                        remoteVersion: $0.remoteVersion
                    )
                },
                items: snapshot.todos.map {
                    RemoteTodoRecord(
                        localID: $0.id,
                        ownerUserID: userID,
                        checklistLocalID: $0.checklistID,
                        sortIndex: $0.sortIndex,
                        title: $0.title,
                        priority: $0.priority,
                        dueAtMillis: $0.dueAtMillis,
                        completed: $0.completed,
                        createdAtMillis: $0.createdAtMillis,
                        updatedAtMillis: $0.updatedAtMillis,
                        reminderRepeat: $0.reminderRepeat,
                        trashedFromChecklistID: $0.trashedFromChecklistID,
                        trashedFromChecklistName:
                            $0.trashedFromChecklistName,
                        trashedAtMillis: $0.trashedAtMillis,
                        remoteVersion: $0.remoteVersion
                    )
                },
                attachments: attachments
            ),
            settings: RemoteSettingsRecord(
                ownerUserID: userID,
                languageMode: snapshot.settings.languageMode,
                updatedAtMillis: Int64(
                    (Date().timeIntervalSince1970 * 1_000).rounded()
                )
            ),
            tombstones: snapshot.tombstones.map {
                RemoteTombstoneRecord(
                    recordType: $0.recordType.rawValue,
                    localID: $0.localID,
                    deletedAtMillis: $0.deletedAtMillis,
                    remoteVersion: $0.remoteVersion
                )
            },
            cleanedImagePaths: cleanedImagePaths
        )
    }

    private static func makeSnapshot(
        from response: PullChangesResponse,
        preserving localSettings: PixelDoneSettings
    ) -> PixelDoneSnapshot {
        let attachments = Dictionary(
            uniqueKeysWithValues: response.attachments.map {
                (
                    $0.todoLocalID,
                    PixelDoneAttachment(
                        todoLocalID: $0.todoLocalID,
                        attachmentID: $0.attachmentID,
                        objectPath: $0.objectPath,
                        contentSHA256: $0.contentSHA256,
                        contentType: $0.contentType,
                        byteSize: $0.byteSize,
                        updatedAtMillis: $0.updatedAtMillis,
                        deletedAtMillis: $0.deletedAtMillis,
                        remoteVersion: $0.remoteVersion
                    )
                )
            }
        )
        var settings = localSettings
        if let remoteSettings = response.settings {
            settings.languageMode = remoteSettings.languageMode
        }
        return PixelDoneSnapshot(
            checklists: response.checklists.map {
                PixelDoneChecklist(
                    id: $0.localID,
                    sortIndex: $0.sortIndex,
                    name: $0.name,
                    createdAtMillis: $0.createdAtMillis,
                    updatedAtMillis: $0.updatedAtMillis,
                    remoteVersion: $0.remoteVersion
                )
            },
            todos: response.items.map {
                PixelDoneTodo(
                    id: $0.localID,
                    checklistID: $0.checklistLocalID,
                    sortIndex: $0.sortIndex,
                    title: $0.title,
                    priority: $0.priority,
                    dueAtMillis: $0.dueAtMillis,
                    completed: $0.completed,
                    createdAtMillis: $0.createdAtMillis,
                    updatedAtMillis: $0.updatedAtMillis,
                    reminderRepeat: $0.reminderRepeat,
                    trashedFromChecklistID: $0.trashedFromChecklistID,
                    trashedFromChecklistName:
                        $0.trashedFromChecklistName,
                    trashedAtMillis: $0.trashedAtMillis,
                    remoteVersion: $0.remoteVersion,
                    attachment: attachments[$0.localID]
                )
            },
            tombstones: response.tombstones.compactMap {
                guard let recordType = TombstoneRecordType(
                    rawValue: $0.recordType
                ) else {
                    return nil
                }
                return PixelDoneTombstone(
                    recordType: recordType,
                    localID: $0.localID,
                    deletedAtMillis: $0.deletedAtMillis,
                    remoteVersion: $0.remoteVersion
                )
            },
            settings: settings
        )
    }
}
