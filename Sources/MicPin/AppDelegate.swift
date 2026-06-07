import AppKit
import MicPinCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PinController?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PinController(audio: CoreAudioSystem(), store: UserDefaultsPinStore())
        let settingsWindow = SettingsWindowController(controller: controller)
        let statusItem = StatusItemController(controller: controller) { [weak settingsWindow] in
            settingsWindow?.show()
        }

        self.controller = controller
        self.settingsWindow = settingsWindow
        self.statusItem = statusItem

        controller.start()
    }
}
