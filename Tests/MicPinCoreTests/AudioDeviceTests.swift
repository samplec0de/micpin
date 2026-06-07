import Testing
@testable import MicPinCore

@Test func transportLabelsAreHumanReadable() {
    #expect(AudioDevice.Transport.builtIn.label == "Built-in")
    #expect(AudioDevice.Transport.bluetooth.label == "Bluetooth")
    #expect(AudioDevice.Transport.usb.label == "USB")
    #expect(AudioDevice.Transport.aggregate.label == "Aggregate")
}

@Test func deviceIdentityIsUID() {
    let device = AudioDevice(uid: "ABC", name: "Mic", transport: .usb)
    #expect(device.id == "ABC")
}
