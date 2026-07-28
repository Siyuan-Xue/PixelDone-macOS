import PixelDoneDomain
import SwiftUI

struct PixelDoneSettingsView: View {
    @Bindable var store: PixelDoneStore

    var body: some View {
        TabView {
            Form {
                Picker(
                    "Theme",
                    selection: Binding(
                        get: { store.snapshot.settings.appearanceMode },
                        set: { value in
                            Task { await store.send(.setAppearance(value)) }
                        }
                    )
                ) {
                    Label("Light", systemImage: "sun.max")
                        .tag(AppearanceMode.light)
                    Label("Dark", systemImage: "moon")
                        .tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)

                Picker(
                    "Language",
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
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            Form {
                Picker(
                    "Add button",
                    selection: Binding(
                        get: { store.snapshot.settings.dock.plusPlacement },
                        set: { value in
                            Task {
                                await store.send(.setDockPlacement(value))
                            }
                        }
                    )
                ) {
                    Text("Left").tag(DockPlacement.leftEdge)
                    Text("Center").tag(DockPlacement.center)
                    Text("Right").tag(DockPlacement.rightEdge)
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
                    "Up to four actions. Selecting a fifth removes the oldest selection."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Dock", systemImage: "dock.rectangle")
            }

            Form {
                LabeledContent(
                    "Mode",
                    value: AppConfiguration.current == nil
                        ? "Local only"
                        : "Configured"
                )
                LabeledContent("Contract", value: "Supabase 3.2")
                Text(
                    "The committed URL and key are intentionally blank. Local-only mode remains fully functional until Config/Local.xcconfig is filled."
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                LabeledContent("Apple baseline", value: "macOS 26.5")
                LabeledContent("Product baseline", value: "Android 3.3.6")
                LabeledContent("UI", value: "SwiftUI + Liquid Glass")
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Sync & About", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .padding(16)
        .frame(width: 620, height: 440)
        .task {
            await store.load()
        }
    }

    private func languageName(_ mode: LanguageMode) -> String {
        switch mode {
        case .system: "System"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .arabic: "العربية"
        case .french: "Français"
        case .russian: "Русский"
        case .spanish: "Español"
        }
    }

    private func actionName(_ action: DockAction) -> String {
        switch action {
        case .sort: "Sort"
        case .deadline: "Deadline countdown"
        case .hideDone: "Hide completed"
        case .deleteDone: "Clean completed"
        case .batchDelete: "Quick delete"
        case .exportMarkdown: "Export Markdown"
        }
    }
}
