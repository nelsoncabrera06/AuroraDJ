//
//  MIDIViewModel.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import Combine

/// ViewModel para gestionar la integración MIDI con los decks
@MainActor
class MIDIViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isConnected = false
    @Published var connectedDeviceName: String?
    @Published var availableDevices: [String] = []

    // MARK: - Properties

    let midiService: MIDIService  // Changed to public for MIDI Learn
    var cancellables = Set<AnyCancellable>()  // Changed to public for MIDI Learn

    // Referencias a los deck ViewModels
    private weak var deckAViewModel: DeckViewModel?
    private weak var deckBViewModel: DeckViewModel?
    private weak var mixerViewModel: MixerViewModel?

    // MARK: - Initialization

    init(midiService: MIDIService) {
        self.midiService = midiService

        // Subscribe to MIDI service published properties
        midiService.$isConnected
            .assign(to: &$isConnected)

        midiService.$connectedDeviceName
            .assign(to: &$connectedDeviceName)

        midiService.$availableDevices
            .assign(to: &$availableDevices)

        // Subscribe to MIDI events
        midiService.midiEventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleMIDIEvent(event)
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    /// Conecta los deck ViewModels
    func connectDecks(deckA: DeckViewModel, deckB: DeckViewModel) {
        self.deckAViewModel = deckA
        self.deckBViewModel = deckB
        print("✅ Decks connected to MIDI ViewModel")
    }

    /// Conecta el mixer ViewModel
    func connectMixer(_ mixer: MixerViewModel) {
        self.mixerViewModel = mixer
        print("✅ Mixer connected to MIDI ViewModel")
    }

    // MARK: - Device Management

    /// Escanea dispositivos MIDI disponibles
    func scanForDevices() {
        midiService.scanForDevices()
    }

    /// Conecta a un dispositivo por nombre
    func connectToDevice(named deviceName: String) {
        let success = midiService.connectToDevice(named: deviceName)

        if success {
            print("✅ Connected to MIDI device: \(deviceName)")
        } else {
            print("❌ Failed to connect to MIDI device: \(deviceName)")
        }
    }

    /// Intenta conectar automáticamente a Behringer CMD Studio 4a
    func connectToBehringer() {
        let success = midiService.connectToBehringer()

        if success {
            print("✅ Connected to Behringer CMD Studio 4a")
        } else {
            print("❌ Behringer CMD Studio 4a not found. Available devices:")
            for device in availableDevices {
                print("  - \(device)")
            }
        }
    }

    /// Desconecta el dispositivo actual
    func disconnect() {
        midiService.disconnect()
    }

    // MARK: - MIDI Event Handling

    private func handleMIDIEvent(_ event: MIDIEvent) {
        var action: MIDIAction?

        switch event {
        case .noteOn(_, let note, let velocity):
            action = BehringerCMDStudio4aMapping.actionFromNote(
                note: note,
                velocity: velocity,
                isOn: true
            )

        case .noteOff(_, let note):
            action = BehringerCMDStudio4aMapping.actionFromNote(
                note: note,
                velocity: 0,
                isOn: false
            )

        case .controlChange(_, let controller, let value):
            action = BehringerCMDStudio4aMapping.actionFromCC(
                controller: controller,
                value: value,
                deck: nil
            )

        case .pitchBend(let channel, let value):
            action = BehringerCMDStudio4aMapping.actionFromPitchBend(
                channel: channel,
                value: value
            )
        }

        if let action = action {
            executeAction(action)
        }
    }

    private func executeAction(_ action: MIDIAction) {
        switch action {
        // Playback
        case .togglePlayPause(let deck):
            print("🎵 MIDI Action: Toggle Play/Pause - Deck \(deck.rawValue)")
            getViewModel(for: deck)?.togglePlayPause()

        case .jumpToCue(let deck):
            print("🎯 MIDI Action: Jump to Cue - Deck \(deck.rawValue)")
            getViewModel(for: deck)?.jumpToCue()

        case .setCuePoint(let deck):
            print("🎯 MIDI Action: Set Cue Point - Deck \(deck.rawValue)")
            getViewModel(for: deck)?.setCuePoint()

        case .sync(let deck):
            print("🔄 MIDI Action: Sync - Deck \(deck.rawValue)")
            // TODO: Implement sync functionality
            print("  ⚠️ Sync not yet implemented")

        // Hot Cues
        case .triggerHotCue(let deck, let slot):
            print("🔥 MIDI Action: Trigger Hot Cue \(slot) - Deck \(deck.rawValue)")
            getViewModel(for: deck)?.triggerHotCue(slot: slot)

        // Jog Wheel
        case .jogWheelTouch(let deck, let pressed):
            print("🎡 MIDI Action: Jog Wheel Touch - Deck \(deck.rawValue) - \(pressed ? "Pressed" : "Released")")
            // TODO: Implement jog wheel touch handling

        case .jogWheelRotate(let deck, let delta):
            print("🎡 MIDI Action: Jog Wheel Rotate - Deck \(deck.rawValue) - Delta: \(delta)")
            // TODO: Implement jog wheel rotation (scrubbing)

        // Controls
        case .setTempo(let deck, let tempo):
            print("⏱️ MIDI Action: Set Tempo - Deck \(deck.rawValue) - \(tempo)")
            getViewModel(for: deck)?.setTempo(tempo)

        case .setPitch(let deck, let pitch):
            print("🎵 MIDI Action: Set Pitch - Deck \(deck.rawValue) - \(pitch)")
            getViewModel(for: deck)?.setPitch(pitch)

        case .setVolume(let deck, let volume):
            print("🔊 MIDI Action: Set Volume - Deck \(deck.rawValue) - \(Int(volume * 100))%")
            // Update the mixer's stored volume and recalculate with crossfader
            mixerViewModel?.setDeckVolume(volume, deck: deck)

        // EQ
        case .setEQHigh(let deck, let gain):
            print("🎚️ MIDI Action: Set EQ High - Deck \(deck.rawValue) - \(gain)dB")
            // Convert dB (-12 to +12) to normalized value (0.0 to 1.0)
            let normalized = (gain + 12.0) / 24.0
            mixerViewModel?.setEQ(.high, value: normalized, deck: deck)

        case .setEQMid(let deck, let gain):
            print("🎚️ MIDI Action: Set EQ Mid - Deck \(deck.rawValue) - \(gain)dB")
            let normalized = (gain + 12.0) / 24.0
            mixerViewModel?.setEQ(.mid, value: normalized, deck: deck)

        case .setEQLow(let deck, let gain):
            print("🎚️ MIDI Action: Set EQ Low - Deck \(deck.rawValue) - \(gain)dB")
            let normalized = (gain + 12.0) / 24.0
            mixerViewModel?.setEQ(.low, value: normalized, deck: deck)

        // Mixer
        case .setCrossfader(let position):
            print("↔️ MIDI Action: Set Crossfader - Position: \(Int(position * 100))%")
            mixerViewModel?.setCrossfaderPosition(position)

        case .setMasterVolume(let volume):
            print("🔊 MIDI Action: Set Master Volume - \(Int(volume * 100))%")
            // TODO: Connect to audio mixer

        // Headphone
        case .toggleHeadphoneCue(let deck):
            print("🎧 MIDI Action: Toggle Headphone Cue - Deck \(deck.rawValue)")
            // TODO: Implement headphone cue
        }
    }

    // MARK: - Helper Methods

    private func getViewModel(for deck: DeckID) -> DeckViewModel? {
        switch deck {
        case .deckA:
            return deckAViewModel
        case .deckB:
            return deckBViewModel
        }
    }
}
