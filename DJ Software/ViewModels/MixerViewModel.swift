//
//  MixerViewModel.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import Combine

@MainActor
class MixerViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var crossfaderPosition: Double = 0.5 // 0.0 = Full A, 1.0 = Full B

    // EQ values for Deck A
    @Published var eqHighA: Double = 0.5 // 0.5 = 0dB
    @Published var eqMidA: Double = 0.5
    @Published var eqLowA: Double = 0.5

    // EQ values for Deck B
    @Published var eqHighB: Double = 0.5
    @Published var eqMidB: Double = 0.5
    @Published var eqLowB: Double = 0.5

    // Volume faders for each deck (0.0 to 1.0)
    @Published var deckAVolume: Double = 1.0
    @Published var deckBVolume: Double = 1.0

    // MARK: - Properties

    private let audioEngine: AudioEngine

    // MARK: - Initialization

    init(audioEngine: AudioEngine) {
        self.audioEngine = audioEngine
    }

    // MARK: - Crossfader Control

    /// Actualiza la posición del crossfader (0.0 = Full A, 1.0 = Full B)
    func setCrossfaderPosition(_ position: Double) {
        crossfaderPosition = position
        applyMixerVolumes()
    }

    /// Actualiza el volumen de un deck desde el fader de volumen
    func setDeckVolume(_ volume: Double, deck: DeckID) {
        switch deck {
        case .deckA:
            deckAVolume = volume
        case .deckB:
            deckBVolume = volume
        }
        applyMixerVolumes()
    }

    /// Calcula y aplica los volúmenes finales combinando faders de deck y crossfader
    private func applyMixerVolumes() {
        // Calculate crossfader curve
        let crossfaderA: Double
        let crossfaderB: Double

        if crossfaderPosition <= 0.5 {
            // Left half: A at full, B fading in
            crossfaderA = 1.0
            crossfaderB = crossfaderPosition * 2.0 // 0.0 to 1.0
        } else {
            // Right half: B at full, A fading out
            crossfaderA = (1.0 - crossfaderPosition) * 2.0 // 1.0 to 0.0
            crossfaderB = 1.0
        }

        // Multiply deck volume by crossfader position
        let finalVolumeA = deckAVolume * crossfaderA
        let finalVolumeB = deckBVolume * crossfaderB

        // Apply to audio engine
        audioEngine.setVolume(finalVolumeA, deck: .deckA)
        audioEngine.setVolume(finalVolumeB, deck: .deckB)

        print("🎚️ Crossfader: \(Int(crossfaderPosition * 100))% | Deck A: \(Int(deckAVolume * 100))% × \(Int(crossfaderA * 100))% = \(Int(finalVolumeA * 100))% | Deck B: \(Int(deckBVolume * 100))% × \(Int(crossfaderB * 100))% = \(Int(finalVolumeB * 100))%")
    }

    // MARK: - EQ Control

    /// Actualiza el EQ de un deck desde MIDI (0.0 a 1.0)
    func setEQ(_ band: EQBand, value: Double, deck: DeckID) {
        // Convert 0.0-1.0 to -12dB to +12dB
        let gain = (value - 0.5) * 24.0

        // Update the published property
        switch (deck, band) {
        case (.deckA, .high):
            eqHighA = value
        case (.deckA, .mid):
            eqMidA = value
        case (.deckA, .low):
            eqLowA = value
        case (.deckB, .high):
            eqHighB = value
        case (.deckB, .mid):
            eqMidB = value
        case (.deckB, .low):
            eqLowB = value
        }

        // Apply to audio engine
        audioEngine.setEQ(deck: deck, band: band, gain: gain)
        print("🎚️ EQ \(band) Deck \(deck.rawValue): \(String(format: "%+.1fdB", gain))")
    }
}
