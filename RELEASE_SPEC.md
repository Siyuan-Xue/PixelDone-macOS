# PixelDone macOS Release Specification

## Stage

`0.1.0-foundation` is an internal source scaffold, not a distributable app release.

## Signing and Distribution

- Automatic signing is enabled, but `DEVELOPMENT_TEAM` is not committed.
- The App Sandbox, network client, and user-selected file access entitlements are explicit.
- No Developer ID, notarization, Mac App Store, DMG, PKG, Sparkle, or public updater is configured.

## Completion Gate

The macOS app is not complete until a Mac records:

- successful Xcode 26 build and `.app` launch through `script/build_and_run.sh`;
- shared and app test results;
- evidence for every required macOS feature row;
- main-window, Settings, Commands, MenuBarExtra, keyboard, pointer, Light, Dark, Arabic RTL, Chinese, accessibility, offline, conflict, attachment, and reminder states;
- exact commit, Xcode, Swift, SDK, entitlements, and signing context.

Windows inspection does not satisfy this gate.
