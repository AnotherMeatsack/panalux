<img src="Packaging/AppIcon-1024.png" alt="PanaLux app icon" width="96" height="96">

# PanaLux

**One panel. Every job.**

I bought a Micro Color Panel for Resolve. I also edit stills. I wanted the panel I already paid for to do more than one job.

PanaLux makes it work in Lightroom Classic. Turn the knobs, grade with the trackballs, and hold a key when you need a different set of controls. It lives in the macOS menu bar. Close the window and the panel keeps working.

> PanaLux is a free, unofficial, open-source macOS app. It is not affiliated with, endorsed by, or related to Blackmagic Design, Adobe, or Apple. It talks to a Micro Color Panel you already purchased and to Lightroom Classic through PanaLux Bridge, a lightly modified copy of the free community plugin MIDI2LR. You are not buying anything. The author is not selling the panel, Lightroom, or this software.

![PanaLux title card: One panel. Every job.](Docs/screenshots/intro-0-03.0.png)

## What you need

macOS 14 or later, a Blackmagic Micro Color Panel connected over USB-C, and Lightroom Classic. PanaLux Bridge, the Lightroom plugin, installs from the app.

## Install

1. Download the DMG from this repository's Releases page.
2. Drag PanaLux to Applications and open it.
3. PanaLux is not notarized. For the first launch, go to **System Settings > Privacy & Security > Open Anyway**.
4. Run the setup assistant. Install PanaLux Bridge, then check the Lightroom and panel connections. Grant Accessibility permission for functions such as Photoshop, copy/paste, and sync.

You can replay the intro from the menu bar. The hands-on tour advances when you actually turn a knob or hold a key. You can follow it with Lightroom on another display.

## What the panel does

The starting map keeps the three trackballs on shadow, midtone, and highlight color. Each ball adjusts hue and saturation. The three rings adjust luminance for those same ranges.

From left to right, the twelve knobs control **Blacks, Exposure, Whites, Contrast, Clarity, Texture, Vibrance, Shadows, Highlights, Saturation, Temperature, and Color blending**.

The keys handle jobs such as copy, paste, undo, redo, previous/next photo, export, and the Photoshop round-trip.

Use both hands. Several knobs, all three balls, and the rings can move together. Lightroom updates as you work, and the readout can show up to six controls at once.

## Hold a key. Get a new panel.

Hold Up Shift and the first eight knobs become the eight Color Mixer bands. Let go and they return to their previous jobs. A tap can also leave a mode on until you tap again.

Every key has separate **On tap** and **While held** assignments. The table below is the factory map, not a fixed set of rules.

![The panel changes from Base to Color Mixer, Upright and Transform, and Masks.](Docs/screenshots/hold-modes.gif)

### Factory modes

| Key and gesture | What it does |
| --- | --- |
| **Hold Up Shift** | Color Mixer. Knobs 1-8 control Red, Orange, Yellow, Green, Aqua, Blue, Purple, and Magenta. Reset Lift, Reset Gamma, and Reset Gain select hue, saturation, and luminance. |
| **Hold User** | Upright and Transform. Knobs become perspective controls. Auto Color becomes Upright Auto while User is held. |
| **Tap or hold Cursor** | Masks. Knobs adjust the selected mask, keeping matching controls in their Base positions. You can turn that behavior off in Settings and build a custom mask layout. |
| **Hold Add Node** | Opens the circular mask tool wheel. Choose a tool and operation, then release to create it. Place it with the mouse. |
| **Hold Viewer** | Crop and Straighten. Knobs trim edges, the center ring straightens, and keys select aspect presets. |
| **Hold Select** | Cull in Library. Keys rate, flag, and color-label photos. Rings scroll photos and zoom. |
| **Tap Offset** | Temperature and tint on the rings, with global color on the right ball. |
| **Hold Down Shift** | Prev/Next Keyframe add photos to the selection, like Command-click. |
| **Hold Wipe Still** | Shows Before. Tap instead for side-by-side. |
| **Hold Auto Color** | Tone Curve, with parametric regions on the knobs. |
| **Hold H / Lite** | Detail, including sharpening and noise reduction. |
| **Hold Play Still** | Effects, including vignette, grain, and dehaze. |
| **Hold Grab Still** | Lens and Optics, including corrections and Lens Blur. Tap instead for the Photoshop round-trip. |
| **Hold Play** | Presets. Step through presets, adjust the amount, and trigger slots 1-10. Assign the Lightroom presets to those slots in the plugin options. |

