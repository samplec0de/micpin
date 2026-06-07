import Foundation
import Observation

@MainActor
@Observable
public final class PinController {
    public private(set) var devices: [AudioDevice] = []
    public private(set) var pinnedUID: String?
    public private(set) var pinnedName: String?
    public private(set) var activeUID: String?

    @ObservationIgnored private let audio: AudioSystem
    @ObservationIgnored private let store: PinStore
    /// Called after any state change so AppKit (the menu bar) can refresh.
    @ObservationIgnored public var onUpdate: (() -> Void)?

    public init(audio: AudioSystem, store: PinStore) {
        self.audio = audio
        self.store = store
        self.pinnedUID = store.pinnedUID
        self.pinnedName = store.pinnedName
        // onChange is a `@MainActor` closure (see AudioSystem), so this is a
        // valid main-isolated call; the producer guarantees main delivery.
        self.audio.onChange = { [weak self] in self?.handleChange() }
    }

    public func start() {
        refreshDevices()
        reconcile()
        notify()
    }

    public func pin(uid: String) {
        pinnedUID = uid
        store.pinnedUID = uid
        // Act on current hardware state, even if start() hasn't run yet. This
        // also refreshes the cached display name from the live device.
        refreshDevices()
        reconcile()
        notify()
    }

    public func unpin() {
        pinnedUID = nil
        pinnedName = nil
        store.pinnedUID = nil
        store.pinnedName = nil
        notify()
    }

    /// The heart of the app. Idempotent and best-effort.
    public func reconcile() {
        guard let pinned = pinnedUID else { return }                        // rule 1
        guard devices.contains(where: { $0.uid == pinned }) else { return } // rule 2
        guard audio.defaultInputUID() != pinned else { return }             // rule 4
        do {
            try audio.setDefaultInput(uid: pinned)                          // rule 3
        } catch {
            // Best-effort: device may have vanished mid-switch. The next
            // event re-reconciles. Never crash.
        }
    }

    private func handleChange() {
        refreshDevices()
        reconcile()
        notify()
    }

    private func refreshDevices() {
        devices = audio.inputDevices()
        activeUID = audio.defaultInputUID()
        // Refresh the cached display name while the pinned device is present
        // (macOS lets users rename devices).
        if let uid = pinnedUID, let device = devices.first(where: { $0.uid == uid }) {
            if pinnedName != device.name {
                pinnedName = device.name
                store.pinnedName = device.name
            }
        }
    }

    private func notify() { onUpdate?() }
}
