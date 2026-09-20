# PanaLux v1.2.2

Knob presses and button combinations make the panel easier to customize. Rewind+ gains a larger mouse workspace, and Map Library lets you save, share and mix setups.

- **Clearer Rewind rings.** Hold Undo: right ring scrubs the timeline, left ring visits landmarks and center ring switches tangents. The complete old factory speed layout migrates automatically; custom layouts are preserved. Settings offers Use right-ring timeline layout.
- **Map Library & Community.** Name and save setups, switch between them, preview map files and browse reviewed community maps. The gallery starts with the official factory map; community submissions appear after review.
- **Borrow just what you want.** Compare source and destination side by side. Click controls or drag sections across, choose Whole control, Tap only or Hold only, then Merge Selected. Referenced hold modes come along without replacing unrelated modes. Review included modes before applying; map changes are backed up and undoable. Calibration and personal app settings stay yours.
- **Share and suggest.** Export & Share opens a public GitHub draft for your map file. Suggest a Feature collects an idea and workflow in a separate draft. A GitHub account is required to submit; nothing is sent automatically. Preset slots refer to the recipient’s own Lightroom configuration.
- **Reliable quick presses.** LED updates wait for button release and stop hiding subsequent quick releases. Lightroom readback clears the temporary Updating display after a reset.
- **Expanded Rewind+.** Hover briefly over the preview or click it to open a pinned glass workspace. Use the mouse slider, playback controls and selectable branch nodes. Escape or Collapse returns to the small readout.
- **Visual merging and cleanup.** Inspect a source node, choose slider settings and merge into a new result without removing either source. Merge results show both input connections. Inactive leaf tangents can be deleted with confirmation and restored with Undo Delete during the current photo session. Branches used by another tangent, the original and the current branch are protected.
- **Keyboard controls.** Click the expanded workspace, then use Space to play/pause, arrows to step, Command-M to merge checked settings, Shift-Command-N for a new tangent and Command-Delete to delete an eligible selected tangent.
- **A recognizable menu icon.** PanaLux’s menu-bar icon now uses a monochrome panel with six knobs and three trackballs, matching the app artwork.
- **Reset feedback.** The notch knob graphic zips back with a short spring animation (respecting Reduce Motion) and displays Lightroom’s reported reset value, including temperature defaults.
- **Press to reset.** All twelve knob presses reset their current Lightroom parameter, including mode, mask and focus assignments. Knobs mapped to commands without a reset show an explanation.
- **Your own combinations.** Hold one or more buttons, then press another button or knob to run a preset slot, shortcut or command. Combinations take priority over mode keys; the most specific matching combination wins. Existing hold behaviors remain active, but a used modifier’s tap does not also fire.
- **Hands free programming.** Open **Presses & Combinations** in the inspector. Capture a gesture, release the panel, then drag or click a command. Or build it with the mouse. Highlighted controls and animated, removable chips keep the selected gesture visible. Programming pauses output until Done.
- **Separate wheel resets.** Up Shift + Reset Lift/Gamma/Gain resets only the corresponding ball. Down Shift + the same Reset button resets only its luminance ring. Reset alone resets both. Lift controls shadows, Gamma midtones and Gain highlights. These editable combinations take precedence over the original Color Mixer bank keys; remove them to restore that behavior.
- **What’s New.** Read the update history from the menu bar or Settings, even offline. Sparkle update packages now carry the same release notes.
- Updated the animated intro, hands-on tour and quick reference. The Rewind+ demo highlights all three rings, then illustrates expanding, inspecting a source, selecting sliders and creating a merged result. Preset slots still need to be configured in Lightroom’s plug-in options.

Developer ID signed; not notarized.

---

# PanaLux v1.2.1

Restores useful feedback throughout fractional scrubbing: the current effect and interpolated value stay visible between recorded stops, with a detailed bottom readout and elapsed/total time.

- Live previews now travel as coherent frames. PanaLux waits for Lightroom to apply and yield for rendering before sending the newest pending frame, preventing an ever-growing stream of individual slider updates. Bridge 6.3.0.6 must be reloaded in Lightroom Plug-in Manager; an older bridge falls back to legacy delivery.
- Unchanged full-refresh reports no longer create hundreds of phantom editing stops. Existing redundant samples are skipped during playback without deleting saved history.
- Tangent and mark snapshots wait behind pending preview delivery. The branch baseline retains the exact fractional slider values you chose, and a panel edit immediately after releasing Undo starts a tangent instead of being mistaken for a playback echo.

Developer ID signed; not notarized. Selective merges still exclude mask and crop tables, whose complete Lightroom SDK roundtrip fidelity is not established.

---

# PanaLux v1.2.0

Rewind responds to every small ring movement, with precise recorded stops and velocity-sensitive travel. Sparse continuous slider edits interpolate while scrubbing; discrete and structural changes keep their boundaries. The timeline and stronger rounded perimeter ticks follow the same playhead without delayed position easing. The edge light holds briefly at pauses, then fades.

