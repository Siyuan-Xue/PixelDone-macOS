# PixelDone macOS Application Specification

## Target

- Product name: PixelDone
- Bundle identifier: `com.milesxue.pixeldone.macos`
- Deployment: macOS 26.0
- Interface: SwiftUI with narrow AppKit interop
- Persistence: SwiftData
- Shared package: sibling `../PixelDoneAppleCore`

The complete product contract is in the pinned AppleCore repository. This file defines macOS-specific structure.

## Scenes

- `WindowGroup("PixelDone", id: "main")` owns the regular primary window.
- `Settings` owns native application settings.
- `MenuBarExtra` exposes app status, open-main-window, safe quick actions, and Quit.
- Closing the main window does not terminate the app while the menu-bar extra is enabled.
- The application remains a regular Dock application, not an accessory-only menu-bar utility.

## Window and Navigation

- Default size: 1180 x 780 pt.
- Minimum size: 1000 x 680 pt.
- Use `NavigationSplitView` for Sidebar and Workspace.
- Sidebar owns ordinary checklists, Trash, Settings shortcut, account, and sync summary.
- Task editing uses an inspector where practical and a sheet for focused/destructive workflows.
- Menus and shortcuts supplement visible controls; they never become the only access path.

## State and Dependencies

- A `@MainActor @Observable PixelDoneStore` owns app presentation state and typed actions.
- Repository, sync, authentication, attachment, notification, and menu-bar services are injected at composition.
- Services that serialize persistence or network operations use actors.
- Views render immutable snapshots and never access model contexts, Keychain, or URLSession directly.

## Platform Services

- SwiftData stores domain and rebuildable sync metadata separately.
- Keychain stores Supabase sessions.
- `URLSession` handles Auth, PostgREST RPC, Storage, and `URLSessionWebSocketTask` Realtime.
- `UNUserNotificationCenter` schedules reminders and STOP/SNOOZE categories.
- XHigh requests Time Sensitive presentation only when authorized.
- Import uses a native open/photo selection surface and app-private normalized copies.
- Optional launch-at-login work is deferred until the main application is stable.

## UI

- Let `NavigationSplitView`, Toolbars, Settings, Sheets, and menus use native macOS 26 materials.
- Do not paint over the system Sidebar or Toolbar.
- Keep task rows, priority controls, product Dock, conflict UI, and content panels on PixelDone design tokens.
- Support VoiceOver, Full Keyboard Access, pointer, Reduce Motion, Increase Contrast, and Arabic RTL.

## Exclusions

- No WidgetKit target.
- No Sparkle or self-updater in the foundation.
- No Developer ID, notarization, or Mac App Store workflow.
- No Critical Alerts.
- No fixed-interval sync polling.
