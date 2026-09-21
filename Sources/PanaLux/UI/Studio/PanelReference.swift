import Foundation

/// A live snapshot rendered on the same physical SVG as the mapper.
struct PanelReference {
    let profile: Profile
    let context: String
    static func current(_ engine: StudioEngine) -> PanelReference {
        PanelReference(profile: engine.currentHelpProfile(), context: engine.referenceContext)
    }
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    var state: ReferencePanelState { .init(title: "Live · Current controls", context: context, profile: profile) }
    var section: String { SVGPanelReference.sheet(state, holds: false) + SVGPanelReference.sheet(state, holds: true) }
    var html: String {
        SVGPanelReference.document(states: [state]).replacingOccurrences(of: "data-gesture=taps", with: "data-gesture=both")
            .replacingOccurrences(of: "</style></head>", with: ".toolbar,.hint,.inspector{display:none}</style></head>")
    }
    var peekHTML: String { SVGPanelReference.document(states: [state], peek: true) }
}
