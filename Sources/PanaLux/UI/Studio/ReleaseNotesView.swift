import SwiftUI
import AppKit

struct ReleaseNotesView: View {
    private let paragraphs = (AppResources.string("ReleaseNotes", "md") ?? "Release notes are unavailable.")
        .components(separatedBy: "\n\n")
        .flatMap { $0.hasPrefix("- ") ? $0.components(separatedBy: "\n") : [$0] }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("What’s New", systemImage: "sparkles").font(.largeTitle.bold())
                Text("PanaLux update history · newest first").foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        if paragraph.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                            Divider().padding(.vertical, 8)
                        } else if paragraph.hasPrefix("# ") {
                            Text(String(paragraph.dropFirst(2))).font(.title2.bold())
                        } else {
                            Text((try? AttributedString(markdown: paragraph, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph))
                                .font(.body).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.textSelection(.enabled).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(minWidth: 480, minHeight: 360)
    }
}

final class ReleaseNotesWindowController {
    static let shared = ReleaseNotesWindowController()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let next = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                                styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            next.title = "What’s New in PanaLux"
            next.contentView = NSHostingView(rootView: ReleaseNotesView())
            next.minSize = NSSize(width: 500, height: 400)
            next.isReleasedWhenClosed = false
            next.center()
            window = next
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
