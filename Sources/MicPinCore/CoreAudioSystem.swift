import CoreAudio
import Foundation

/// Real `AudioSystem` over CoreAudio. Listeners run on a private serial queue;
/// `onChange` is always dispatched to the main thread (trailing debounce).
public final class CoreAudioSystem: AudioSystem, @unchecked Sendable {
    // Set on main by PinController; read on the serial queue in
    // scheduleReconcile, which hops to main before invoking it. The
    // `@MainActor` closure type is Sendable, so it crosses the queue safely.
    nonisolated(unsafe) public var onChange: (@MainActor () -> Void)?

    private let queue = DispatchQueue(label: "com.micpin.coreaudio")
    private var debounce: DispatchWorkItem?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init() {
        installListeners()
    }

    deinit {
        removeListeners()
    }

    // MARK: AudioSystem

    public func inputDevices() -> [AudioDevice] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(of: id) > 0 else { return nil }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
            return AudioDevice(uid: uid, name: name, transport: transport(of: id))
        }
    }

    public func defaultInputUID() -> String? {
        guard let id = defaultInputDeviceID(), id != kAudioObjectUnknown else { return nil }
        return stringProperty(id, kAudioDevicePropertyDeviceUID)
    }

    public func setDefaultInput(uid: String) throws {
        let id = deviceID(forUID: uid)
        guard id != kAudioObjectUnknown else { throw AudioSystemError.deviceNotFound }
        var deviceID = id
        var address = systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
        guard status == noErr else { throw AudioSystemError.osStatus(status) }
    }

    // MARK: Property helpers

    private func systemAddress(_ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func deviceIDs() -> [AudioDeviceID] {
        var address = systemAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = systemAddress(kAudioDevicePropertyStreamConfiguration,
                                    scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0
        else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Reads a CFString property (UID, name). CoreAudio returns a +1 string we own.
    private func stringProperty(_ device: AudioObjectID,
                                _ selector: AudioObjectPropertySelector) -> String? {
        var address = systemAddress(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfString: CFString?
        let status = withUnsafeMutablePointer(to: &cfString) { ptr in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let string = cfString else { return nil }
        let result = string as String
        return result.isEmpty ? nil : result
    }

    private func transport(of device: AudioDeviceID) -> AudioDevice.Transport {
        var address = systemAddress(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return .other }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeVirtual: return .virtual
        case kAudioDeviceTransportTypeAggregate: return .aggregate
        default: return .other
        }
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var address = systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
        else { return nil }
        return deviceID
    }

    /// Returns `kAudioObjectUnknown` when no device matches the UID (NOT an error).
    private func deviceID(forUID uid: String) -> AudioDeviceID {
        var address = systemAddress(kAudioHardwarePropertyTranslateUIDToDevice)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var cfUID = uid as CFString
        var outSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString?>.size), uidPtr,   // UID passed as qualifier
                &outSize, &deviceID)
        }
        guard status == noErr else { return AudioDeviceID(kAudioObjectUnknown) }
        return deviceID
    }

    // MARK: Listeners

    private func installListeners() {
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var address = systemAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.scheduleReconcile()
            }
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
            listeners.append((address, block))
        }
    }

    private func removeListeners() {
        for (address, block) in listeners {
            var addr = address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, queue, block)
        }
        listeners.removeAll()
    }

    private func scheduleReconcile() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let callback = self.onChange
            DispatchQueue.main.async {
                MainActor.assumeIsolated { callback?() }   // guaranteed on main here
            }
        }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.1, execute: work)
    }
}
