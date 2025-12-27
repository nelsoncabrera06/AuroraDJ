//
//  DeckState.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation

/// Identifica cada deck
enum DeckID: String, CaseIterable {
    case deckA = "A"
    case deckB = "B"
}

/// Estado de reproducción de un deck
struct DeckState {
    var currentTrack: Track?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var tempo: Double = 1.0          // 1.0 = velocidad normal (0.5 a 2.0)
    var pitch: Double = 0.0          // Semitones (-12 a +12)
    var volume: Double = 0.75        // 0.0 a 1.0
    var cuePoint: TimeInterval?
    var hotCuePoints: [Int: TimeInterval] = [:] // Hasta 4 hot cues (0-3)
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?
    var isLooping: Bool = false

    /// Duración de la pista actual
    var duration: TimeInterval {
        currentTrack?.duration ?? 0
    }

    /// Progreso de reproducción (0.0 a 1.0)
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    /// Tiempo restante
    var timeRemaining: TimeInterval {
        return duration - currentTime
    }

    /// Formatea el tiempo actual en MM:SS
    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    /// Formatea el tiempo restante en -MM:SS
    var formattedTimeRemaining: String {
        let remaining = timeRemaining
        let sign = remaining >= 0 ? "-" : "+"
        return sign + formatTime(abs(remaining))
    }

    /// Formatea un tiempo en formato MM:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Verifica si hay una pista cargada
    var hasTrack: Bool {
        currentTrack != nil
    }

    /// Retorna el tempo como porcentaje para display (+8.0% por ejemplo)
    var tempoPercentage: String {
        let percent = (tempo - 1.0) * 100
        let sign = percent >= 0 ? "+" : ""
        return String(format: "%@%.1f%%", sign, percent)
    }

    /// Retorna el pitch en semitonos para display (+3 por ejemplo)
    var pitchDisplay: String {
        let sign = pitch >= 0 ? "+" : ""
        return String(format: "%@%.0f", sign, pitch)
    }

    /// Retorna los BPM originales de la pista
    var originalBPM: Double? {
        currentTrack?.bpm
    }

    /// Retorna los BPM actuales (ajustados por tempo)
    var currentBPM: Double? {
        guard let bpm = originalBPM else { return nil }
        return bpm * tempo
    }

    /// Formatea los BPM para mostrar
    var formattedBPM: String {
        if let currentBPM = currentBPM, let originalBPM = originalBPM {
            if tempo == 1.0 {
                return String(format: "%.1f BPM", originalBPM)
            } else {
                return String(format: "%.1f BPM (%.1f)", currentBPM, originalBPM)
            }
        }
        return "-- BPM"
    }

    /// Datos de waveform del track actual
    var waveformData: WaveformData? {
        currentTrack?.waveformData
    }
}
