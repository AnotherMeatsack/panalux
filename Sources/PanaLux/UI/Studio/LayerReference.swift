import Foundation

enum LayerReference {
    static func html(for engine: StudioEngine) -> String {
        SVGPanelReference.document(states: SVGPanelReference.states(for: engine), atlas: true)
    }
}
