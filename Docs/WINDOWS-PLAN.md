# Windows feasibility and first implementation plan

20 September 2026 — planning only; no Windows build or hardware validation yet.

## Target

Keep control identities, maps, combinations, Lightroom command semantics and Rewind behavior compatible. Recreate the panel canvas and main workflows closely. Native macOS glass, menu bar, notch attachment, permission prompts, keyboard modifiers and updater will need Windows equivalents. Do not promise pixel-identical OS effects or a percentage of code reuse before a prototype.

Swift is available on Windows. The current executable cannot simply be compiled there: Package.swift links IOKit, AppKit, SwiftUI, Network, ApplicationServices, ServiceManagement and Sparkle. Source inventory includes 40 files importing SwiftUI and 25 importing AppKit (overlap exists). The engine also mixes platform services with state; extracting it is real work.

## Architecture and likely reuse

| Area | Proposed treatment |
| --- | --- |
| Profile JSON, command IDs, panel SVG/assets | Keep formats and semantic IDs; fixture-test cross-platform round trips. Map hardware calibration remains separate from user actions. |
| PanelDecoder, layout, combinations, value/range calculations, Rewind data | Extract Foundation-only core with clock, storage and output interfaces. Validate endian/alignment and report-ID handling on Windows. |
| Lightroom Lua bridge and command catalog | Reuse SDK/socket logic where supported; audit path separators, shell calls, module installation and platform-specific shortcuts. Verify against Windows Lightroom. |
| USB/HID and LEDs | Windows adapter using HIDAPI/Windows HID, behind a PanelTransport interface. Preserve report 0x0A streaming enable, payload framing, hot-plug, exclusive ownership and LED/input coordination. |
| Network.framework bridge | Replace with a portable socket adapter while keeping wire messages unchanged. |
| SwiftUI/AppKit, WebKit canvas | Prototype a Windows shell around shared core. Compare native WinUI/C# plus C ABI with a web canvas shell; choose after measuring interop and rendering, not before. SVG art is reusable. |
| Keyboard injection/accessibility, Photoshop AppleScript | New Windows implementations. Validate shortcut translation and Photoshop automation separately; do not assume AppleScript ports. |
| Tray/HUD/login/update/install | Windows tray, floating overlay, startup registration, signed installer and update mechanism. Preserve non-notch HUD workflow. |

## Smallest useful first slice

1. Extract a headless core package without changing the Mac UI. Define PanelTransport, LightroomTransport, clock and storage boundaries.
2. Build a replay fixture set: button down/up and holds, three navigation pairs, simultaneous chords, positive/negative knobs and ball/ring deltas, LED-associated reports, disconnect/reconnect and malformed/truncated packets. Compare emitted semantic events and command sequences with the Mac baseline.
3. Compile and run core tests on a Windows CI runner. This proves actual Windows execution without the stored PC; CI does not prove USB or Lightroom compatibility. Add CI only once the portable target exists.
4. Build a Windows diagnostic executable before a full UI: enumerate the panel, enable streaming, log physical control names, show all knobs/balls, and test LEDs. Make diagnostic logs exportable and avoid sending editing commands by default.
5. Connect a mock Lightroom server, then a real Windows Lightroom instance with disposable photos. Prove one knob, one reset, one combination and readback end to end. Then add Rewind and a minimal map canvas.
6. Choose the final UI stack using the working slice; expand feature parity against an explicit checklist.

## Testing before unpacking the PC

- Today on Mac: recorded/replayed input, protocol and profile fixtures, reference screenshots, core extraction and deterministic command comparisons.
- Windows hosted runner: compile and test headless core, packaging sanity and mock socket integration. Requires configured CI; not executed in this task.
- Windows VM with suitable USB passthrough: useful for UI and preliminary integration. CPU architecture, GPU/animation and USB redirection can differ from the target PC. Do not treat VM responsiveness as final evidence.
- Real PC: required before claiming hardware quality. Connect the panel directly and run Windows Lightroom/Photoshop. Test hot-plug, sleep/wake, Resolve releasing/reclaiming the device, every button/LED, sustained fast input, multi-monitor/DPI, and both cold/warm app starts.

Capture median/p95 input-to-dispatch latency, dropped/duplicate events and maximum queue growth during repeatable recorded loads. Separately measure visible Lightroom response and subjective ball/ring feel on the PC. Establish a Mac baseline first; no performance threshold or current Windows result is claimed here.

## Release gates

All 12 knob rotations/presses, 3 balls, 3 rings and 40 buttons must match semantic IDs. Existing maps must retain actions and held modes. Navigation LEDs must match the physical labels. Readback, masks, combinations and Rewind must pass parity fixtures and hands-on checks. Photoshop, shortcuts, installation and updating need independent Windows acceptance tests.

Get the PC out when the diagnostic executable is ready, or sooner if convenient to identify its Windows version, CPU architecture and available ports. Planning and core work can start now.

## Primary references

- Swift Windows toolchains: https://www.swift.org/install/windows/
- Swift platform support: https://www.swift.org/platform-support/
- HIDAPI Windows/macOS backends: https://github.com/libusb/hidapi
- Microsoft VM device sharing: https://learn.microsoft.com/en-ie/windows-server/virtualization/hyper-v/enhanced-session-mode
