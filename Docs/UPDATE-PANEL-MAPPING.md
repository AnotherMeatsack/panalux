# Panel mapping update — prepared 20 September 2026

The navigation mapping fix and old-factory-map migration were published as v1.2.3 on 20 September 2026: https://github.com/AnotherMeatsack/panalux/releases/tag/v1.2.3

Reference-image export remains in source only; it was not included in that focused hotfix. No local app installation was performed.

Prepared changes:

- Correct physical Previous/Next Keyframe to bits 41/42, Frame to 45/46, Clip to 47/48. Reverse LED mapping follows the same table.
- Correct saved/imported calibration only when all six navigation entries match the old factory signature. Partial/custom mappings remain unchanged. Other assignments remain intact. There is no device/firmware-specific evidence yet; a panel with a different physical layout can retain custom calibration.
- Help → Print Reference Card opens the printable current-map sheet (browser printing also supports PDF).
- Help → Save Reference Image exports that sheet as PNG. It includes modes, bank assignments, explicit knob presses and button combinations. This is a labeled reference sheet, not a photograph of the panel. Default knob-press reset behavior is described in Quick Reference; explicit overrides appear on the sheet.
- Up Shift + wheel reset (color) and Down Shift + wheel reset (luminance) already exist in the 1.2.2 source and remain editable.

Physical follow-up: press all six corrected navigation buttons and verify their highlighted control and LED. Before releasing reference-image export, try it from the app menu using a customized map and prepare a subsequent version. No live panel or Lightroom changes were made for these tests.

Validation: 191 Swift tests passed with zero failures in safe render mode on 20 September 2026. Tests cover all six navigation press/release events and reverse LED lookups, saved/imported old-map migration, custom-map preservation, and full-height PNG export. The default reference PNG was visually inspected through its final mode. `git diff --check` passed. This is software verification, not a physical hardware test.
