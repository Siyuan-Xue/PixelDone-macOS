import PixelDoneDomain
import SwiftUI

struct PixelDoneSettingsView: View {
    @Bindable var store: PixelDoneStore

    var body: some View {
        TabView {
            Form {
                Picker(
                    "settings_theme",
                    selection: Binding(
                        get: { store.snapshot.settings.appearanceMode },
                        set: { value in
                            Task { await store.send(.setAppearance(value)) }
                        }
                    )
                ) {
                    Label("theme_light", systemImage: "sun.max")
                        .tag(AppearanceMode.light)
                    Label("theme_dark", systemImage: "moon")
                        .tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)

                Picker(
                    "settings_language",
                    selection: Binding(
                        get: { store.snapshot.settings.languageMode },
                        set: { value in
                            Task { await store.send(.setLanguage(value)) }
                        }
                    )
                ) {
                    ForEach(LanguageMode.allCases, id: \.self) { mode in
                        Text(languageName(mode)).tag(mode)
                    }
                }

                Divider()

                LabeledContent(
                    "settings_permissions",
                    value: store.notificationStatus
                )
                Button(
                    "update_permissions",
                    systemImage: "bell.badge"
                ) {
                    Task {
                        await store.requestNotificationAuthorization()
                    }
                }
                Text(
                    "xhigh_task_due"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("settings_display", systemImage: "gear")
            }

            Form {
                Picker(
                    "plus",
                    selection: Binding(
                        get: { store.snapshot.settings.dock.plusPlacement },
                        set: { value in
                            Task {
                                await store.send(.setDockPlacement(value))
                            }
                        }
                    )
                ) {
                    Text("left").tag(DockPlacement.leftEdge)
                    Text("center").tag(DockPlacement.center)
                    Text("right").tag(DockPlacement.rightEdge)
                }
                .pickerStyle(.segmented)

                ForEach(DockAction.allCases, id: \.self) { action in
                    Toggle(
                        actionName(action),
                        isOn: Binding(
                            get: {
                                store.snapshot.settings.dock.actions
                                    .contains(action)
                            },
                            set: { isSelected in
                                let current =
                                    store.snapshot.settings.dock.actions
                                let next = isSelected
                                    ? DockRules.selecting(action, in: current)
                                    : DockRules.deselecting(action, in: current)
                                Task {
                                    await store.send(.setDockActions(next))
                                }
                            }
                        )
                    )
                }

                Text(
                    "settings_dock"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("settings_dock", systemImage: "dock.rectangle")
            }

            Form {
                LabeledContent("cloud") {
                    Text(cloudStatusName(store.cloud.status))
                }
                LabeledContent("cloud_version", value: "Supabase 3.2")
                CloudAccountView(store: store)

                Divider()

                LabeledContent("app", value: "macOS 26.5")
                LabeledContent("stable", value: "Android 3.3.6")
                LabeledContent("preview", value: "SwiftUI + Liquid Glass")
            }
            .formStyle(.grouped)
            .tabItem {
                Label("settings_about", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .padding(16)
        .frame(width: 620, height: 440)
        .id(store.snapshot.settings.languageMode)
        .task {
            await store.load()
        }
    }

    private func languageName(_ mode: LanguageMode) -> LocalizedStringKey {
        switch mode {
        case .system: "language_system"
        case .english: "language_english"
        case .simplifiedChinese: "language_chinese"
        case .arabic: "language_arabic"
        case .french: "language_french"
        case .russian: "language_russian"
        case .spanish: "language_spanish"
        }
    }

    private func actionName(_ action: DockAction) -> LocalizedStringKey {
        switch action {
        case .sort: "sort"
        case .deadline: "toggle_deadline"
        case .hideDone: "hide_done"
        case .deleteDone: "clean_done"
        case .batchDelete: "quick_delete"
        case .exportMarkdown: "export_markdown"
        }
    }

    private func cloudStatusName(
        _ status: CloudStatus
    ) -> LocalizedStringKey {
        switch status {
        case .localOnly: "local_only"
        case .signedOut: "signed_out"
        case .idle: "synced"
        case .syncing: "syncing"
        case .retrying: "pending"
        case .authenticationExpired: "sync_sign_in_required"
        case .updateRequired: "server_update_required"
        case .storageError: "error"
        }
    }
}