## Hold Add Node. Pick a mask.

Hold Add Node and a circular tool wheel appears over Lightroom. Roll a ball to choose a tool. The lit wedge shows what you will get. Release Add Node to create it.

![Selecting Linear, Radial, Brush, and Subject from the mask tool wheel.](Docs/screenshots/mask-wheel.gif)

There are twelve tools: Linear, Radial, Brush, Object, Subject, Sky, People, Background, Color Range, Luminance, Depth, and Landscape.

Place the mask with the mouse. Knobs then grade that mask, with Exposure still on the Exposure knob and so on.

**Coming soon:** placing radial, linear, and brush masks with the trackballs and rings, so you can stay off the mouse. The wheel, the combine modes, and local knobs ship now.

![The panel's Add Node key and the wheel with New Radial selected.](Docs/screenshots/intro-6-02.5.png)

### New, Add, Subtract, or Intersect

While the wheel is open, the left ring chooses New, Add, Subtract, or Intersect. Prev Node, Next Node, Prev Frame, and Next Frame can also select those operations. The center readout names the tool and operation before you release.

![The mask wheel with Add Subject selected.](Docs/screenshots/hud-mask-wheel.png)

Once a mask is selected, the matching adjustment knobs stay in familiar positions. Other keys can move between masks, invert, hide, delete, or select subject and sky.

## Make the map yours

The main window is one drawing of the panel. Click a control or touch it on the hardware, and the inspector follows. Search the catalog of **999 Lightroom commands** from MIDI2LR. Drag a command tile onto a knob or key. Every control can be remapped.

Each key has an On tap job and a While held job. A hold can activate a mode, make adjustments slower with Fine, show a comparison, put a focused slider on the knobs, open the mask wheel, or do nothing.

Copy, paste, or swap controls. Undo map edits with Command-Z and redo with Shift-Command-Z. Use the editing picker to work on Base or any mode without holding its key down.

Command-K finds a command so you can run it once, assign it, see where it is mapped, or temporarily put it on a knob. Hover a key to see arrows to the knobs and wheels it affects. If a mode is held, the hover view shows that mode's map rather than Base.

## Readout

The Micro Color Panel has no screens. PanaLux puts a small readout under the menu bar, below the camera notch where there is one, on Lightroom's display.

![Contrast readout showing Knob 4, a position indicator, and a value of +24.](Docs/screenshots/hud-knob.png)

It shows the value you are changing, a spinning knob or ring, and a vectorscope for trackballs. While you hold a mode, it can list all twelve knob names. The Color Mixer can show its eight color dots.

Move several controls and the readout follows up to six at once.

![Five simultaneous readouts for exposure, contrast, shadows, midtones, and highlight luminance.](Docs/screenshots/hud-multi5.png)

**HOLD** means the mode ends when you let go. **ON** means you tapped it on.

Choose Full, Minimal, or Hidden. Set the readout to tuck away after 2, 4, 8, 15, or 30 seconds, or leave it until the next change.

## Working on several photos

Bypass selects all photos in the filmstrip. Disable opens Sync Settings; press it again to click Synchronize. Copy and Paste handle Develop settings. Undo, Redo, and Reset are available too.

These actions use Lightroom's menus and shortcuts, so macOS asks for Accessibility permission.

## Safety

**Pause Output** stops commands from reaching Lightroom. The readout still shows what would have happened.

**Safe Setup** lets you preview knob adjustments on screen without changing the photo. Held keys still work. Use Pause Output when you need all Lightroom output stopped.

**Back to Base** turns every mode off. It is also available from the menu bar.

PanaLux reads the current value from Lightroom before moving a slider rather than starting it at zero. It makes map backups at launch and before an import, preset, or reset. If Lightroom is missing or a control is unmapped, the readout says so.

At the end of the hands-on tour, choose **Keep Changes** or **Put the Photo Back**.

## Photoshop

Tap Grab Still to open the selected photos as layers in Photoshop, auto-align them, flatten, save, and bring Lightroom forward again. This round-trip needs Accessibility permission.

Holding Grab Still does a different job: it opens the Lens and Optics controls.

## DaVinci Resolve

When Resolve is open, PanaLux releases the panel so Resolve can use it. PanaLux takes the panel back when Resolve quits. The handoff follows whether Resolve is open, not which window is in front.

There is also an option to quit Resolve automatically. It is off by default.

## Share your maps

**Maps → Export Map** writes a `.panalux.json` file. That file is the whole setup: every knob, ring, ball, key, and mode, plus Fine speed, mask knob layout, and key calibration. It also includes a readable `readme` list of what each control does, so you can open it in a text editor.

Drop a map on the PanaLux window, or choose **Maps → Import**. Importing backs up your current map first. **Copy Map** puts the same file on the clipboard so you can paste it into a message.

You can also print a Reference Card for the current map, including every mode.

Preset, Keywords, Key 1-40, and Command Series slots are defined in Lightroom under **File > Plug-in Extras > General options**. PanaLux triggers those slots. A Command Series such as Auto Tone, then Upright, then Lens Corrections can live on one key.

Post the maps you build. I'd like to see what people put under their hands for different kinds of photography.

## Report a bug

Menu bar or Help → **Report a Bug**. Write what happened. PanaLux opens a GitHub issue with version, connections, and the active mode already filled in, and puts a copy of your map in Finder so you can attach it.

## Build from source

Requires Xcode 26 or later.

```bash
./Scripts/build_app.sh     # PanaLux.app (universal, ad-hoc signed, plugin included)
./Scripts/create_dmg.sh    # PanaLux-<version>.dmg for a release
swift test                 # unit tests
swift Scripts/make_icon.swift .   # regenerate the app icon (then iconutil, see script)
Scripts/make_bridge_plugin.sh /path/to/MIDI2LR.lrplugin   # refresh the bundled plugin from a MIDI2LR release
```

Quit PanaLux before rebuilding. Only one copy can use the panel.

### Layout

```
Sources/PanaLux/
  App/        launch, setup, tour, resource and file locations
  Hardware/   USB HID input and key lights
  Bridge/     engine (holds, modes, readout), Lightroom connection, Photoshop round-trip
  Model/      map format, factory map, command catalog, backups
  UI/         Map window, inspector, settings, command palette, notch readout
  Resources/  panel drawing, command list, factory map
Packaging/
  PanaLux Bridge.lrplugin   the Lightroom plugin PanaLux installs (GPL-3.0, see its NOTICE.txt)
```

## Troubleshooting

- **Lightroom shows "waiting."** Install the plugin from Settings, restart Lightroom, and quit the MIDI2LR app if it's open. That app holds the plugin's connection.
- **Panel not found.** Use a data-capable USB-C cable. If Resolve is open, the panel is with Resolve.
- **A knob does nothing.** The readout says why: not mapped, Lightroom not connected, or output paused.
- **Something feels stuck.** Use Back to Base in the menu bar.

## License

MIT for the PanaLux app. See [LICENSE](LICENSE).

The bundled Lightroom plugin, PanaLux Bridge, is GPL-3.0 because it is based on [MIDI2LR](https://github.com/rsjaffe/MIDI2LR). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
