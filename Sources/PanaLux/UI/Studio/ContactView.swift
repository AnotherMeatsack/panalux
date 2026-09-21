import SwiftUI
import AppKit

/// Bug reports, questions and feature ideas. Every message is formatted the same way so it reads
/// cleanly on the receiving end, whether it goes by email or as a GitHub issue.
enum ContactKind: String, CaseIterable, Identifiable {
    case bug = "Bug", question = "Question", idea = "Idea"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .bug: return "ladybug"
        case .question: return "questionmark.bubble"
        case .idea: return "lightbulb"
        }
    }
    var prompt: String {
        switch self {
        case .bug: return "What happened, and what did you expect? Steps to repeat it help most."
        case .question: return "What would you like to know about PanaLux?"
        case .idea: return "What should PanaLux do, and what would it let you do in Lightroom?"
        }
    }
}

enum ContactMessage {
    static let email = "panalux@icloud.com"

    static func subject(kind: ContactKind, text: String) -> String {
        let first = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let short = first.count <= 60 ? first : String(first.prefix(57)) + "..."
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "[PanaLux \(version)] \(kind.rawValue)" + (short.isEmpty ? "" : ": " + short)
    }

    /// Plain text for email. Mail apps do not render Markdown, so this uses simple rules and spacing.
    static func emailBody(kind: ContactKind, text: String, includeSetup: Bool) -> String {
        var lines = ["\(kind.rawValue.uppercased())", "", text.isEmpty ? "(write here)" : text]
        if includeSetup {
            lines += ["", "— — —", "SETUP", BugReport.diagnostics().replacingOccurrences(of: "- ", with: "  ")]
        }
        lines += ["", "Sent from PanaLux"]
        return lines.joined(separator: "\n")
    }

    static func markdown(kind: ContactKind, text: String, includeSetup: Bool) -> String {
        var parts = ["**\(kind.rawValue)**", "", text.isEmpty ? "_(write here)_" : text]
        if includeSetup { parts += ["", "### Setup", BugReport.diagnostics()] }
        return parts.joined(separator: "\n")
    }

    static func mailURL(kind: ContactKind, text: String, includeSetup: Bool) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: subject(kind: kind, text: text)),
                        URLQueryItem(name: "body", value: emailBody(kind: kind, text: text, includeSetup: includeSetup))]
        // URLComponents leaves "+" alone; mail clients would read it as a plus, which is what we want.
        return c.url
    }

    static func issueURL(kind: ContactKind, text: String, includeSetup: Bool) -> URL? {
        var c = URLComponents(string: BugReport.newIssue)
        c?.queryItems = [URLQueryItem(name: "title", value: subject(kind: kind, text: text)),
                         URLQueryItem(name: "body", value: markdown(kind: kind, text: text, includeSetup: includeSetup))]
        return c?.url
    }
}

struct ContactView: View {
    @State var kind: ContactKind
    @State private var text = ""
    @State private var includeSetup = true
    @State private var showSetup = false
    @State private var copied = false
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk to the maker").font(.title2.bold())
                    Text("Bugs, questions, feature ideas. A person reads every one.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $kind) {
                ForEach(ContactKind.allCases) { k in Label(k.rawValue, systemImage: k.symbol).tag(k) }
            }
            .pickerStyle(.segmented).labelsHidden()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if text.isEmpty {
                    Text(kind.prompt).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 150)

            DisclosureGroup(isExpanded: $showSetup) {
                Text(BugReport.diagnostics())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            } label: {
                Toggle("Include my setup (versions and connections, no personal data)", isOn: $includeSetup)
                    .toggleStyle(.checkbox)
            }

            HStack {
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ContactMessage.markdown(kind: kind, text: text, includeSetup: includeSetup), forType: .string)
                    copied = true
                }
                Button { open(ContactMessage.issueURL(kind: kind, text: text, includeSetup: includeSetup)) } label: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Button { open(ContactMessage.mailURL(kind: kind, text: text, includeSetup: includeSetup)) } label: {
                    Label("Email", systemImage: "envelope")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            Text("Email goes to \(ContactMessage.email). GitHub is public; email is private. Nothing is sent until you press send in Mail or on GitHub.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 560)
        .onChange(of: text) { _, _ in copied = false }
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor final class ContactWindowController {
    static let shared = ContactWindowController()
    private var window: NSWindow?

    func show(kind: ContactKind = .bug) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Contact"
        w.contentView = NSHostingView(rootView: ContactView(kind: kind, onClose: { [weak w] in w?.close() }))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
