import Foundation
import Testing
@testable import MicPinCore

@Test func userDefaultsStoreRoundTrips() {
    let suite = UserDefaults(suiteName: "micpin.test.\(UUID().uuidString)")!
    let store = UserDefaultsPinStore(defaults: suite)
    #expect(store.pinnedUID == nil)
    store.pinnedUID = "UID-1"
    store.pinnedName = "Mic One"
    #expect(store.pinnedUID == "UID-1")
    #expect(store.pinnedName == "Mic One")
    store.pinnedUID = nil
    #expect(store.pinnedUID == nil)
}

@MainActor
@Test func noPinDoesNothing() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let bt = AudioDevice.test("BT", "Huawei", .bluetooth)
    let audio = FakeAudioSystem(devices: [built, bt], defaultUID: "BT")
    let controller = PinController(audio: audio, store: MemoryPinStore())
    controller.start()
    #expect(audio.setCount == 0)
    #expect(audio.currentDefaultUID == "BT")
}

@MainActor
@Test func pinAbsentDeviceDoesNotOverride() {
    let bt = AudioDevice.test("BT", "Huawei", .bluetooth)
    let audio = FakeAudioSystem(devices: [bt], defaultUID: "BT")
    let store = MemoryPinStore()
    store.pinnedUID = "BUILTIN"        // pinned device not in device list
    let controller = PinController(audio: audio, store: store)
    controller.start()
    #expect(audio.setCount == 0)
    #expect(audio.currentDefaultUID == "BT")
}

@MainActor
@Test func pinPresentAndWrongSwitchesOnce() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let bt = AudioDevice.test("BT", "Huawei", .bluetooth)
    let audio = FakeAudioSystem(devices: [built, bt], defaultUID: "BT")
    let controller = PinController(audio: audio, store: MemoryPinStore())
    controller.pin(uid: "BUILTIN")
    #expect(audio.currentDefaultUID == "BUILTIN")
    #expect(audio.setCount == 1)       // converges, no oscillation
}

@MainActor
@Test func pinAlreadyCorrectDoesNotWrite() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let audio = FakeAudioSystem(devices: [built], defaultUID: "BUILTIN")
    let store = MemoryPinStore()
    store.pinnedUID = "BUILTIN"
    let controller = PinController(audio: audio, store: store)
    controller.start()
    #expect(audio.setCount == 0)
}

@MainActor
@Test func autoSwitchAwayIsReverted() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let bt = AudioDevice.test("BT", "Huawei", .bluetooth)
    let audio = FakeAudioSystem(devices: [built], defaultUID: "BUILTIN")
    let controller = PinController(audio: audio, store: MemoryPinStore())
    controller.pin(uid: "BUILTIN")
    audio.resetSetCount()              // reset after initial pin
    // Bluetooth connects and macOS auto-switches input to it:
    audio.simulate(devices: [built, bt], defaultUID: "BT")
    #expect(audio.currentDefaultUID == "BUILTIN")
    #expect(audio.setCount == 1)
}

@MainActor
@Test func pinnedReconnectRestores() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let bt = AudioDevice.test("BT", "Huawei", .bluetooth)
    let audio = FakeAudioSystem(devices: [bt], defaultUID: "BT")
    let store = MemoryPinStore()
    store.pinnedUID = "BUILTIN"
    let controller = PinController(audio: audio, store: store)
    controller.start()
    #expect(audio.setCount == 0)       // absent → no-op
    // Built-in reappears (e.g. after a glitch):
    audio.simulate(devices: [built, bt], defaultUID: "BT")
    #expect(audio.currentDefaultUID == "BUILTIN")
    #expect(audio.setCount == 1)
}

@MainActor
@Test func setTriggeredOnChangeConvergesWithoutRecursion() {
    // setDefaultInput fires onChange (as the real listener does). Verify the
    // loop terminates after a single set rather than oscillating.
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let bt = AudioDevice.test("BT", "Huawei", .bluetooth)
    let audio = FakeAudioSystem(devices: [built, bt], defaultUID: "BT")
    audio.fireOnChangeOnSet = true
    let controller = PinController(audio: audio, store: MemoryPinStore())
    controller.pin(uid: "BUILTIN")
    #expect(audio.currentDefaultUID == "BUILTIN")
    #expect(audio.setCount == 1)
}

@MainActor
@Test func setFailureKeepsControllerStable() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let audio = FakeAudioSystem(devices: [built], defaultUID: "OTHER")
    let store = MemoryPinStore()
    store.pinnedUID = "BUILTIN"
    let controller = PinController(audio: audio, store: store)
    audio.failNextSet = true
    controller.start()                 // set throws, swallowed
    #expect(audio.currentDefaultUID == "OTHER")   // unchanged, no crash
    // A subsequent event reconciles cleanly:
    audio.simulate(devices: [built], defaultUID: "OTHER")
    #expect(audio.currentDefaultUID == "BUILTIN")
}

@MainActor
@Test func cachedNameRefreshesWhenDeviceSeen() {
    let store = MemoryPinStore()
    store.pinnedUID = "BT"
    store.pinnedName = "Old Name"
    let renamed = AudioDevice.test("BT", "New Name", .bluetooth)
    let audio = FakeAudioSystem(devices: [renamed], defaultUID: "BT")
    let controller = PinController(audio: audio, store: store)
    controller.start()
    #expect(controller.pinnedName == "New Name")
    #expect(store.pinnedName == "New Name")
}

@MainActor
@Test func pinThenUnpinClearsState() {
    let built = AudioDevice.test("BUILTIN", "MacBook Mic", .builtIn)
    let audio = FakeAudioSystem(devices: [built], defaultUID: "BUILTIN")
    let store = MemoryPinStore()
    let controller = PinController(audio: audio, store: store)
    controller.pin(uid: "BUILTIN")
    #expect(controller.pinnedUID == "BUILTIN")
    controller.unpin()
    #expect(controller.pinnedUID == nil)
    #expect(store.pinnedUID == nil)
    #expect(store.pinnedName == nil)
}
