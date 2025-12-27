//
//  MIDIMapping.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation

/// Mapeo de controles MIDI para Behringer CMD Studio 4a
struct BehringerCMDStudio4aMapping {

    // MARK: - Deck A Controls (Canal 0)

    struct DeckA {
        // Botones de transporte (Notes) - CONFIRMADOS!
        static let playButton: UInt8 = 44    // 0x2C ✅
        static let cueButton: UInt8 = 43     // 0x2B ✅
        static let syncButton: UInt8 = 45    // 0x2D ✅
        static let cupButton: UInt8 = 0x03   // Cup button - pendiente

        // Hot Cues (Notes) - pendiente mapeo
        static let hotCue1: UInt8 = 0x10
        static let hotCue2: UInt8 = 0x11
        static let hotCue3: UInt8 = 0x12
        static let hotCue4: UInt8 = 0x13

        // Control Changes (CC)
        static let jogWheelTouch: UInt8 = 0x16     // Touch sensor - pendiente
        static let jogWheelRotation: UInt8 = 0x17  // Rotación - pendiente

        static let pitchFader: UInt8 = 0x0D        // Fader de tempo/pitch - pendiente
        static let volumeFader: UInt8 = 112        // 0x70 ✅

        // EQ (CC) - CONFIRMADOS!
        static let eqHigh: UInt8 = 96    // 0x60 ✅
        static let eqMid: UInt8 = 97     // 0x61 ✅
        static let eqLow: UInt8 = 98     // 0x62 ✅

        // FX/Filter (CC)
        static let filterKnob: UInt8 = 0x14
    }

    // MARK: - Deck B Controls (Canal 1)

    struct DeckB {
        // Botones de transporte (Notes) - CONFIRMADOS!
        static let playButton: UInt8 = 76    // 0x4C ✅
        static let cueButton: UInt8 = 75     // 0x4B ✅
        static let syncButton: UInt8 = 77    // 0x4D ✅
        static let cupButton: UInt8 = 0x23   // Cup button - pendiente

        // Hot Cues (Notes) - pendiente mapeo
        static let hotCue1: UInt8 = 0x30
        static let hotCue2: UInt8 = 0x31
        static let hotCue3: UInt8 = 0x32
        static let hotCue4: UInt8 = 0x33

        // Control Changes (CC)
        static let jogWheelTouch: UInt8 = 0x2E     // Touch sensor - pendiente
        static let jogWheelRotation: UInt8 = 0x2F  // Rotación - pendiente

        static let pitchFader: UInt8 = 0x1D        // Fader de tempo/pitch - pendiente
        static let volumeFader: UInt8 = 113        // 0x71 ✅

        // EQ (CC) - CONFIRMADOS!
        static let eqHigh: UInt8 = 99    // 0x63 ✅
        static let eqMid: UInt8 = 100    // 0x64 ✅
        static let eqLow: UInt8 = 101    // 0x65 ✅

        // FX/Filter (CC)
        static let filterKnob: UInt8 = 0x34
    }

    // MARK: - Mixer Controls

    struct Mixer {
        // Crossfader y Master (CC)
        static let crossfader: UInt8 = 114       // 0x72 ✅
        static let masterVolume: UInt8 = 0x09

        // Headphone cue (Notes)
        static let headphoneCueA: UInt8 = 0x40
        static let headphoneCueB: UInt8 = 0x41
    }

    // MARK: - Helper Methods

    /// Determina si una nota corresponde al Deck A
    static func isDeckA(note: UInt8) -> Bool {
        return (note >= 0x00 && note <= 0x1F)
    }

    /// Determina si una nota corresponde al Deck B
    static func isDeckB(note: UInt8) -> Bool {
        return (note >= 0x20 && note <= 0x3F)
    }

    /// Convierte un valor MIDI (0-127) a un rango normalizado (0.0-1.0)
    static func normalize(_ value: UInt8) -> Double {
        return Double(value) / 127.0
    }

