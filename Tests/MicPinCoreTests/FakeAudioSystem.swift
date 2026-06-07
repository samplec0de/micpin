import Foundation
@testable import MicPinCore

/// In-memory AudioSystem. Mirrors real semantics: a successful
/// `setDefaultInput` fires `onChange` (like the real listener would).
final class FakeAudioSystem: AudioSystem {
    var devices: [AudioDevice]
    var currentDefaultUID: String?
    var onChange: (@MainActor () -> Void)?

    private(set) var setCount = 0
    var failNextSet = false
    var fireOnChangeOnSet = true

    init(devices: [AudioDevice], defaultUID: String?) {
        self.devices = devices
        self.currentDefaultUID = defaultUID
    }

    func inputDevices() -> [AudioDevice] { devices }
    func defaultInputUID() -> String? { currentDefaultUID }

    func resetSetCount() { setCount = 0 }

    func setDefaultInput(uid: String) throws {
        setCount += 1
        if failNextSet {
            failNextSet = false
            throw AudioSystemError.deviceNotFound
        }
        guard devices.contains(where: { $0.uid == uid }) else {
            throw AudioSystemError.deviceNotFound
        }
        currentDefaultUID = uid
        if fireOnChangeOnSet { fire() }
    }

    /// Simulate the OS changing devices and/or the active input, then notify.
    func simulate(devices: [AudioDevice], defaultUID: String?) {
        self.devices = devices
        self.currentDefaultUID = defaultUID
        fire()
    }

    /// Bridge to the `@MainActor` closure. Safe because the fake is only ever
    /// driven from `@MainActor` tests (i.e. already on main), keeping the
    /// reconcile path synchronous and deterministic.
    private func fire() {
        guard let onChange else { return }
        MainActor.assumeIsolated { onChange() }
    }
}

final class MemoryPinStore: PinStore {
    var pinnedUID: String?
    var pinnedName: String?
}

extension AudioDevice {
    static func test(_ uid: String, _ name: String = "Mic", _ t: Transport = .usb) -> AudioDevice {
        AudioDevice(uid: uid, name: name, transport: t)
    }
}
