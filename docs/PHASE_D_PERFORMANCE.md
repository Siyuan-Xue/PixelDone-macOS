# Phase D Performance Audit

Audited on 2026-07-28 with the Build macOS Apps workflow.

## Code-first findings

| Area | Evidence | Result |
| --- | --- | --- |
| List identity | Sidebar and todo collections use stable domain UUIDs | Pass |
| SwiftUI body work | Attachment image decoding moved into `PixelDoneAttachmentService` and cached in view state | Fixed |
| Motion accessibility | Programmatic todo scrolling skips animation when Reduce Motion is enabled | Pass |
| Layout | Native split-view and inspector sizing avoid layout feedback loops | Pass |
| Formatting | No formatter allocation in scrolling row bodies | Pass |
| Platform bridge | Window and command behavior remain SwiftUI-native; no broad AppKit ownership | Pass |

The immutable store snapshot can still invalidate more of the window hierarchy
than an individual changed row. That is acceptable for the current small data
set and remains a measurement target for large imports.

## Runtime evidence boundary

The mandated build-and-run script, XCTest flow, and Accessibility inspection
verify launch and the main window structure. No valid Instruments trace has been
captured yet, so this document does not claim launch-time, CPU, hang, or
frame-rate numbers.

Before release, profile a signed Release build on the target Mac and verify:

1. App Launch and SwiftUI update cost.
2. Sidebar and task scrolling with a realistically large imported checklist.
3. Memory after repeatedly selecting and removing 10 MiB image attachments.
4. MenuBarExtra and main-window lifecycle over repeated open/close cycles.