    /// Convierte un valor normalizado (0.0-1.0) a valor MIDI (0-127)
    static func toMIDI(_ value: Double) -> UInt8 {
        return UInt8(min(max(value, 0.0), 1.0) * 127.0)
    }

    /// Convierte un valor MIDI a tempo multiplier (0.92-1.08, donde 64 = 1.0)
    static func toTempo(_ value: UInt8) -> Double {
        // 0 = 0.92x, 64 = 1.0x, 127 = 1.08x
        let normalized = Double(value) / 127.0
        return 0.92 + (normalized * 0.16)
    }

    /// Convierte un tempo multiplier (0.92-1.08) a valor MIDI
    static func tempoToMIDI(_ tempo: Double) -> UInt8 {
        let clamped = min(max(tempo, 0.92), 1.08)
        let normalized = (clamped - 0.92) / 0.16
        return UInt8(normalized * 127.0)
    }

    /// Convierte un valor MIDI a pitch en semitonos (-12 a +12)
    static func toPitch(_ value: UInt8) -> Double {
        // 0 = -12, 64 = 0, 127 = +12
        let normalized = Double(value) / 127.0
        return (normalized * 24.0) - 12.0
    }

    /// Convierte pitch en semitonos a valor MIDI
    static func pitchToMIDI(_ pitch: Double) -> UInt8 {
        let clamped = min(max(pitch, -12.0), 12.0)
        let normalized = (clamped + 12.0) / 24.0
        return UInt8(normalized * 127.0)
    }

    /// Convierte valor MIDI de EQ a ganancia en dB (-12 a +12)
    static func toEQGain(_ value: UInt8) -> Double {
        // 64 = 0dB (sin cambio)
        let centered = Double(value) - 64.0
        return (centered / 64.0) * 12.0
    }

    /// Convierte ganancia en dB a valor MIDI
    static func eqGainToMIDI(_ gain: Double) -> UInt8 {
        let clamped = min(max(gain, -12.0), 12.0)
        let normalized = (clamped / 12.0) * 64.0
        return UInt8(normalized + 64.0)
    }
}

// MARK: - MIDI Action Types

/// Acciones que puede realizar un control MIDI
enum MIDIAction {
    // Playback
    case togglePlayPause(deck: DeckID)
    case jumpToCue(deck: DeckID)
    case setCuePoint(deck: DeckID)
    case sync(deck: DeckID)

    // Hot Cues
    case triggerHotCue(deck: DeckID, slot: Int)

    // Jog Wheel
    case jogWheelTouch(deck: DeckID, pressed: Bool)
    case jogWheelRotate(deck: DeckID, delta: Int)

    // Controls
    case setTempo(deck: DeckID, tempo: Double)
    case setPitch(deck: DeckID, pitch: Double)
    case setVolume(deck: DeckID, volume: Double)

    // EQ
    case setEQHigh(deck: DeckID, gain: Double)
    case setEQMid(deck: DeckID, gain: Double)
    case setEQLow(deck: DeckID, gain: Double)

    // Mixer
    case setCrossfader(position: Double)
    case setMasterVolume(volume: Double)

    // Headphone
    case toggleHeadphoneCue(deck: DeckID)
}

/// Helper para mapear eventos MIDI a acciones
extension BehringerCMDStudio4aMapping {

