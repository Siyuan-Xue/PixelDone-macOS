# AGENTS.md

This repository contains the native macOS implementation of PixelDone.

## Required Reading

Before editing, generating the Xcode project, building, testing, signing, or changing window behavior:

1. `README.md`
2. `APP_SPEC.md`
3. `MAC_HANDOFF.md`
4. `RELEASE_SPEC.md`
5. the pinned sibling `PixelDoneAppleCore/START_HERE.md` and its required specifications

If the pinned AppleCore checkout is unavailable, stop rather than guessing product behavior.

## Rules

- All durable project rules and documentation must be written in English.
- The deployment target is macOS 26.0.
- Use SwiftUI scenes, SwiftData, Observation, UserNotifications, Keychain, and native URLSession APIs.
- AppKit interop must remain narrow and documented.
- The app is a regular Dock application with a main window, Settings, Commands, and a `MenuBarExtra`.
- Do not convert the app into a menu-bar-only accessory.
- Do not add third-party runtime dependencies without an architecture decision recorded in AppleCore.
- Views emit typed intent. They do not write persistence, credentials, or network state directly.
- Keep secrets in an ignored `Config/Local.xcconfig` and sessions in Keychain.
- Direct-IP HTTP/ws support and its warning are required.

## Run Contract

- `script/build_and_run.sh` is the single build/run entrypoint after project generation.
- `.codex/environments/environment.toml` must keep its Run action pointed at that script.
- Supported modes are default run, `--debug`, `--logs`, `--telemetry`, and `--verify`.

## Environment Boundary

- Project generation, compilation, testing, signing, and launch occur only on macOS.
- Windows-created Swift, scripts, and XcodeGen files are unverified scaffolding until the first Mac build.
- Do not claim build or runtime success without Xcode 26 evidence.
