import Foundation

public struct PanelControlMapping {
    /// Maps 58 SVG semantic IDs to Profile / Engine control keys
    public static let svgToProfile: [String: String] = [
        // 12 Encoders
        "encoder_y_lift": "Y_LIFT",
        "encoder_y_gamma": "Y_GAMMA",
        "encoder_y_gain": "Y_GAIN",
        "encoder_contrast": "CONTRAST",
        "encoder_pivot": "PIVOT",
        "encoder_mid_detail": "MID_DETAIL",
        "encoder_color_boost": "COL_BOOST",
        "encoder_shadows": "SHAD",
        "encoder_highlights": "HI_LIGHT",
        "encoder_saturation": "SAT",
        "encoder_hue": "HUE",
        "encoder_lum_mix": "LUM_MIX",
        
        // 3 Independent Annular Rings
        "ring_left": "RING_LIFT",
        "ring_center": "RING_GAMMA",
        "ring_right": "RING_GAIN",
        
        // 3 Trackballs
        "trackball_left": "TB_LIFT",
        "trackball_center": "TB_GAMMA",
        "trackball_right": "TB_GAIN",
        
        // 40 Buttons
        "button_auto_color": "AUTO_COLOR",
        "button_offset": "OFFSET",
        "button_copy": "COPY",
        "button_paste": "PASTE",
        "button_undo": "UNDO",
        "button_redo": "REDO",
        "button_delete": "DELETE",
        "button_reset": "RESET_ALL",
        "button_bypass": "BYPASS",
        "button_disable": "DISABLE",
        "button_user": "USER",
        "button_loop": "LOOP",
        "button_corner_upper_left": "SHIFT",
        "button_corner_lower_right": "CORNER_LOWER_RIGHT",
        "button_play_still": "PLAY_STILL",
        "button_wipe_still": "WIPE_STILL",
        "button_grab_still": "GRAB_STILL",
        "button_mute": "H/LITE",
        "button_viewer": "VIEWER",
        "button_cursor": "CURSOR",
        "button_select": "SELECT",
        "button_add_node": "ADD_NODE",
        "button_add_window": "ADD_WINDOW",
        "button_add_keyframe": "ADD_KEYFRM",
        "button_reset_lift": "RESET_LIFT",
        "button_reset_gamma": "RESET_GAMMA",
        "button_reset_gain": "RESET_GAIN",
        "button_previous_still": "PREV_STILL",
        "button_next_still": "NEXT_STILL",
        "button_previous_keyframe": "PREV_KEYFRM",
        "button_next_keyframe": "NEXT_KEYFRM",
        "button_previous_node": "PREV_NODE",
        "button_next_node": "NEXT_NODE",
        "button_previous_frame": "PREV_FRAME",
        "button_next_frame": "NEXT_FRAME",
        "button_previous_clip": "PREV_CLIP",
        "button_next_clip": "NEXT_CLIP",
        "button_transport_reverse": "PLAY_REV",
        "button_transport_forward": "PLAY",
        "button_transport_stop": "STOP"
    ]
    
    /// Reverse mapping from Profile / Engine key to SVG semantic ID
    public static let profileToSvg: [String: String] = {
        var dict: [String: String] = [:]
        for (svg, prof) in svgToProfile {
            dict[prof] = svg
        }
        // Aliases and hardware variations
        dict["TB_LIFT_X"] = "trackball_left"
        dict["TB_LIFT_Y"] = "trackball_left"
        dict["TB_GAMMA_X"] = "trackball_center"
        dict["TB_GAMMA_Y"] = "trackball_center"
        dict["TB_GAIN_X"] = "trackball_right"
        dict["TB_GAIN_Y"] = "trackball_right"
        dict["H/LITE"] = "button_mute"
        dict["MUTE"] = "button_mute"
        return dict
    }()
    
    public static func toProfileId(_ id: String) -> String {
        return svgToProfile[id] ?? id
    }
    
    public static func toSvgId(_ id: String) -> String {
        return profileToSvg[id] ?? id
    }
}