    /// Convierte un evento MIDI Note en una acción
    static func actionFromNote(note: UInt8, velocity: UInt8, isOn: Bool) -> MIDIAction? {
        guard isOn else { return nil }  // Solo procesamos note on

        // Deck A
        if note == DeckA.playButton {
            return .togglePlayPause(deck: .deckA)
        }
        if note == DeckA.cueButton {
            return .jumpToCue(deck: .deckA)
        }
        if note == DeckA.syncButton {
            return .sync(deck: .deckA)
        }
        if note == DeckA.hotCue1 {
            return .triggerHotCue(deck: .deckA, slot: 0)
        }
        if note == DeckA.hotCue2 {
            return .triggerHotCue(deck: .deckA, slot: 1)
        }
        if note == DeckA.hotCue3 {
            return .triggerHotCue(deck: .deckA, slot: 2)
        }
        if note == DeckA.hotCue4 {
            return .triggerHotCue(deck: .deckA, slot: 3)
        }

        // Deck B
        if note == DeckB.playButton {
            return .togglePlayPause(deck: .deckB)
        }
        if note == DeckB.cueButton {
            return .jumpToCue(deck: .deckB)
        }
        if note == DeckB.syncButton {
            return .sync(deck: .deckB)
        }
        if note == DeckB.hotCue1 {
            return .triggerHotCue(deck: .deckB, slot: 0)
        }
        if note == DeckB.hotCue2 {
            return .triggerHotCue(deck: .deckB, slot: 1)
        }
        if note == DeckB.hotCue3 {
            return .triggerHotCue(deck: .deckB, slot: 2)
        }
        if note == DeckB.hotCue4 {
            return .triggerHotCue(deck: .deckB, slot: 3)
        }

        // Mixer
        if note == Mixer.headphoneCueA {
            return .toggleHeadphoneCue(deck: .deckA)
        }
        if note == Mixer.headphoneCueB {
            return .toggleHeadphoneCue(deck: .deckB)
        }

        return nil
    }

    /// Convierte un evento MIDI Pitch Bend en una acción
    static func actionFromPitchBend(channel: UInt8, value: Int) -> MIDIAction? {
        // Pitch bend range: 0 to 16368 (Behringer controller actual range)
        // Map to ±41% tempo range (0.59x to 1.41x) like VirtualDJ
        // Center at 8184 (16368 / 2) = 1.0x (natural tempo)
        let center = 8184.0
        let normalized = (Double(value) - center) / center  // -1.0 to +1.0
        let tempo = 1.0 + (normalized * 0.41)  // 0.59 to 1.41

        // Determine deck based on channel
        if channel == 0 {
            return .setTempo(deck: .deckA, tempo: tempo)
        } else if channel == 1 {
            return .setTempo(deck: .deckB, tempo: tempo)
        }

        return nil
    }

    /// Convierte un evento MIDI CC en una acción
    static func actionFromCC(controller: UInt8, value: UInt8, deck: DeckID?) -> MIDIAction? {

        // Deck A
        if controller == DeckA.volumeFader {
            let volume = normalize(value)
            return .setVolume(deck: .deckA, volume: volume)
        }
        if controller == DeckA.eqHigh {
            let gain = toEQGain(value)
            return .setEQHigh(deck: .deckA, gain: gain)
        }
        if controller == DeckA.eqMid {
            let gain = toEQGain(value)
            return .setEQMid(deck: .deckA, gain: gain)
        }
        if controller == DeckA.eqLow {
            let gain = toEQGain(value)
            return .setEQLow(deck: .deckA, gain: gain)
        }
        if controller == DeckA.jogWheelTouch {
            return .jogWheelTouch(deck: .deckA, pressed: value > 0)
        }

        // Deck B
        if controller == DeckB.pitchFader {
            let tempo = toTempo(value)
            return .setTempo(deck: .deckB, tempo: tempo)
        }
        if controller == DeckB.volumeFader {
            let volume = normalize(value)
            return .setVolume(deck: .deckB, volume: volume)
        }
        if controller == DeckB.eqHigh {
            let gain = toEQGain(value)
            return .setEQHigh(deck: .deckB, gain: gain)
        }
        if controller == DeckB.eqMid {
            let gain = toEQGain(value)
            return .setEQMid(deck: .deckB, gain: gain)
        }
        if controller == DeckB.eqLow {
            let gain = toEQGain(value)
            return .setEQLow(deck: .deckB, gain: gain)
        }
        if controller == DeckB.jogWheelTouch {
            return .jogWheelTouch(deck: .deckB, pressed: value > 0)
        }

        // Mixer
        if controller == Mixer.crossfader {
            let position = normalize(value)
            return .setCrossfader(position: position)
        }
        if controller == Mixer.masterVolume {
            let volume = normalize(value)
            return .setMasterVolume(volume: volume)
        }

        return nil
    }
}