- One PanaLux process owns the panel, bridge and overlays, even when launched from different copies. Rewind retries a held request when Lightroom supplies the photo identity late.
- PanaLux Bridge 6.3.0.5 resends photo identity on refresh and tolerates missing mask values/ranges without nil arithmetic. Reload the updated plugin in Lightroom's Plug-in Manager.
- **Program Buttons** lets every physical button select its tap or hold without sending edits. Drop an action onto the selected key. Holds accept keyboard shortcuts and Rewind actions; mode-specific tap/hold assignments remain separate.
- **Tangents** names saved versions, opens a chosen version and merges checked recorded sliders into a new tangent. Both sources stay saved. This merge excludes local mask sliders and crop; it does not merge opaque mask/settings tables.
- **BYPASS** defaults to the repeatable Lightroom backslash Before/After toggle. Existing saved maps keep their assignments; choose **Before / After (Toggle)** to change one.
- Wider mode readouts and shorter mask instructions improve legibility. The intro and tour explain programming, fractional travel, tangents and merging.
- An optional Settings layout uses the centre ring for travel, left for landmarks and right for tangents. Existing outer-ring assignments are preserved until chosen. Trackballs rest during Rewind; release Undo to grade.
- Sparkle updates are available from **Check for Updates…**, backed by signed update archives and an HTTPS feed. Earlier releases require one manual upgrade to gain this feature.

This release is Developer ID signed. Notarization remains unavailable while the Apple account issue is unresolved. Real mask/crop settings-table fidelity remains dependent on Lightroom SDK behavior; the nil-value regression checks do not establish complete structural roundtrip coverage.

See [update publishing instructions](Docs/UPDATES.md).

---

# PanaLux v1.1.0

**Now featuring Rewind+.** Hold Undo and watch your edit un-edit itself. Then branch it.

![Rewind+ with three tangents](Docs/screenshots/hud-rewind-tangents.png)

## Rewind+

Undo still undoes on a tap. Hold it and the whole editing session becomes a tape you can scrub, replay, and branch. (The plus is a joke. The feature isn't.)

- **The centre ring is a jog wheel.** One click is one thing you changed, so you can stop on the exact number you had, in a thirty-second edit or a two-hour one. Turn faster and it accelerates smoothly to cross a long session; stop turning and it holds.
- **Play it back.** Play and Play Reverse replay your edits as they happened. The same key again pauses; Stop pauses too. Long quiet stretches play through in half a second. The left ring is a fine speed dial and the right a coarse one, 0.05× to 32×, both catching at 1×.
- **Tangents.** Edit from a rolled-back moment and a new tangent starts, with a notice, and every readout wears that tangent's badge while you are on it. The line you left is kept whole. Prev / Next Node hop between tangents at the same moment, or from the end of one to the end of the next, so you can flip between where each finished.
- **A timeline worth looking at.** A large readout on a display-rate timeline: the playhead glides on a critically damped spring, the ticks under it swell and blip with each step, the tape re-zooms to how densely you were editing, and every tangent is a lane with forks curving off. The panel widens for it and grows with the number of tangents. The notch shows what changed at each step, where you are among them, and what all twelve knobs read there.
- **Tune the feel** in Settings > Rewind: click size and spin speed apply on the next turn.
- **Landmarks and nothing lost.** A whole settings table is captured around a mask, crop, preset, or paste, so landing on one restores it exactly. Rolling back never truncates the future. Add Keyframe marks a moment; Wipe Still peeks at now; Next Still returns to it.

The trail is kept per photo under `~/Library/Application Support/PanaLux/Trails` and survives quitting. Every part of the gesture is remappable, like every other control on the panel.

## Fixed

- **Temperature no longer stops at 3000 K.** The Lightroom plugin, inherited from MIDI2LR, squeezed Temperature into a 3000-9000 K window, so after Auto Color the knob could not go warmer than 3000 K. It also made the notch's Kelvin readout wrong. Temperature now spans Lightroom's own 2000-50000 K, the readout matches Lightroom, and the knob feels exactly as it did.
- **Grab Still sends the whole stack, and the save is checked.** Photoshop is shown again before each send (it was left hidden after a save, and Lightroom handed a hidden Photoshop only the first photo), and the automatic resend retries with Lightroom in front instead of giving up on the first refusal.
- **A save can no longer vanish.** Every call to Photoshop used to share one script file, so a background check could overwrite a save's script before Photoshop read it. Each call now has its own, one at a time. The file is confirmed on disk before the blend is closed; if Photoshop does not confirm it, the blend stays open and the notch says so. Pressing Grab Still while auto-align is running waits instead of flattening a half-aligned stack.
- **Nothing fails silently.** A stack that never arrives, a refused resend, or an unconfirmed save is now written to the hand-off log and shown on the notch.
- **Photoshop is addressed by document id** rather than whatever is frontmost, and the hand-off waits for every layer before aligning.
- **Lightroom stays in front when Grab Still fires.**
- **Shareable maps.** Export writes the full setup as one `.panalux.json` anyone can drop on PanaLux.
- **In-app bug reports.**

## Upgrading

Your map is kept. The new Rewind keys are added to it only where you had not already given a key a job. Update the Lightroom plugin from the app when PanaLux asks, then restart Lightroom: Rewind needs the new PanaLux Bridge, and the Temperature fix lives in it.

Requires macOS 14 or later, a USB-C Micro Color Panel, and Lightroom Classic.

> PanaLux is a free, unofficial, open-source macOS app. It is not affiliated with, endorsed by, or related to Blackmagic Design, Adobe, or Apple. It talks to a Micro Color Panel you already purchased and to Lightroom Classic through PanaLux Bridge, a lightly modified copy of the free community plugin MIDI2LR. You are not buying anything. The author is not selling the panel, Lightroom, or this software.

MIT for the app. PanaLux Bridge is GPL-3.0 because it is based on MIDI2LR.
