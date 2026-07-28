# PixelDone for macOS

Native SwiftUI implementation of PixelDone for macOS 26.5.

This repository is intentionally self-contained when checked out beside `PixelDoneAppleCore`; it does not require the Android or Windows source repositories.

## Mac Checkout

```text
PixelDone-Apple/
├── PixelDone-iOS/
├── PixelDone-macOS/
└── PixelDoneAppleCore/
```

Read `MAC_HANDOFF.md` before generating or running the project.

Current stage: local-first Phase A plus fixture-verified native Phase B/C
infrastructure. The app has been compiled, tested, launched through the
required shell workflow, and visually inspected on macOS 26.5 with Xcode
26.6.

`PixelDoneApp/AppIcon.icon` is the Apple Icon Composer source and build
resource. `project.yml` is authoritative for selecting it as `AppIcon`.

The committed Supabase configuration is intentionally empty. Add an ignored
`Config/Local.xcconfig` only when a live HTTP/WS server is ready.

See `docs/PHASE_B_C_VERIFICATION.md` and `docs/PHASE_D_PERFORMANCE.md` for
feature, evidence, and performance-audit status.

Developer identity: CODEX & XUE.
