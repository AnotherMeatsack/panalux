# PanaLux v1.1.0

**Hold Undo. Watch the photo un-edit itself.**

## Rewind

Undo still undoes on a tap. Hold it and the whole editing session becomes a tape you can scrub.

- **Centre ring scrubs time.** Slowly, one edit at a time; quickly, minutes at a time. The photo un-edits itself continuously as the playhead moves, because PanaLux records every develop value the plugin reports — whether a knob here or the mouse in Lightroom moved it — not a list of history steps.
- **Right ring sets how far back.** 0–100% of the way toward the scrub point, so you can sit halfway between how the photo looks now and how it looked twenty minutes ago. Time in one hand, strength in the other.
- **Landmarks.** A whole settings table is captured around anything structural — a mask, a crop, a preset, a paste — so landing on one puts it back exactly, masks and crop included. Add Keyframe drops a mark of your own; the playhead snaps to it.
- **Nothing is ever destroyed.** Rolling back does not truncate the future: the tip stays, and Next Still returns to it. Editing from a rolled-back point starts a branch and keeps the line you left, whole. Branch from a branch as often as you like.
- **Wipe Still peeks at now** without leaving the past, for A/B without giving up your place.
- Letting go of Undo leaves the photo wherever the playhead is. You can stop anywhere.
- The trail is kept per photo under `~/Library/Application Support/PanaLux/Trails` and survives quitting. Every part of the gesture is remappable, like every other control on the panel.

The readout grows to show the tape: the playhead stands still while time moves under it, landmark names fade in as they approach, the twelve knob values roll rather than jump, and the future a rollback has gone past stays on screen, dimmed, so it is obvious nothing was thrown away.

## Also in this release

- **Grab Still round-trip is reliable.** Photoshop is addressed by document id rather than whatever is frontmost, the hand-off waits for every layer before aligning, and the flatten comes back to Lightroom from a real Photoshop document.
- **Lightroom stays in front when Grab Still fires.** Opening Photoshop first hid Lightroom's Photo menu; the round-trip now clicks Open as Layers first and resends if the stack lands as one photo.
- **Shareable maps.** Export writes the full setup — map, fine speed, mask knob layout, key calibration — as one `.panalux.json` anyone can drop on PanaLux.
- **In-app bug reports.**

## Upgrading

Your map is kept. Holding Undo is added to it only if you had not already given that key a hold of your own. Update the Lightroom plugin from the app when PanaLux asks: Rewind needs the new PanaLux Bridge, which reports which photo is on screen and can hand over whole settings tables.

Requires macOS 14 or later, a USB-C Micro Color Panel, and Lightroom Classic.

> PanaLux is a free, unofficial, open-source macOS app. It is not affiliated with, endorsed by, or related to Blackmagic Design, Adobe, or Apple. It talks to a Micro Color Panel you already purchased and to Lightroom Classic through PanaLux Bridge, a lightly modified copy of the free community plugin MIDI2LR. You are not buying anything. The author is not selling the panel, Lightroom, or this software.

MIT for the app. PanaLux Bridge is GPL-3.0 because it is based on MIDI2LR.
