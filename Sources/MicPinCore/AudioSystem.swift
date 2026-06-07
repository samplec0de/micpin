import Foundation

/// Abstraction over the system audio layer so the pin logic is testable
/// without hardware.
public protocol AudioSystem: AnyObject {
    func inputDevices() -> [AudioDevice]
    func defaultInputUID() -> String?
    func setDefaultInput(uid: String) throws
    /// Invoked when devices or the default input change. Always delivered on the
    /// main actor (the implementation is responsible for the hop), so the type
    /// is `@MainActor`-isolated.
    var onChange: (@MainActor () -> Void)? { get set }
}

public enum AudioSystemError: Error, Equatable {
    case deviceNotFound
    case osStatus(Int32)
}

/// Persistence for the single pinned device.
public protocol PinStore: AnyObject {
    var pinnedUID: String? { get set }
    var pinnedName: String? { get set }
}

public final class UserDefaultsPinStore: PinStore {
    private let defaults: UserDefaults
    private let uidKey = "pinnedInputDeviceUID"
    private let nameKey = "pinnedInputDeviceName"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var pinnedUID: String? {
        get { defaults.string(forKey: uidKey) }
        set { defaults.set(newValue, forKey: uidKey) }
    }

    public var pinnedName: String? {
        get { defaults.string(forKey: nameKey) }
        set { defaults.set(newValue, forKey: nameKey) }
    }
}
