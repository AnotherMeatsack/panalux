# Physical panel reference

Both the momentary guide and the export browser use `micro-color-panel.svg`, the same geometry and 58 semantic IDs as the mapper. Assignment cards are anchored to those controls. The top-level diagram preserves the whole panel; region zoom and enlarged-section printing make dense button assignments readable. Full labels are retained below the diagram and in PNG export whenever a card needs shortening.

## Using it

- Hold Previous Still + Next Still within 300 ms. Release either to dismiss. The nonactivating panel permits mode/gesture/zoom clicks without deliberately activating PanaLux.
- Click **Print / Panel Guide** in the toolbar, or **Help → Panel Reference · View / Print / Save…**. Select a map/mode/bank/program/combination and Turn / Tap, Press / Hold or Both views.
- Print this view preserves the selected region. Print complete guide prints every physical diagram with both gestures. Print enlarged sections prints five regions per gesture for the selected map. Choose Save as PDF in the browser print dialog.
- Save selected PNG exports the named gesture of the selected map, including complete overflow labels. Help → Save Current Panel Image exports both live gestures in one PNG.

## Implementation and checks

`SVGPanelReference` overlays effective bindings onto a read-only copy of the existing SVG. `PanelReference` captures the live state. `ReferencePeekWindow` shows the same document with export controls hidden; `ReferenceCard` opens a local HTML document in the browser. Layer inheritance, banks, programs and combinations are separate selectable diagram states. `ReferenceImageExport` retains the native current-map PNG path.

`ReferenceChordTests` cover both key orders, release orders, singleton events, timeout/unrelated-key flushing, repeated downs, reset/disconnect, synthetic hardware dispatch and escaping/custom assignments. `ReferenceImageTests` verify native rendering and bottom-of-document retention. `Tests/ReferencePrint/check_print.cjs` verifies all 58 controls in every diagram, responsive width, inspector interaction, region zoom, browser PNG download and complete/enlarged PDF generation in isolated headless Chrome.

Physical chord timing and focus over Lightroom/full-screen remain hands-on acceptance checks. No map is changed by viewing or exporting a reference.
