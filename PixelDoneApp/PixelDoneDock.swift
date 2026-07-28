import PixelDoneDomain
import SwiftUI

struct PixelDoneDock: View {
    @Bindable var store: PixelDoneStore
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if store.snapshot.settings.dock.plusPlacement == .leftEdge {
                    addButton
                }

                ForEach(
                    store.snapshot.settings.dock.actions,
                    id: \.self
                ) { action in
                    actionView(action)
                }

                if store.snapshot.settings.dock.plusPlacement == .center {
                    addButton
                }

                if store.snapshot.settings.dock.plusPlacement == .rightEdge {
                    addButton
                }
            }
        }
        .padding(8)
    }

    private var addButton: some View {
        Button {
            store.editorPresentation = .create
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glassProminent)
        .tint(.pixelDoneClay)
        .glassEffectID("dock-add", in: glassNamespace)
        .accessibilityLabel("new_task")
    }

    @ViewBuilder
    private func actionView(_ action: DockAction) -> some View {
        if action == .exportMarkdown {
            ShareLink(
                item: markdown,
                subject: Text(store.selectedChecklist?.name ?? "PixelDone"),
                message: Text("shell_exported_from")
            ) {
                dockLabel(action)
            }
            .buttonStyle(.glass)
            .glassEffectID(action.rawValue, in: glassNamespace)
        } else {
            Button {
                perform(action)
            } label: {
                dockLabel(action)
            }
            .buttonStyle(.glass)
            .glassEffectID(action.rawValue, in: glassNamespace)
        }
    }

    private func dockLabel(_ action: DockAction) -> some View {
        Image(systemName: symbol(for: action))
            .frame(width: 34, height: 34)
            .foregroundStyle(
                isActive(action) ? Color.pixelDoneClay : Color.primary
            )
            .accessibilityLabel(label(for: action))
    }

    private func perform(_ action: DockAction) {
        Task {
            switch action {
            case .sort:
                await store.send(
                    .setSortMode(
                        store.snapshot.settings.sortMode == .priority
                            ? .time
                            : .priority
                    )
                )
            case .deadline:
                await store.send(.toggleDeadline)
            case .hideDone:
                await store.send(.toggleHideCompleted)
            case .deleteDone:
                await store.send(.cleanCompleted)
            case .batchDelete:
                await store.send(.toggleQuickDelete)
            case .exportMarkdown:
                break
            }
        }
    }

    private func symbol(for action: DockAction) -> String {
        switch action {
        case .sort: "arrow.up.arrow.down"
        case .deadline: "timer"
        case .hideDone: "eye.slash"
        case .deleteDone: "checkmark.square"
        case .batchDelete: "trash.square"
        case .exportMarkdown: "square.and.arrow.up"
        }
    }

    private func label(for action: DockAction) -> LocalizedStringKey {
        switch action {
        case .sort: "toggle_sort"
        case .deadline: "toggle_deadline"
        case .hideDone: "toggle_done_visibility"
        case .deleteDone: "clean_done"
        case .batchDelete: "toggle_quick_delete"
        case .exportMarkdown: "export_markdown"
        }
    }

    private func isActive(_ action: DockAction) -> Bool {
        switch action {
        case .deadline:
            store.snapshot.settings.showDeadlineCountdown
        case .hideDone:
            store.snapshot.settings.hideCompleted
        case .batchDelete:
            store.snapshot.settings.quickDelete
        default:
            false
        }
    }

    private var markdown: String {
        MarkdownExporter.render(
            checklistName: store.selectedChecklist?.name ?? "PixelDone",
            todos: store.visibleTodos,
            detailed: true,
            formatMillis: { millis in
                Date(
                    timeIntervalSince1970: Double(millis) / 1_000
                ).formatted(
                    .dateTime.year().month().day().hour().minute()
                )
            }
        )
    }
}
