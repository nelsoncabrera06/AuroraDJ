//
//  MIDIService.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import CoreMIDI
import Combine

/// Callback global para recibir paquetes MIDI
private func midiReadProc(
    packetList: UnsafePointer<MIDIPacketList>,
    readProcRefCon: UnsafeMutableRawPointer?,
    srcConnRefCon: UnsafeMutableRawPointer?
) {
    guard let refCon = readProcRefCon else { return }
    let service = Unmanaged<MIDIService>.fromOpaque(refCon).takeUnretainedValue()
    service.handleMIDIPacketList(packetList)
}

/// Tipos de eventos MIDI
enum MIDIEvent {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case pitchBend(channel: UInt8, value: Int)
}

/// Servicio para comunicación MIDI
class MIDIService: ObservableObject {
    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var connectedDeviceName: String?
    @Published var availableDevices: [String] = []

    // MARK: - Properties

    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var connectedEndpoint: MIDIEndpointRef = 0

    // Publisher para eventos MIDI
    let midiEventsPublisher = PassthroughSubject<MIDIEvent, Never>()

    // MARK: - Initialization

    init() {
        setupMIDI()
        scanForDevices()
    }

    deinit {
        disconnect()

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
        }

        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
    }

    // MARK: - Setup

    private func setupMIDI() {
        var client: MIDIClientRef = 0

        let status = MIDIClientCreateWithBlock("DJSoftwareMIDIClient" as CFString, &client) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }

        if status == noErr {
            midiClient = client
            print("✅ MIDI Client created successfully")
        } else {
            print("❌ Failed to create MIDI client: \(status)")
            return
        }

        // Create input port with self as context
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        var port: MIDIPortRef = 0
        let portStatus = MIDIInputPortCreate(
            client,
            "DJSoftwareInputPort" as CFString,
            midiReadProc,
            selfPointer,
            &port
        )

        if portStatus == noErr {
            inputPort = port
            print("✅ MIDI Input Port created successfully")
        } else {
            print("❌ Failed to create MIDI input port: \(portStatus)")
        }
    }

    // MARK: - Device Management

    /// Escanea dispositivos MIDI disponibles
    func scanForDevices() {
        var devices: [String] = []
        let sourceCount = MIDIGetNumberOfSources()

        print("🔍 Scanning for MIDI devices... Found \(sourceCount) sources")

        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)

            var name: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)

            if status == noErr, let deviceName = name?.takeRetainedValue() as String? {
                devices.append(deviceName)
                print("  📱 Found: \(deviceName)")
            }
        }

        DispatchQueue.main.async {
            self.availableDevices = devices
        }
    }

    /// Conecta a un dispositivo MIDI por nombre
    func connectToDevice(named deviceName: String) -> Bool {
        let sourceCount = MIDIGetNumberOfSources()

        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)

            var name: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)

            if status == noErr,
               let endpointName = name?.takeRetainedValue() as String?,
               endpointName.contains(deviceName) {

                return connectToEndpoint(endpoint, name: endpointName)
            }
        }

        print("❌ Device not found: \(deviceName)")
        return false
    }

    /// Intenta conectar a Behringer CMD Studio 4a automáticamente
    func connectToBehringer() -> Bool {
        // Buscar variantes del nombre del dispositivo
        let possibleNames = [
            "Studio 4A",           // Nombre real del dispositivo
            "CMD Studio 4a",
            "Behringer",
            "CMD STUDIO 4A",
            "Studio 4a"
        ]

        for name in possibleNames {
            if connectToDevice(named: name) {
                return true
            }
        }

        print("❌ Behringer CMD Studio 4a not found")
        return false
    }

    private func connectToEndpoint(_ endpoint: MIDIEndpointRef, name: String) -> Bool {
        // Disconnect previous connection
        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
        }

        // Connect to new endpoint
        let status = MIDIPortConnectSource(inputPort, endpoint, nil)

        if status == noErr {
            connectedEndpoint = endpoint

            DispatchQueue.main.async {
                self.isConnected = true
                self.connectedDeviceName = name
            }

            print("✅ Connected to MIDI device: \(name)")
            return true
        } else {
            print("❌ Failed to connect to MIDI device: \(status)")
            return false
        }
    }

    /// Desconecta el dispositivo MIDI actual
    func disconnect() {
        if connectedEndpoint != 0 {
            MIDIPortDisconnectSource(inputPort, connectedEndpoint)
            connectedEndpoint = 0
        }

        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedDeviceName = nil
        }

        print("🔌 MIDI device disconnected")
    }

    // MARK: - MIDI Event Handling

    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        let message = notification.pointee

        switch message.messageID {
        case .msgSetupChanged:
            print("🔄 MIDI setup changed")
            scanForDevices()

        case .msgObjectAdded:
            print("➕ MIDI device added")
            scanForDevices()

        case .msgObjectRemoved:
            print("➖ MIDI device removed")
            scanForDevices()

        default:
            break
        }
    }

    func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            parseMIDIPacket(&packet)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func parseMIDIPacket(_ packet: inout MIDIPacket) {
        let data = Mirror(reflecting: packet.data).children.prefix(Int(packet.length)).map { $0.value as! UInt8 }

        guard data.count >= 3 else { return }

        let statusByte = data[0]
        let data1 = data[1]
        let data2 = data[2]

        let messageType = statusByte & 0xF0
        let channel = statusByte & 0x0F

        var event: MIDIEvent?

        switch messageType {
        case 0x90: // Note On
            if data2 > 0 {
                event = .noteOn(channel: channel, note: data1, velocity: data2)
                print("🎹 Note On: CH\(channel) Note:\(data1) Vel:\(data2)")
            } else {
                event = .noteOff(channel: channel, note: data1)
                print("🎹 Note Off: CH\(channel) Note:\(data1)")
            }

        case 0x80: // Note Off
            event = .noteOff(channel: channel, note: data1)
            print("🎹 Note Off: CH\(channel) Note:\(data1)")

        case 0xB0: // Control Change
            event = .controlChange(channel: channel, controller: data1, value: data2)
            print("🎚️ CC: CH\(channel) Controller:\(data1) Value:\(data2)")

        case 0xE0: // Pitch Bend
            let value = Int(data1) | (Int(data2) << 7)
            event = .pitchBend(channel: channel, value: value)  // Pass raw value, let mapping handle centering
            print("🎵 Pitch Bend: CH\(channel) Value:\(value)")

        default:
            break
        }

        if let event = event {
            midiEventsPublisher.send(event)
        }
    }
}

