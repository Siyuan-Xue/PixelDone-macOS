# Phase A Verification

Verified on 2026-07-28 with Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen
2.46.0, and macOS 26.5.

## Implemented

- SwiftData-backed checklists, todos, settings, tombstones, sync metadata,
  and transactional outbox records.
- Fixed MAIN, TRASH, and SETTINGS destinations plus checklist and Trash rules.
- Todo creation, editing, completion, reactivation, priority, due date,
  recurrence, sorting, product Dock actions, Trash restoration, retention,
  and Markdown export.
- Native `WindowGroup`, `Settings`, `MenuBarExtra`, `Commands`,
  `NavigationSplitView`, toolbar, and inspector structure.
- Liquid Glass action groups with PixelDone Ivory, Slate, Clay, square task
  geometry, and semantic priority colors.
- Complete local-only behavior when Supabase configuration is empty.

## Evidence

```sh
./script/generate_project.sh
./script/build_and_run.sh --verify

xcodebuild test \
  -project PixelDone-macOS.xcodeproj \
  -scheme PixelDone-macOS \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData
```

The app was inspected through macOS Accessibility after launch. MAIN exposed
both seeded tasks, the task inspector exposed its expected controls, the
Settings scene opened as a separate native settings window, and the menu bar
included the app's Tasks command menu.
