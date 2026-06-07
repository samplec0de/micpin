import Foundation

public struct AudioDevice: Equatable, Identifiable, Sendable {
    public let uid: String
    public let name: String
    public let transport: Transport

    public var id: String { uid }

    public init(uid: String, name: String, transport: Transport) {
        self.uid = uid
        self.name = name
        self.transport = transport
    }

    public enum Transport: Equatable, Sendable {
        case builtIn, bluetooth, usb, virtual, aggregate, other

        public var label: String {
            switch self {
            case .builtIn: return "Built-in"
            case .bluetooth: return "Bluetooth"
            case .usb: return "USB"
            case .virtual: return "Virtual"
            case .aggregate: return "Aggregate"
            case .other: return "Other"
            }
        }
    }
}
