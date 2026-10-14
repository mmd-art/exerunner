import AppKit
import Foundation
import IOKit
import CoreMIDI

struct HostDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var detail: String
    var node: String?
}

/// Read-only platform discovery: no device is opened, seized or sent data.
@MainActor struct DeviceInventory {
    var serial: [HostDevice] = []
    var usb: [HostDevice] = []
    var controllers: [HostDevice] = []
    var midiInputs: [String] = []
    var midiOutputs: [String] = []
    var printers: [String] = []
    static func current() -> DeviceInventory {
        var value = DeviceInventory()
        for properties in services("IOSerialBSDClient") {
            guard let node = properties["IOCalloutDevice"] as? String, node != "/dev/cu.debug-console", SerialPortMapper.valid(.init(number: 1, device: node)) else { continue }
            value.serial.append(.init(id: node, name: URL(fileURLWithPath: node).lastPathComponent, detail: node, node: node))
        }
        if value.serial.isEmpty {
            for leaf in ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []) where leaf.hasPrefix("cu.") && leaf != "cu.debug-console" {
                let node = "/dev/" + leaf
                if SerialPortMapper.connected(node) { value.serial.append(.init(id: node, name: leaf, detail: node, node: node)) }
            }
        }
        value.serial.sort { $0.name < $1.name }
        for (index, properties) in services("IOUSBHostDevice").enumerated() {
            let name = properties["USB Product Name"] as? String ?? properties["IOName"] as? String ?? "USB"
            let vendor = properties["idVendor"] as? Int ?? 0, product = properties["idProduct"] as? Int ?? 0
            value.usb.append(.init(id: "usb-\(index)-\(vendor)-\(product)", name: name,
                                   detail: String(format: "%04x:%04x", vendor, product), node: nil))
        }
        for (index, properties) in services("IOHIDDevice").enumerated() {
            guard properties["PrimaryUsagePage"] as? Int == 1,
                  let usage = properties["PrimaryUsage"] as? Int, [4, 5].contains(usage) else { continue }
            let name = properties["Product"] as? String ?? "HID"
            value.controllers.append(.init(id: "hid-\(index)", name: name,
                                           detail: properties["Transport"] as? String ?? "HID", node: nil))
        }
        for i in 0..<MIDIGetNumberOfSources() { value.midiInputs.append(midiName(MIDIGetSource(i))) }
        for i in 0..<MIDIGetNumberOfDestinations() { value.midiOutputs.append(midiName(MIDIGetDestination(i))) }
        value.printers = NSPrinter.printerNames.sorted()
        return value
    }
    private static func services(_ name: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] { result.append(dictionary) }
        }
        return result
    }
    private static func midiName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let name { return name.takeRetainedValue() as String }
        return "MIDI"
    }
}
