import Foundation

/// The Lightroom side of gathering photos for a Photoshop blend.
///
/// Lightroom Classic has no way to build a scattered selection from the keyboard —
/// arrow keys always collapse it back to one photo. The Quick Collection does have
/// one: marking a photo never disturbs what is selected, so you can walk the
/// filmstrip, mark 1, 2, 3, skip 4, mark 5 and 6, and send exactly those.
public enum BracketCommands {
    /// Adds or removes the photo under the cursor. Lightroom's B key.
    public static let mark = "AddOrRemoveFromTargetColl"
    public static let showAction = LightroomMenuActions.prefix + "bracket_show"
    public static let clearAction = LightroomMenuActions.prefix + "bracket_clear"
}
