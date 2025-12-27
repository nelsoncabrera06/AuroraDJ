//
//  WaveformData.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 27.12.2025.
//

import Foundation

/// Datos de forma de onda para visualización
struct WaveformData: Equatable {
    /// ID del track al que pertenece este waveform
    let trackID: UUID

    /// Muestras de amplitud RMS normalizadas (0.0 a 1.0)
    let samples: [Float]

    /// Número de muestras por segundo (típicamente 50)
    let samplesPerSecond: Int

    /// Duración total del track en segundos
    let duration: TimeInterval

    // MARK: - Computed Properties

    /// Número total de muestras
    var totalSamples: Int {
        samples.count
    }

    /// Intervalo de tiempo entre muestras consecutivas
    var sampleInterval: TimeInterval {
        1.0 / Double(samplesPerSecond)
    }

    // MARK: - Helper Methods

    /// Obtiene el índice de muestra para un tiempo dado
    /// - Parameter time: Tiempo en segundos
    /// - Returns: Índice de la muestra correspondiente
    func sampleIndex(for time: TimeInterval) -> Int {
        let index = Int(time * Double(samplesPerSecond))
        return min(max(index, 0), samples.count - 1)
    }

    /// Obtiene el valor de amplitud para un tiempo dado
    /// - Parameter time: Tiempo en segundos
    /// - Returns: Amplitud normalizada (0.0 a 1.0)
    func amplitude(at time: TimeInterval) -> Float {
        let index = sampleIndex(for: time)
        return samples[index]
    }
}
