import AppKit
import SwiftUI
import MicPinCore

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let controller: PinController
    private var window: NSWindow?

    init(controller: PinController) {
        self.controller = controller
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(controller: controller))
            let window = NSWindow(contentViewController: hosting)
            window.title = "MicPin"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Defer to avoid a momentary ghost Dock icon during the close animation.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
