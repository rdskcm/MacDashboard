// Engine/IPhoneLink.swift
// IPHONE-WIFI: how a phone is reached (cable or Wi-Fi) and the pure decisions on it. Covered by Tests/MoonportTests.
import Foundation

enum IPhoneLink: Equatable, Sendable {
    case usb, wifi
}

enum IPhoneLinkPolicy {
    /// What the transport does with an attach notification.
    enum Attach: Equatable { case report(IPhoneLink), park, ignore }

    /// `AMDeviceGetInterfaceType`: 1 = USB, 2 = network (IPHONE-SPIKE C3, C34). A network device is parked (held, not
    /// reported) while «Connect over Wi-Fi» is off; any other type is ignored.
    static func attach(interfaceType: Int32, networkEnabled: Bool) -> Attach {
        switch interfaceType {
        case 1: return .report(.usb)
        case 2: return networkEnabled ? .report(.wifi) : .park
        default: return .ignore
        }
    }

    /// True when `candidate` should replace `current` as a device's connection: USB beats Wi-Fi, otherwise the
    /// current one stays.
    static func replaces(_ candidate: IPhoneLink, _ current: IPhoneLink) -> Bool {
        candidate == .usb && current == .wifi
    }
}
