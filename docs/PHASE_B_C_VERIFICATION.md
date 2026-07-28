# Phase B/C Verification

Verified on 2026-07-28 with Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen
2.46.0, and macOS 26.5.

## Feature status

| ID | Native implementation | Evidence | Status |
| --- | --- | --- | --- |
| MAC-AUTH-01 | Supabase email/password sign-up, sign-in, refresh, password change, global sign-out, Keychain session | HTTP fixture decodes Auth; project builds | Fixture verified |
| MAC-SYNC-01 | 3.2 pull/apply RPC, mutation UUID, transactional outbox, CAS conflicts, tombstones | AppleCore exact-wire test and app URLProtocol fixture | Fixture verified |
| MAC-RT-01 | URLSessionWebSocketTask invalidations with 350ms event debounce | Strict-concurrency build; no periodic polling | Build verified |
| MAC-STORAGE-01 | Authenticated Storage upload/download/delete, 10 MiB cap, 4096px JPEG, SHA-256 | Native image normalization test | Fixture verified |
| MAC-CONFLICT-01 | Review sheet, Keep Cloud, Keep Local, tombstone cloning | Store and contract tests; UI build | Fixture verified |
| MAC-NOTIFY-01 | Standard reminders, XHIGH Time Sensitive, Stop and Snooze 10 min | Native macOS build | Permission/device acceptance pending |
| MAC-L10N-01 | English, Simplified Chinese, Arabic RTL, French, Russian, Spanish, plus System selection | 275 imported product entries and 10 Apple shell entries compile | Build verified |
| MAC-UI-01 | WindowGroup, Settings, Commands, MenuBarExtra, Sidebar, toolbar, Inspector, Liquid Glass Dock | Build script, XCTest, Accessibility inspection | Verified |
| MAC-ICON-01 | Native four-layer Icon Composer app icon using the PixelDone palette and mark | `actool` generated `AppIcon.icns` from `AppIcon.icon`; rendered output visually inspected | Verified |

`Fixture verified` means the client behavior is tested without external
credentials. It does not claim that a live Supabase deployment accepted the
request.

## Reproducible evidence

```sh
./script/generate_project.sh
./script/build_and_run.sh --verify

xcodebuild test \
  -project PixelDone-macOS.xcodeproj \
  -scheme PixelDone-macOS \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -only-testing:PixelDoneTests

xcodebuild test \
  -project PixelDone-macOS.xcodeproj \
  -scheme PixelDone-macOS \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  -only-testing:PixelDoneUITests
```

Four Swift Testing tests and one XCTest UI flow pass. The running app was
inspected through the macOS Accessibility tree after the mandated build
script opened it; Sidebar, task rows, toolbar, glass Dock, and Inspector were
present.

## Live acceptance gate

The committed URL and publishable key remain blank. Live Auth, Realtime,
Storage cleanup, cross-device convergence, notification delivery, and
conflict acceptance remain deliberately open until an ignored
`Config/Local.xcconfig` is supplied.
