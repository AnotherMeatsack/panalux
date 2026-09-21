# Micro Color Panel LED evidence

Audit: 20 September 2026. Device: USB VID `1EDB`, PID `DA0F` (2024 Micro Color Panel).

## Confirmed by Blackmagic's documentation

The [Micro Color Panel manual](https://documents.blackmagicdesign.com/InstallationGuides/DaVinciMicroColorPanelManual.pdf) and [quick-start guide](https://documents.blackmagicdesign.com/InstallationGuides/DaVinciMicroColorPanelQSG.pdf) describe these indicators in Resolve:

| Control | Documented active color |
| --- | --- |
| Bypass, Disable | Red |
| Offset, Shift Up, Shift Down | Green |
| Play Still, H/Lite, Cursor | Green |

This confirms the listed hardware indicators, not selectable RGB on every button. The manuals do not establish a green Bypass channel or explain USB color selection. Resolve's Bypass removes grades; PanaLux's default Bypass types Lightroom's Before/After shortcut, which is a different operation.

## Confirmed in this implementation

`PanelManager.setLEDs` writes report `0x02`, eight payload bytes (64 one-bit channels). Its current policy permits bits 12–63 and queues writes until held buttons are released. `PanelLEDController` constructs the same report. HardwareMap identifies input bits 20 and 21 as Bypass and Disable. There is no separate verified red/green channel table in this repository. An input-bit mapping does not prove that every output bit has the same physical meaning.

The earlier local descriptor analysis records output `0x04` as six bytes / 48 one-bit fields. Its purpose is unidentified. Extra report-0x02 channels, report-0x04 channels, or firmware-specific behavior are hypotheses, not supported color commands. No arbitrary feature reports or firmware configuration changes were sent during this audit.

## State semantics

The factory Bypass action is `key:\` (Before / After (Toggle)); existing custom bindings remain valid. `StudioEngine.typeKey` checks Accessibility and Lightroom's presence, then posts the key. Successful event posting is not confirmation of Lightroom's view. The bridge currently supplies no Before/After state readback. A local toggle counter can drift on keyboard/menu use, a different module, or a rejected key event, so it must not be labeled as authoritative bypass state.

## Remaining work

1. With a person observing the panel, correlate individual documented output channels with physical colors, preserving the prior lighting and exclusive panel ownership. Record exact report/payload, device/firmware, physical key and observed color; restore the prior state after each bounded check.
2. If necessary, capture Resolve's normal output transitions for red Bypass and green mode indicators. Do not infer report-0x04 semantics from its length.
3. Establish reliable Lightroom Before/After readback, including direct keyboard/menu changes and module/photo transitions. Unknown state must remain unknown.
4. Only then wire red to confirmed Before/bypass-active and green to confirmed After, if the physical Bypass key actually supports both. Preserve customized assignments and Stealth lighting.

No physical color validation or color-control fix is claimed by this update.
