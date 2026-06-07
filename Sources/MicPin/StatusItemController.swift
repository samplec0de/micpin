import AppKit
import MicPinCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let controller: PinController
    private let openSettings: () -> Void

    init(controller: PinController, openSettings: @escaping () -> Void) {
        self.controller = controller
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        refreshIcon()
        rebuildMenu()
        controller.onUpdate = { [weak self] in
            self?.refreshIcon()
            self?.rebuildMenu()
        }
    }

    private func refreshIcon() {
        let symbol = controller.pinnedUID == nil ? "mic" : "mic.fill"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MicPin")
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        // We manage enabled state ourselves; without this, AppKit auto-enables
        // any item whose target responds to its action (ignoring isEnabled).
        menu.autoenablesItems = false
        menu.addItem(disabled("Pinned input"))

        for device in controller.devices {
            let item = NSMenuItem(
                title: "\(device.name)  ·  \(device.transport.label)",
                action: #selector(pinDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uid
            item.state = device.uid == controller.pinnedUID ? .on : .off
            menu.addItem(item)
        }

        if let pinned = controller.pinnedUID,
           !controller.devices.contains(where: { $0.uid == pinned }) {
            let name = controller.pinnedName ?? pinned
            menu.addItem(disabled("\(name) — disconnected"))
        }

        menu.addItem(.separator())

        let unpin = NSMenuItem(title: "Unpin (follow system)",
                               action: #selector(unpinAction), keyEquivalent: "")
        unpin.target = self
        unpin.isEnabled = controller.pinnedUID != nil
        menu.addItem(unpin)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Open Settings…",
                                  action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let login = NSMenuItem(title: "Start at Login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MicPin", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func pinDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        controller.pin(uid: uid)
    }

    @objc private func unpinAction() { controller.unpin() }
    @objc private func openSettingsAction() { openSettings() }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        rebuildMenu()
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
