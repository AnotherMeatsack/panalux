import Foundation

public struct CommandCategory: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let items: [CatalogCommand]
}

public struct CatalogCommand: Identifiable, Hashable {
    public let id: String          // The API parameter/action string
    public let title: String       // Clean human-friendly title
    public let subtitle: String    // Explanation / technical API name
    public let isParameter: Bool   // true = for knobs/rings/balls; false = for buttons
    public let icon: String

    public init(id: String, title: String, subtitle: String = "", isParameter: Bool = true, icon: String = "slider.horizontal.3") {
        self.id = id
        self.title = title
        self.subtitle = subtitle.isEmpty ? id : subtitle
        self.isParameter = isParameter
        self.icon = icon
    }
}

public class CommandCatalog: ObservableObject {
    public static let shared = CommandCatalog()

    public let categories: [CommandCategory]
    private var lookup: [String: CatalogCommand] = [:]

    private init() {
        var cats: [CommandCategory] = []

        // 1. Basic Tone & Exposure
        cats.append(CommandCategory(
            id: "basic",
            title: "Basic Tone & Exposure",
            icon: "sun.max.fill",
            items: [
                CatalogCommand(id: "Exposure", title: "Exposure", subtitle: "Lightness adjustment (-5 to +5 EV)", isParameter: true, icon: "sun.max"),
                CatalogCommand(id: "Contrast", title: "Contrast", subtitle: "Tonal curve contrast (-100 to +100)", isParameter: true, icon: "circle.righthalf.filled"),
                CatalogCommand(id: "Highlights", title: "Highlights", subtitle: "Recovers bright highlight detail", isParameter: true, icon: "sparkles"),
                CatalogCommand(id: "Shadows", title: "Shadows", subtitle: "Opens up dark shadow detail", isParameter: true, icon: "moon.fill"),
                CatalogCommand(id: "Whites", title: "Whites", subtitle: "Sets the white clipping point", isParameter: true, icon: "square.fill"),
                CatalogCommand(id: "Blacks", title: "Blacks", subtitle: "Sets the black clipping point", isParameter: true, icon: "square")
            ]
        ))

        // 2. Color & White Balance
        cats.append(CommandCategory(
            id: "color",
            title: "Color & White Balance",
            icon: "thermometer.sun.fill",
            items: [
                CatalogCommand(id: "Temperature", title: "Color Temperature", subtitle: "Kelvin white balance (2000K–50000K)", isParameter: true, icon: "thermometer.sun"),
                CatalogCommand(id: "Tint", title: "Tint", subtitle: "Green to Magenta color tint", isParameter: true, icon: "paintpalette"),
                CatalogCommand(id: "Vibrance", title: "Vibrance", subtitle: "Smart saturation prioritizing skin tones", isParameter: true, icon: "wand.and.stars"),
                CatalogCommand(id: "Saturation", title: "Global Saturation", subtitle: "Overall color saturation (-100 to +100)", isParameter: true, icon: "circle.dashed")
            ]
        ))

        // 3. Presence & Texture
        cats.append(CommandCategory(
            id: "presence",
            title: "Presence & Texture",
            icon: "aqi.medium",
            items: [
                CatalogCommand(id: "Texture", title: "Texture", subtitle: "Enhances fine surface details", isParameter: true, icon: "square.grid.3x3.fill"),
                CatalogCommand(id: "Clarity", title: "Clarity", subtitle: "Midtone contrast enhancement", isParameter: true, icon: "eye.fill"),
                CatalogCommand(id: "Dehaze", title: "Dehaze", subtitle: "Cuts through atmospheric haze", isParameter: true, icon: "cloud.fog.fill")
            ]
        ))

        // 4. Color Grading (Resolve 3-Way Style)
        cats.append(CommandCategory(
            id: "grading",
            title: "Color Grading (3-Way Wheels)",
            icon: "circle.grid.cross.fill",
            items: [
                CatalogCommand(id: "SplitToningShadowHue", title: "Shadows Hue (Lift Ball)", subtitle: "Shadow color tint direction", isParameter: true, icon: "circle"),
                CatalogCommand(id: "SplitToningShadowSaturation", title: "Shadows Saturation (Lift Ball)", subtitle: "Shadow tint intensity", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "ColorGradeShadowLum", title: "Shadows Luminance (Lift Ring)", subtitle: "Lift luminance level", isParameter: true, icon: "dial.low.fill"),
                CatalogCommand(id: "ColorGradeMidtoneHue", title: "Midtones Hue (Gamma Ball)", subtitle: "Midtone color tint direction", isParameter: true, icon: "circle"),
                CatalogCommand(id: "ColorGradeMidtoneSat", title: "Midtones Saturation (Gamma Ball)", subtitle: "Midtone tint intensity", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "ColorGradeMidtoneLum", title: "Midtones Luminance (Gamma Ring)", subtitle: "Gamma luminance level", isParameter: true, icon: "dial.medium.fill"),
                CatalogCommand(id: "SplitToningHighlightHue", title: "Highlights Hue (Gain Ball)", subtitle: "Highlight color tint direction", isParameter: true, icon: "circle"),
                CatalogCommand(id: "SplitToningHighlightSaturation", title: "Highlights Saturation (Gain Ball)", subtitle: "Highlight tint intensity", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "ColorGradeHighlightLum", title: "Highlights Luminance (Gain Ring)", subtitle: "Gain luminance level", isParameter: true, icon: "dial.high.fill"),
                CatalogCommand(id: "ColorGradeGlobalHue", title: "Global Offset Hue", subtitle: "Global color tint direction", isParameter: true, icon: "globe"),
                CatalogCommand(id: "ColorGradeGlobalSat", title: "Global Offset Saturation", subtitle: "Global color tint intensity", isParameter: true, icon: "globe.americas.fill"),
                CatalogCommand(id: "ColorGradeGlobalLum", title: "Global Offset Luminance", subtitle: "Global luminance level", isParameter: true, icon: "sun.min.fill"),
                CatalogCommand(id: "ColorGradeBlending", title: "Color Grade Blending", subtitle: "Wheel overlap & range blend", isParameter: true, icon: "slider.horizontal.2.square.on.square"),
                CatalogCommand(id: "SplitToningBalance", title: "Color Grade Balance", subtitle: "Shadows vs Highlights bias", isParameter: true, icon: "scale.3d")
            ]
        ))

        // 5. HSL / Color Mixer (Individual Color Bands)
        cats.append(CommandCategory(
            id: "mixer",
            title: "HSL & Color Mixer",
            icon: "paintpalette",
            items: [
                CatalogCommand(id: "SaturationAdjustmentRed", title: "Red Saturation", subtitle: "Knob 1 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentOrange", title: "Orange Saturation", subtitle: "Knob 2 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentYellow", title: "Yellow Saturation", subtitle: "Knob 3 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentGreen", title: "Green Saturation", subtitle: "Knob 4 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentAqua", title: "Aqua Saturation", subtitle: "Knob 5 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentBlue", title: "Blue Saturation", subtitle: "Knob 6 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentPurple", title: "Purple Saturation", subtitle: "Knob 7 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "SaturationAdjustmentMagenta", title: "Magenta Saturation", subtitle: "Knob 8 in Mixer", isParameter: true, icon: "circle.fill"),
                CatalogCommand(id: "HueAdjustmentRed", title: "Red Hue Shift", subtitle: "Knob 1 (Hue Bank)", isParameter: true, icon: "paintpalette"),
                CatalogCommand(id: "HueAdjustmentOrange", title: "Orange Hue Shift", subtitle: "Knob 2 (Hue Bank)", isParameter: true, icon: "paintpalette"),
                CatalogCommand(id: "LuminanceAdjustmentRed", title: "Red Luminance", subtitle: "Knob 1 (Lum Bank)", isParameter: true, icon: "sun.max"),
                CatalogCommand(id: "LuminanceAdjustmentOrange", title: "Orange Luminance", subtitle: "Knob 2 (Lum Bank)", isParameter: true, icon: "sun.max")
            ]
        ))

        // 6. Detail & Optics
        cats.append(CommandCategory(
            id: "detail",
            title: "Detail, Sharpening & Optics",
            icon: "viewfinder",
            items: [
                CatalogCommand(id: "Sharpness", title: "Sharpening Amount", subtitle: "Edge contrast sharpening", isParameter: true, icon: "triangle"),
                CatalogCommand(id: "SharpenRadius", title: "Sharpening Radius", subtitle: "Size of halo details", isParameter: true, icon: "circle.dashed"),
                CatalogCommand(id: "SharpenDetail", title: "Sharpening Detail", subtitle: "Suppression of high-frequency noise", isParameter: true, icon: "dot.squareshape.split.2x2"),
                CatalogCommand(id: "SharpenEdgeMasking", title: "Edge Masking", subtitle: "Restricts sharpening to edges", isParameter: true, icon: "mask.fill"),
                CatalogCommand(id: "LuminanceSmoothing", title: "Noise Reduction (Luminance)", subtitle: "Smooths grain and digital noise", isParameter: true, icon: "bubbles.and.sparkles"),
                CatalogCommand(id: "ColorNoiseReduction", title: "Color Noise Reduction", subtitle: "Removes chroma speckles", isParameter: true, icon: "circle.hexagongrid.fill"),
                CatalogCommand(id: "PostCropVignetteAmount", title: "Post-Crop Vignette", subtitle: "Edge darkening or lightening", isParameter: true, icon: "camera.aperture")
            ]
        ))

        // 7. Perspective, Transform & Upright
        cats.append(CommandCategory(
            id: "transform",
            title: "Perspective & Upright",
            icon: "perspective",
            items: [
                CatalogCommand(id: "UprightAuto", title: "Upright: Auto", subtitle: "Automatic balanced perspective correction", isParameter: false, icon: "wand.and.rays"),
                CatalogCommand(id: "UprightLevel", title: "Upright: Level", subtitle: "Levels horizon lines", isParameter: false, icon: "level"),
                CatalogCommand(id: "UprightVertical", title: "Upright: Vertical", subtitle: "Corrects vertical keystone distortion", isParameter: false, icon: "arrow.up.and.down"),
                CatalogCommand(id: "UprightFull", title: "Upright: Full", subtitle: "Full level and vertical correction", isParameter: false, icon: "viewfinder.rectangular"),
                CatalogCommand(id: "UprightOff", title: "Upright: Off", subtitle: "Disables automatic upright", isParameter: false, icon: "xmark.circle"),
                CatalogCommand(id: "PerspectiveVertical", title: "Manual Vertical Keystone", subtitle: "Tilts perspective vertically", isParameter: true, icon: "arrow.up.and.down"),
                CatalogCommand(id: "PerspectiveHorizontal", title: "Manual Horizontal Keystone", subtitle: "Tilts perspective horizontally", isParameter: true, icon: "arrow.left.and.right"),
                CatalogCommand(id: "PerspectiveRotate", title: "Straighten / Rotate", subtitle: "Rotates the photo", isParameter: true, icon: "rotate.right"),
                CatalogCommand(id: "PerspectiveAspect", title: "Perspective Aspect Ratio", subtitle: "Compresses or expands aspect", isParameter: true, icon: "aspectratio"),
                CatalogCommand(id: "PerspectiveScale", title: "Perspective Scale", subtitle: "Zooms image within crop boundary", isParameter: true, icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
            ]
        ))

        // 8. Masks & Local Adjustments
        cats.append(CommandCategory(
            id: "masks",
            title: "Masks & Local Adjustments",
            icon: "lasso.and.sparkles",
            items: [
                CatalogCommand(id: "MaskNewRad", title: "New Radial Mask", subtitle: "Creates a circular/radial adjustment mask", isParameter: false, icon: "circle.circle"),
                CatalogCommand(id: "MaskNewGrad", title: "New Linear Gradient Mask", subtitle: "Creates a linear gradient mask", isParameter: false, icon: "rectangle.split.2x1"),
                CatalogCommand(id: "MaskNext", title: "Next Mask", subtitle: "Selects the next mask layer", isParameter: false, icon: "arrow.forward.circle"),
                CatalogCommand(id: "MaskPrevious", title: "Previous Mask", subtitle: "Selects the previous mask layer", isParameter: false, icon: "arrow.backward.circle"),
                CatalogCommand(id: "MaskNewBrush", title: "New Brush Mask", subtitle: "Paint a new mask", isParameter: false, icon: "paintbrush.pointed"),
                CatalogCommand(id: "MaskNewSubject", title: "Select Subject", subtitle: "AI subject mask. takes a moment", isParameter: false, icon: "person.crop.rectangle"),
                CatalogCommand(id: "MaskNewSky", title: "Select Sky", subtitle: "AI sky mask. takes a moment", isParameter: false, icon: "cloud.sun"),
                CatalogCommand(id: "MaskNewPeople", title: "Select People", subtitle: "AI people mask. takes a moment", isParameter: false, icon: "person.2"),
                CatalogCommand(id: "MaskNewObj", title: "New Object Mask", subtitle: "Click the object Lightroom should select", isParameter: false, icon: "cube.transparent"),
                CatalogCommand(id: "MaskNewBack", title: "New Background Mask", subtitle: "AI background mask. takes a moment", isParameter: false, icon: "rectangle.on.rectangle.angled"),
                CatalogCommand(id: "MaskNewColor", title: "New Color Range Mask", subtitle: "Sample a color to mask", isParameter: false, icon: "eyedropper.halffull"),
                CatalogCommand(id: "MaskNewLum", title: "New Luminance Range Mask", subtitle: "Mask by brightness", isParameter: false, icon: "circle.lefthalf.filled"),
                CatalogCommand(id: "MaskInvert", title: "Invert Selected Mask", subtitle: "Inverts mask coverage", isParameter: false, icon: "arrow.triangle.2.circlepath"),
                CatalogCommand(id: "MaskHide", title: "Show / Hide Overlay", subtitle: "Toggles the red mask overlay", isParameter: false, icon: "eye.slash"),
                CatalogCommand(id: "ChangeBrushSize", title: "Brush Size", subtitle: "Turn to grow or shrink the brush", isParameter: true, icon: "dial.medium"),
                CatalogCommand(id: "ChangeFeatherSize", title: "Brush Feather", subtitle: "Turn to soften or harden the brush", isParameter: true, icon: "dial.medium"),
                CatalogCommand(id: "local_Exposure", title: "Mask Exposure", subtitle: "Local exposure inside active mask", isParameter: true, icon: "sun.max"),
                CatalogCommand(id: "local_Contrast", title: "Mask Contrast", subtitle: "Local contrast inside active mask", isParameter: true, icon: "circle.righthalf.filled"),
                CatalogCommand(id: "local_Highlights", title: "Mask Highlights", subtitle: "Local highlights inside active mask", isParameter: true, icon: "sparkles"),
                CatalogCommand(id: "local_Shadows", title: "Mask Shadows", subtitle: "Local shadows inside active mask", isParameter: true, icon: "moon.fill"),
                CatalogCommand(id: "local_Clarity", title: "Mask Clarity", subtitle: "Local clarity inside active mask", isParameter: true, icon: "eye.fill"),
                CatalogCommand(id: "local_Texture", title: "Mask Texture", subtitle: "Local texture inside active mask", isParameter: true, icon: "square.grid.3x3.fill"),
                CatalogCommand(id: "local_Dehaze", title: "Mask Dehaze", subtitle: "Local dehaze inside active mask", isParameter: true, icon: "cloud.fog.fill"),
                CatalogCommand(id: "local_Amount", title: "Mask Overall Amount", subtitle: "Opacity of the active mask", isParameter: true, icon: "slider.horizontal.below.rectangle")
            ]
        ))

        // 9. Navigation, Rating & Flags
        cats.append(CommandCategory(
            id: "navigation",
            title: "Navigation, Flags & Stars",
            icon: "star.fill",
            items: [
                CatalogCommand(id: "Next", title: "Next Photo", subtitle: "Advances to next photo", isParameter: false, icon: "chevron.right"),
                CatalogCommand(id: "Prev", title: "Previous Photo", subtitle: "Returns to previous photo", isParameter: false, icon: "chevron.left"),
                CatalogCommand(id: "Select1Right", title: "Add Next Photo to Selection", subtitle: "Like Command-click the next photo", isParameter: false, icon: "plus.rectangle.on.rectangle"),
                CatalogCommand(id: "Select1Left", title: "Add Previous Photo to Selection", subtitle: "Like Command-click the previous photo", isParameter: false, icon: "minus.rectangle"),
                CatalogCommand(id: "Pick", title: "Flag as Pick", subtitle: "Flags photo as keeper", isParameter: false, icon: "flag.fill"),
                CatalogCommand(id: "Reject", title: "Reject / Blacklist", subtitle: "Marks photo for deletion", isParameter: false, icon: "xmark.bin.fill"),
                CatalogCommand(id: "RemoveFlag", title: "Remove Flag", subtitle: "Clears pick/reject flag", isParameter: false, icon: "flag.slash"),
                CatalogCommand(id: "SetRating1", title: "1 Star Rating", subtitle: "Sets 1 star", isParameter: false, icon: "star"),
                CatalogCommand(id: "SetRating2", title: "2 Star Rating", subtitle: "Sets 2 stars", isParameter: false, icon: "star"),
                CatalogCommand(id: "SetRating3", title: "3 Star Rating", subtitle: "Sets 3 stars", isParameter: false, icon: "star"),
                CatalogCommand(id: "SetRating4", title: "4 Star Rating", subtitle: "Sets 4 stars", isParameter: false, icon: "star"),
                CatalogCommand(id: "SetRating5", title: "5 Star Rating", subtitle: "Sets 5 stars", isParameter: false, icon: "star.fill"),
                CatalogCommand(id: "SetRating0", title: "Clear Rating (0 Stars)", subtitle: "Clears star rating", isParameter: false, icon: "star.slash"),
                CatalogCommand(id: "ToggleRed", title: "Color Label: Red", subtitle: "Toggles the red color label", isParameter: false, icon: "tag.fill"),
                CatalogCommand(id: "ToggleGreen", title: "Color Label: Green", subtitle: "Toggles the green color label", isParameter: false, icon: "tag.fill"),
                CatalogCommand(id: "ToggleYellow", title: "Color Label: Yellow", subtitle: "Toggles the yellow color label", isParameter: false, icon: "tag.fill")
            ]
        ))

        // 10. Workspace & Comparison Views
        cats.append(CommandCategory(
            id: "views",
            title: "Workspace & View Modes",
            icon: "rectangle.split.2x1.fill",
            items: [
                CatalogCommand(id: "ShoVwdevelop_before_after_horiz", title: "Before / After", subtitle: "Side-by-side before and after in Develop", isParameter: false, icon: "rectangle.split.2x1"),
                CatalogCommand(id: KeyCommands.beforeAfter, title: "Before / After (Toggle)", subtitle: "Press for Before, press again to come back. Types Lightroom's \\ key", isParameter: false, icon: "arrow.left.arrow.right"),
                CatalogCommand(id: "ShoVwRefHoriz", title: "Reference View", subtitle: "Side-by-side reference comparison", isParameter: false, icon: "rectangle.split.3x1"),
                CatalogCommand(id: "NextScreenMode", title: "Full Screen / Lights Out", subtitle: "Cycles cinema and full-screen modes", isParameter: false, icon: "arrow.up.left.and.arrow.down.right"),
                CatalogCommand(id: "ShowClipping", title: "Toggle Highlight/Shadow Clipping", subtitle: "Displays clipping warnings (J)", isParameter: false, icon: "eye.trianglebadge.exclamationmark"),
                CatalogCommand(id: "ToggleZoomOffOn", title: "Zoom 100% Toggle", subtitle: "Toggles 1:1 pixel zoom", isParameter: false, icon: "plus.magnifyingglass"),
                CatalogCommand(id: "ShoVwloupe", title: "Loupe View", subtitle: "Standard single-image view (E)", isParameter: false, icon: "photo"),
                CatalogCommand(id: "SwToMlibrary", title: "Library Grid", subtitle: "Switch to Library module (G)", isParameter: false, icon: "square.grid.2x2")
            ]
        ))

        // 11. Develop Actions & Presets
        cats.append(CommandCategory(
            id: "actions",
            title: "Develop Actions",
            icon: "bolt.fill",
            items: [
                CatalogCommand(id: "AutoTone", title: "Auto Tone", subtitle: "Automatic exposure and tone balancing", isParameter: false, icon: "sparkles"),
                CatalogCommand(id: "WhiteBalanceAuto", title: "Auto White Balance / Auto Temperature", subtitle: "WhiteBalanceAuto. Lightroom sets Kelvin and Tint", isParameter: false, icon: "sun.and.horizon"),
                CatalogCommand(id: "reset_wheel:LIFT", title: "Reset Shadows Wheel", subtitle: "Resets the left ball and ring", isParameter: false, icon: "arrow.counterclockwise.circle"),
                CatalogCommand(id: "reset_wheel:GAMMA", title: "Reset Midtones Wheel", subtitle: "Resets the center ball and ring", isParameter: false, icon: "arrow.counterclockwise.circle"),
                CatalogCommand(id: "reset_wheel:GAIN", title: "Reset Highlights Wheel", subtitle: "Resets the right ball and ring", isParameter: false, icon: "arrow.counterclockwise.circle"),
                CatalogCommand(id: "ResetAll", title: "Reset All Adjustments", subtitle: "Reverts photo to original import state", isParameter: false, icon: "arrow.counterclockwise"),
                CatalogCommand(id: "LRCopy", title: "Copy Develop Settings", subtitle: "Copies all adjustments (Cmd+C)", isParameter: false, icon: "doc.on.doc"),
                CatalogCommand(id: "LRPaste", title: "Paste Develop Settings", subtitle: "Pastes copied settings (Cmd+V)", isParameter: false, icon: "arrow.right.doc.on.clipboard"),
                CatalogCommand(id: "VirtualCopy", title: "Create Virtual Copy", subtitle: "Creates an uncommitted duplicate version", isParameter: false, icon: "plus.rectangle.on.rectangle"),
                CatalogCommand(id: "Undo", title: "Undo", subtitle: "Undoes last action", isParameter: false, icon: "arrow.uturn.backward.circle"),
                CatalogCommand(id: "Redo", title: "Redo", subtitle: "Redoes last undone action", isParameter: false, icon: "arrow.uturn.forward.circle"),
                CatalogCommand(id: "openExportWithPreviousDialog", title: "Export with Previous Settings", subtitle: "Exports selected photos using the last export preset", isParameter: false, icon: "square.and.arrow.up")
            ]
        ))

        cats.append(CommandCategory(
            id: "multiphoto",
            title: "Selection & Sync",
            icon: "arrow.triangle.2.circlepath",
            items: LightroomMenuActions.items.map {
                CatalogCommand(id: LightroomMenuActions.prefix + $0.id, title: $0.title, subtitle: $0.subtitle, isParameter: false, icon: $0.icon)
            } + [
                CatalogCommand(id: "Select1Left", title: "Add Previous Photo to Selection", subtitle: "Grows the selection to the left", isParameter: false, icon: "arrow.left.square"),
                CatalogCommand(id: "Select1Right", title: "Add Next Photo to Selection", subtitle: "Grows the selection to the right", isParameter: false, icon: "arrow.right.square"),
            ]
        ))

        // 12. Photoshop & External
        cats.append(CommandCategory(
            id: "photoshop",
            title: "Photoshop Round-Trip",
            icon: "square.stack.3d.forward.dottedline.fill",
            items: [
                CatalogCommand(id: "smart_roundtrip", title: "Open Selected as Layers in Photoshop", subtitle: "Sends, auto-aligns, then saves back on the next press", isParameter: false, icon: "square.stack.3d.up.fill"),
                CatalogCommand(id: "AddOrRemoveFromTargetColl", title: "Add / Remove from Bracket", subtitle: "Gathers this photo without changing the selection", isParameter: false, icon: "plus.rectangle.on.rectangle"),
                CatalogCommand(id: "bracket_roundtrip", title: "Send Bracket to Photoshop", subtitle: "Opens everything gathered as aligned layers", isParameter: false, icon: "square.3.layers.3d.top.filled"),
                CatalogCommand(id: "align_layers", title: "Auto-Align Layers", subtitle: "Lines up the open stack in Photoshop", isParameter: false, icon: "arrow.up.left.and.down.right.magnifyingglass"),
                CatalogCommand(id: "EditPhotoshop", title: "Edit Copy in Photoshop", subtitle: "Opens single file in Photoshop", isParameter: false, icon: "pencil.circle")
            ]
        ))

        // 13. Rewind — PanaLux's own recorder, not Lightroom's history
        cats.append(CommandCategory(
            id: "rewind",
            title: "Rewind",
            icon: "gobackward",
            items: [
                CatalogCommand(id: RewindCommands.scrub, title: "Scrub the Trail",
                               subtitle: "One click is one thing that changed. Turn faster to travel, stop to hold",
                               isParameter: true, icon: "backward.circle"),
                CatalogCommand(id: RewindCommands.speedFine, title: "Playback Speed · Fine",
                               subtitle: "Slow motion. Clockwise is faster, and it catches at 1×",
                               isParameter: true, icon: "tortoise.fill"),
                CatalogCommand(id: RewindCommands.speed, title: "Playback Speed",
                               subtitle: "Coarse dial, 0.05× to 32×. Clockwise is faster",
                               isParameter: true, icon: "hare.fill"),
                CatalogCommand(id: RewindCommands.play, title: "Play",
                               subtitle: "Watch your edits happen again. Press again to pause", isParameter: false, icon: "play.fill"),
                CatalogCommand(id: RewindCommands.playReverse, title: "Play Backward",
                               subtitle: "Watch them undo themselves. Press again to pause", isParameter: false, icon: "backward.fill"),
                CatalogCommand(id: RewindCommands.pause, title: "Pause",
                               subtitle: "Stops where it is. The photo stays put", isParameter: false, icon: "pause.fill"),
                CatalogCommand(id: RewindCommands.tip, title: "Back to Now",
                               subtitle: "Jumps the playhead to the newest edit", isParameter: false, icon: "forward.end.fill"),
                CatalogCommand(id: RewindCommands.mark, title: "Mark This",
                               subtitle: "Drops a landmark the playhead snaps to. \"I liked it\"", isParameter: false, icon: "bookmark.fill"),
                CatalogCommand(id: RewindCommands.tangentPrevious, title: "Previous Tangent",
                               subtitle: "Hops to the tangent before this one, at the same moment. A/B in one press",
                               isParameter: false, icon: "chevron.up"),
                CatalogCommand(id: RewindCommands.tangentNext, title: "Next Tangent",
                               subtitle: "Hops to the next tangent, at the same moment", isParameter: false, icon: "chevron.down"),
                CatalogCommand(id: RewindCommands.branch, title: "Branch Here",
                               subtitle: "Starts a new line of editing. The old one is kept, whole", isParameter: false, icon: "arrow.triangle.branch"),
                CatalogCommand(id: RewindCommands.previous, title: "Previous Landmark",
                               subtitle: "Steps back to the last mask, crop, preset, or mark", isParameter: false, icon: "chevron.left.2"),
                CatalogCommand(id: RewindCommands.next, title: "Next Landmark",
                               subtitle: "Steps forward to the next landmark", isParameter: false, icon: "chevron.right.2"),
                CatalogCommand(id: RewindCommands.peek, title: "Peek at Now",
                               subtitle: "Hold to see the tip without leaving the past", isParameter: false, icon: "eye.fill")
            ]
        ))

        // 14. Modes, holds & special keys
        var modeItems: [CatalogCommand] = []
        for (layer, blurb) in Self.modeBlurbs {
            let title = LayerNames.defaultTitle(layer)
            modeItems.append(CatalogCommand(id: "hold_layer:\(layer)", title: "Hold: \(title)", subtitle: blurb, isParameter: false, icon: LayerNames.symbol(layer)))
            modeItems.append(CatalogCommand(id: "layer:\(layer)", title: "Toggle: \(title)", subtitle: "Tap on, tap off. \(blurb)", isParameter: false, icon: LayerNames.symbol(layer)))
        }
        modeItems += [
            CatalogCommand(id: "modifier:FINE", title: "Hold: Fine", subtitle: "Knobs and balls move at a fraction of their speed", isParameter: false, icon: "scope"),
            CatalogCommand(id: "hold_compare", title: "Hold: Compare Before", subtitle: "Shows Before while held, back to Develop on release", isParameter: false, icon: "rectangle.lefthalf.inset.filled"),
            CatalogCommand(id: "hold_picker:mask_tools", title: "Hold: Mask Tool Wheel", subtitle: "Spin a ring or roll a ball to pick a mask tool, then release", isParameter: false, icon: "circle.grid.cross"),
            CatalogCommand(id: "pointer:move", title: "Move Pointer", subtitle: "Optional. This ball moves the mouse. Factory placement is the mouse for now", isParameter: true, icon: "cursorarrow.motion"),
            CatalogCommand(id: "pointer:size", title: "Resize Mask", subtitle: "Optional. This ring click-drags to grow or shrink a radial or linear mask", isParameter: true, icon: "arrow.up.left.and.arrow.down.right"),
            CatalogCommand(id: "pointer:click", title: "Click Pointer", subtitle: "Optional. Click at the pointer. Hold for click-and-drag", isParameter: false, icon: "cursorarrow.click"),
            CatalogCommand(id: "set_variant:HUE", title: "Mixer Bank: Hue", subtitle: "Switches Color Mixer knobs to hue", isParameter: false, icon: "paintpalette"),
            CatalogCommand(id: "set_variant:SAT", title: "Mixer Bank: Saturation", subtitle: "Switches Color Mixer knobs to saturation", isParameter: false, icon: "circle.fill"),
            CatalogCommand(id: "set_variant:LUM", title: "Mixer Bank: Luminance", subtitle: "Switches Color Mixer knobs to luminance", isParameter: false, icon: "sun.max.fill")
        ]
        cats.append(CommandCategory(
            id: "layers",
            title: "Modes & Holds",
            icon: "square.3.layers.3d",
            items: modeItems
        ))

        self.categories = cats

        // Index for fast lookup
        for cat in cats {
            for item in cat.items {
                lookup[item.id] = item
            }
        }
    }

    static let modeBlurbs: [(String, String)] = [
        ("MIXER", "Knobs 1–8 are the eight color bands"),
        ("TRANSFORM", "Perspective on the knobs, Upright on the keys"),
        ("MASK", "Same knobs as Base, pointed at the selected mask. Right ball places it; right ring sizes it."),
        ("CROP", "Knobs trim edges, center ring straightens"),
        ("CULL", "Keys rate and flag, rings scroll and zoom"),
        ("TONE", "Parametric tone curve on the knobs"),
        ("DETAIL", "Sharpening and noise reduction"),
        ("EFFECTS", "Vignette, grain, dehaze"),
        ("LENS", "Lens corrections and Lens Blur"),
        ("PRESETS", "Step presets, set the amount, fire slots 1–10"),
        ("OFFSET", "Temp and tint on the rings, global color on the right ball"),
        ("MULTISELECT", "Prev/Next Keyframe add photos to the selection"),
        ("REWIND", "Hold Undo: the centre ring scrubs the editing session, the right ring sets how far back")
    ]

    public func command(for id: String) -> CatalogCommand? {
        return lookup[id]
    }

    public func friendlyTitle(for id: String) -> String {
        if id.hasPrefix("hold_layer:") || id.hasPrefix("layer:") {
            return lookup[id]?.title ?? id
        }
        return CommandDatabase.shared.label(for: id)
    }
}
