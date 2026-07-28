import ImageIO
import PixelDoneDomain
import SwiftUI
import UniformTypeIdentifiers

struct TodoEditorView: View {
    @Bindable var store: PixelDoneStore
    let presentation: EditorPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoDraft
    @State private var isImportingAttachment = false
    @State private var attachmentMessage: String?
    @State private var existingAttachmentData: Data?
    private let attachmentService = PixelDoneAttachmentService()

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
                Button("close", systemImage: "xmark") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }

            Form {
                Section("field_title") {
                    TextField(
                        "field_title",
                        text: $draft.title,
                        axis: .vertical
                    )
                    .lineLimit(2...5)

                    Picker("field_priority", selection: $draft.priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { priority in
                            Text(priority.localizedName).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("deadline_short") {
                    DatePicker(
                        "field_due",
                        selection: $draft.dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Picker("field_repeat", selection: $draft.reminderRepeat) {
                        Text("repeat_none").tag(ReminderRepeat.none)
                        Text("repeat_daily").tag(ReminderRepeat.daily)
                        Text("repeat_weekly").tag(ReminderRepeat.weekly)
                    }
                }

                Section {
                    if let image = attachmentImage {
                        Image(
                            decorative: image,
                            scale: 1,
                            orientation: .up
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityLabel("task_image_preview")
                    }

                    Button(
                        "add_task_image",
                        systemImage: "photo.badge.plus"
                    ) {
                        isImportingAttachment = true
                    }

                    if hasAttachment {
                        Button(
                            "remove",
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            draft.attachment = nil
                            draft.removeAttachment = true
                            existingAttachmentData = nil
                            attachmentMessage =
                                "Image will be removed on save."
                        }
                    }

                    if let attachmentMessage {
                        Text(attachmentMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("save") {
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
        .fileImporter(
            isPresented: $isImportingAttachment,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            Task {
                do {
                    let url = try result.get()
                    guard let selectedURL = url.first else {
                        return
                    }
                    let accessed =
                        selectedURL.startAccessingSecurityScopedResource()
                    defer {
                        if accessed {
                            selectedURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    let data = try Data(contentsOf: selectedURL)
                    draft.attachment = try await attachmentService.normalize(
                        data
                    )
                    draft.removeAttachment = false
                    attachmentMessage =
                        "Image ready — normalized as JPEG."
                } catch {
                    attachmentMessage = error.localizedDescription
                }
            }
        }
        .task(id: existingAttachmentID) {
            guard case let .edit(todo) = presentation else { return }
            existingAttachmentData = await store.attachmentData(for: todo)
        }
    }

    private var title: LocalizedStringKey {
        switch presentation {
        case .create: "new_task"
        case .edit: "edit_task"
        }
    }

    private var hasAttachment: Bool {
        draft.attachment != nil || {
            if case let .edit(todo) = presentation {
                return todo.attachment?.deletedAtMillis == nil
                    && todo.attachment != nil
            }
            return false
        }()
    }

    private var existingAttachmentID: String? {
        if case let .edit(todo) = presentation {
            return todo.attachment?.attachmentID
        }
        return nil
    }

    private var attachmentImage: CGImage? {
        let data = draft.attachment?.data ?? existingAttachmentData
        guard let data,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
              ) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
                        Text("field_title")
                            .font(.caption.weight(.black))
                            .foregroundStyle(todo.priority.color)
                        Text(todo.title)
                            .font(.title2.weight(.bold))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("close", systemImage: "xmark") {
                        store.inspectedTodoID = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text("field_priority").foregroundStyle(.secondary)
                        Text(todo.priority.localizedName)
                            .fontWeight(.bold)
                            .foregroundStyle(todo.priority.color)
                    }
                    GridRow {
                        Text("field_due").foregroundStyle(.secondary)
                        Text(
                            Date(
                                timeIntervalSince1970:
                                    Double(todo.dueAtMillis) / 1_000
                            ),
                            format: .dateTime.year().month().day().hour().minute()
                        )
                    }
                    GridRow {
                        Text("field_repeat").foregroundStyle(.secondary)
                        Text(repeatName(todo.reminderRepeat))
                    }
                    GridRow {
                        Text("field_completed").foregroundStyle(.secondary)
                        Text(todo.completed ? "status_completed" : "status_active")
                    }
                }

                if todo.attachment?.deletedAtMillis == nil,
                   todo.attachment != nil {
                    TodoAttachmentPreviewView(store: store, todo: todo)
                }

                Spacer(minLength: 8)

                if store.selectedChecklistID
                    == PixelDoneProductBaseline.trashChecklistID {
                    Button("restore_task", systemImage: "arrow.uturn.backward") {
                        Task { await store.send(.restoreTodo(todo.id)) }
                    }
                    .buttonStyle(.glassProminent)

                    Button(
                        "delete_task",
                        systemImage: "trash.slash",
                        role: .destructive
                    ) {
                        Task {
                            await store.send(.permanentlyDelete(todo.id))
                        }
                    }
                } else {
                    Button("edit_task", systemImage: "pencil") {
                        store.editorPresentation = .edit(todo)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.pixelDoneClay)

                    Button(
                        "field_trash",
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

    private func repeatName(
        _ reminderRepeat: ReminderRepeat
    ) -> LocalizedStringKey {
        switch reminderRepeat {
        case .none: "repeat_none"
        case .daily: "repeat_daily"
        case .weekly: "repeat_weekly"
        }
    }
}

private struct TodoAttachmentPreviewView: View {
    @Bindable var store: PixelDoneStore
    let todo: PixelDoneTodo
    @State private var data: Data?

    var body: some View {
        Group {
            if let image {
                Image(
                    decorative: image,
                    scale: 1,
                    orientation: .up
                )
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityLabel("task_image_preview")
            } else {
                Label("loading_image", systemImage: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: todo.attachment?.attachmentID) {
            data = await store.attachmentData(for: todo)
        }
    }

    private var image: CGImage? {
        guard let data,
              let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
              ) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
