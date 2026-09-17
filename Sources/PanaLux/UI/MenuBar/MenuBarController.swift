import SwiftUI
import AppKit
import Combine

public class MenuBarController: NSObject, NSMenuDelegate {
    public static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    public func setup() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshIcon()

        // Icon follows the state you most need to notice.
        StudioEngine.shared.$isOutputPaused
            .combineLatest(PanelManager.shared.$isConnected, LightroomBridge.shared.$isConnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let engine = StudioEngine.shared
        let symbol: String
        if engine.isOutputPaused {
            symbol = "pause.circle.fill"
        } else if !PanelManager.shared.isConnected || !LightroomBridge.shared.isConnected {
            symbol = "circle.grid.cross"
        } else {
            symbol = "circle.grid.cross.fill"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PanaLux")
        button.image?.isTemplate = true
        button.toolTip = "PanaLux: \(engine.statusMessage)"
    }

    // Rebuilt each time it opens so every line is current.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let engine = StudioEngine.shared
        let panel = PanelManager.shared
        let coordinator = AppCoordinator.shared
        let settings = AppSettings.shared

        let title = NSMenuItem(title: "PanaLux", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "PanaLux", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(title)

        let panelLine: String
        if panel.isReleased {
            panelLine = "Panel: handed to DaVinci Resolve"
        } else {
            panelLine = panel.isConnected ? "Panel: connected" : "Panel: not found. plug it in"
        }
        menu.addItem(status(panelLine, ok: panel.isConnected))

        let lrLine: String
        if LightroomBridge.shared.isConnected {
            lrLine = "Lightroom: connected"
        } else if !coordinator.isLightroomRunning {
            lrLine = "Lightroom: not open"
        } else if coordinator.isMIDI2LRAppRunning {
            lrLine = "Lightroom: quit the MIDI2LR app"
        } else {
            lrLine = coordinator.isPluginInstalled ? "Lightroom: waiting for plugin" : "Lightroom: plugin not installed"
        }
        menu.addItem(status(lrLine, ok: LightroomBridge.shared.isConnected))
        menu.addItem(status("Mode: \(engine.statusMessage)", ok: nil))

        menu.addItem(.separator())

        menu.addItem(action("Open PanaLux", #selector(openStudio), key: "o", symbol: "circle.grid.cross"))
        menu.addItem(action("Find a Command…", #selector(openPalette), key: "k", symbol: "magnifyingglass"))

        menu.addItem(.separator())

        let pause = action(engine.isOutputPaused ? "Resume Output" : "Pause Output", #selector(togglePause), key: "", symbol: engine.isOutputPaused ? "play.fill" : "pause.fill")
        pause.state = engine.isOutputPaused ? .on : .off
        menu.addItem(pause)
        menu.addItem(action("Back to Base Map", #selector(returnToBase), key: "", symbol: "house"))
        if engine.tempFocusParam != nil {
            menu.addItem(action("Clear Focus Dial", #selector(clearFocus), key: "", symbol: "dial.medium"))
        }

        if panel.isReleased {
            menu.addItem(action("Take Panel Back", #selector(reclaimPanel), key: "", symbol: "arrow.down.circle"))
        } else {
            menu.addItem(action("Hand Panel to Resolve", #selector(releasePanel), key: "", symbol: "arrow.up.circle"))
            menu.addItem(action("Reconnect Panel", #selector(reconnectPanel), key: "", symbol: "arrow.clockwise"))
        }
        if !LightroomBridge.shared.isConnected && !coordinator.isLightroomRunning {
            menu.addItem(action("Open Lightroom Classic", #selector(openLightroom), key: "", symbol: "arrow.up.forward.app"))
        }

        menu.addItem(.separator())

        let hud = NSMenuItem(title: "Notch HUD", action: nil, keyEquivalent: "")
        hud.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: nil)
        let hudMenu = NSMenu()
        for (label, value) in [("Full", "full"), ("Minimal", "minimal"), ("Hidden", "hidden")] {
            let entry = NSMenuItem(title: label, action: #selector(setHUDStyle(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = value
            let current = settings.notchHudEnabled ? settings.hudStyle : "hidden"
            entry.state = current == value ? .on : .off
            hudMenu.addItem(entry)
        }
        hud.submenu = hudMenu
        menu.addItem(hud)

        menu.addItem(action("Reference Card", #selector(openReferenceCard), key: "", symbol: "printer"))
        menu.addItem(action("Import Map…", #selector(importMap), key: "", symbol: "square.and.arrow.down"))
        menu.addItem(action("Export Map…", #selector(exportMap), key: "", symbol: "square.and.arrow.up"))
        menu.addItem(action("Copy Map", #selector(copyMap), key: "", symbol: "doc.on.doc"))
        menu.addItem(action("Watch the Intro", #selector(openIntro), key: "", symbol: "play.rectangle"))
        menu.addItem(action("Take the Hands-On Tour", #selector(openTutorial), key: "", symbol: "sparkles"))
        menu.addItem(action("Setup Assistant…", #selector(openSetup), key: "", symbol: "checklist"))
        menu.addItem(action("Report a Bug…", #selector(reportBug), key: "", symbol: "exclamationmark.bubble"))
        menu.addItem(action("Settings…", #selector(openSettings), key: ",", symbol: "gearshape"))

        menu.addItem(.separator())
        menu.addItem(action("Quit PanaLux", #selector(quitApp), key: "q", symbol: nil))
    }

    private func status(_ text: String, ok: Bool?) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let ok {
            let config = NSImage.SymbolConfiguration(paletteColors: [ok ? .systemGreen : .systemOrange])
            item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config.applying(.init(pointSize: 7, weight: .regular)))
        }
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String, symbol: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    @objc private func openStudio() {
        StudioWindowController.shared.show()
    }

    @objc private func openPalette() {
        StudioWindowController.shared.show()
        GuideController.shared.showPalette = true
    }

    @objc private func openTutorial() {
        StudioWindowController.shared.show()
        GuideController.shared.startWalkthrough()
    }

    @objc private func openIntro() {
        StudioWindowController.shared.show()
        GuideController.shared.presentIntro()
    }
    
    @objc private func openSetup() {
        StudioWindowController.shared.show()
        GuideController.shared.presentSetup()
    }

    @objc private func openSettings() {
        StudioWindowController.shared.show()
        GuideController.shared.showSettings = true
    }

    @objc private func openReferenceCard() {
        ReferenceCard.open()
    }

    @objc private func importMap() {
        MapImporter.chooseAndImport()
    }

    @objc private func exportMap() {
        MapImporter.chooseAndExport()
    }

    @objc private func copyMap() {
        MapImporter.copyCurrentMap()
    }

    @objc private func reportBug() {
        BugReport.present()
    }

    @objc private func togglePause() {
        let engine = StudioEngine.shared
        engine.setOutputPaused(!engine.isOutputPaused)
    }

    @objc private func returnToBase() {
        StudioEngine.shared.returnToBase()
    }

    @objc private func clearFocus() {
        StudioEngine.shared.setTempFocus(nil)
    }

    @objc private func setHUDStyle(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        let settings = AppSettings.shared
        if value == "hidden" {
            settings.notchHudEnabled = false
        } else {
            settings.notchHudEnabled = true
            settings.hudStyle = value
        }
    }

    @objc private func releasePanel() {
        AppCoordinator.shared.releasePanel()
    }

    @objc private func reclaimPanel() {
        AppCoordinator.shared.reclaimPanel()
    }

    @objc private func reconnectPanel() {
        StudioEngine.shared.returnToBase(announce: false)
        PanelManager.shared.reclaim()
    }

    @objc private func openLightroom() {
        AppCoordinator.shared.launchLightroomClassic()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
