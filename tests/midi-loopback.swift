import Foundation
import CoreMIDI
var client: MIDIClientRef = 0
var destination: MIDIEndpointRef = 0
let status = MIDIClientCreate("ExeRunner transport control" as CFString, nil, nil, &client)
guard status == noErr else { fatalError("MIDI client \(status)") }
let received = DispatchSemaphore(value: 0)
let create = MIDIDestinationCreateWithBlock(client, "ExeRunner Probe" as CFString, &destination) { packets, _ in
    let packet = packets.pointee.packet
    let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
    if bytes.starts(with: [0x90, 0x40, 0x64]) {
        print("RECEIVED 90 40 64");fflush(stdout);received.signal()
    }
}
guard create == noErr else { fatalError("MIDI destination \(create)") }
print("READY");fflush(stdout)
_ = received.wait(timeout: .now() + 45)
MIDIEndpointDispose(destination);MIDIClientDispose(client)
