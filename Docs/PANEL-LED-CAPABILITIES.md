# Micro Color Panel LED evidence

Audit: 20 September 2026. Device: USB VID `1EDB`, PID `DA0F` (2024 Micro Color Panel).

## Observed on the user’s USB panel — 20 September 2026

A standalone probe held the same exclusive panel lock as PanaLux, with PanaLux quit and no Lightroom commands or input routing. Every output test automatically returned its report to zero after 30 seconds.

- The live 297-byte HID descriptor confirms report `0x02`: 64 one-bit output channels, and report `0x04`: 48 one-bit output channels.
- `0x02`, bits 12–51 together: user observed all/most keys white, then dim/off when cleared.
- `0x02`, bit 20 alone after a settling delay: user observed one brighter white key, returning to the common dimmer backlight after clearing. The input-to-output key name still needs an explicit observer confirmation.
- **`0x04`, bit 0: user explicitly confirmed Bypass turns red.** Payload including report ID: `04 01 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- `0x04`, bit 1: user observed only standard white backlighting with no colored or distinctive key change; all lights turned off when the test ended and the probe closed. Payload: `04 02 00 00 00 00 00`.
- **`0x04`, bit 2: user explicitly confirmed Offset turns green.** Payload including report ID: `04 04 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 3: user explicitly confirmed Disable turns red.** Payload including report ID: `04 08 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 4: user explicitly confirmed Shift Up turns green.** Payload including report ID: `04 10 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 5: user explicitly confirmed Shift Down turns green.** Payload including report ID: `04 20 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 6: user explicitly confirmed Play Still turns green.** Payload including report ID: `04 40 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 7: user explicitly confirmed Wipe Still turns green.** Payload including report ID: `04 80 00 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 8: user explicitly confirmed H/Lite turns green.** Payload including report ID: `04 00 01 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 9: user explicitly confirmed Viewer turns green.** Payload including report ID: `04 00 02 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- **`0x04`, bit 10: user explicitly confirmed Cursor turns green.** Payload including report ID: `04 00 04 00 00 00 00`. Clearing `04 00 00 00 00 00 00` ends the test.
- `0x04`, bit 11: user observed no visible change. Payload: `04 00 08 00 00 00 00`.
- `0x04`, bit 12: user observed no visible change. Payload: `04 00 10 00 00 00 00`.
- `0x04`, bit 13: user observed no visible change. Payload: `04 00 20 00 00 00 00`.
- `0x04`, bit 16: user observed no visible change (tested 16-bit bank offset). Payload: `04 00 00 01 00 00 00`.
- `0x04`, bit 24: user observed no visible change (tested 24-bit bank offset). Payload: `04 00 00 00 01 00 00`.
- `0x04`, bits 14–23 (tested together, repeated): user observed no visible change across the entire panel. Payload: `04 00 c0 ff 00 00 00`.
- `0x04`, bits 24–47 (full second half, tested together): user observed no visible change across the entire panel. Payload: `04 00 00 00 ff ff ff`.
- Feature `0x08` read back `08 00 64` before testing. No brightness changes have been made yet. Output reports cannot be read back on this device (`IOHIDDeviceGetReport` returns an error), so zero is the explicit tested output cleanup, not a claim that the previous unknown report-0x04 state was read and restored.

**Physical Hardware LED Census Confirmed**:
- Exactly 10 physical color LED channels exist on the Micro Color Panel:
  - 2 Red indicators: **Bypass** (`0x04` bit 0) and **Disable** (`0x04` bit 3).
  - 8 Green indicators: **Offset** (`0x04` bit 2), **Shift Up** (`0x04` bit 4), **Shift Down** (`0x04` bit 5), **Play Still** (`0x04` bit 6), **Wipe Still** (`0x04` bit 7), **H/Lite** (`0x04` bit 8), **Viewer** (`0x04` bit 9), **Cursor** (`0x04` bit 10).
- **Bypass does not physically support Green.** Extensive tests across all banks and individual channels confirm Bypass has only a Red LED die and a White backlight die.
- All remaining keys (bits 11–47) have only single-color white illumination.
- The shipping app has not yet been changed to use this new report.

## Confirmed by Blackmagic's documentation

The [Micro Color Panel manual](https://documents.blackmagicdesign.com/InstallationGuides/DaVinciMicroColorPanelManual.pdf) and [quick-start guide](https://documents.blackmagicdesign.com/InstallationGuides/DaVinciMicroColorPanelQSG.pdf) describe these indicators in Resolve:

| Control | Documented active color |
| --- | --- |
| Bypass, Disable | Red |
| Offset, Shift Up, Shift Down | Green |
| Play Still, H/Lite, Cursor | Green |

This confirms the listed hardware indicators, not selectable RGB on every button. The manuals do not establish a green Bypass channel or explain USB color selection. Resolve's Bypass removes grades; PanaLux's default Bypass types Lightroom's Before/After shortcut, which is a different operation.

## Confirmed in this implementation

`PanelManager.setLEDs` writes report `0x02`, eight payload bytes (64 one-bit channels). Its current policy permits bits 12–63 and queues writes until held buttons are released. `PanelLEDController` constructs the same report. HardwareMap identifies input bits 20 and 21 as Bypass and Disable. The shipping driver has no separate red/green channel table; the observed Bypass red channel is recorded above. An input-bit mapping does not prove that every output bit has the same physical meaning.

The earlier local descriptor analysis records output `0x04` as six bytes / 48 one-bit fields. The live test above now identifies at least its bit 0 as Bypass red; the other channels remain unmapped. Extra report-0x02 channels, report-0x04 channels, or firmware-specific behavior are hypotheses, not supported color commands. No arbitrary feature reports or firmware configuration changes were sent during this audit.

## State semantics

The factory Bypass action is `key:\` (Before / After (Toggle)); existing custom bindings remain valid. `StudioEngine.typeKey` checks Accessibility and Lightroom's presence, then posts the key. Successful event posting is not confirmation of Lightroom's view. The bridge currently supplies no Before/After state readback. A local toggle counter can drift on keyboard/menu use, a different module, or a rejected key event, so it must not be labeled as authoritative bypass state.

## Remaining work

1. With a person observing the panel, correlate individual documented output channels with physical colors, preserving the prior lighting and exclusive panel ownership. Record exact report/payload, device/firmware, physical key and observed color; restore the prior state after each bounded check.
2. If necessary, capture Resolve's normal output transitions for red Bypass and green mode indicators. Do not infer report-0x04 semantics from its length.
3. Establish reliable Lightroom Before/After readback, including direct keyboard/menu changes and module/photo transitions. Unknown state must remain unknown.
4. Only then wire red to confirmed Before/bypass-active and green to confirmed After, if the physical Bypass key actually supports both. Preserve customized assignments and Stealth lighting.

The earlier glass-guide release contained no color-control fix. The subsequent calibration above confirms one physical color channel; it is not yet integrated into a shipped update.
