//
//  BPMDetector.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import AVFoundation
import Accelerate

/// Servicio para detectar BPM de archivos de audio
class BPMDetector {

    /// Detecta el BPM de un archivo de audio
    /// - Parameter url: URL del archivo de audio
    /// - Returns: BPM detectado (Double) o nil si falla
    static func detectBPM(from url: URL) async -> Double? {
        do {
            // Load audio file
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = UInt32(audioFile.length)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                print("❌ Failed to create audio buffer")
                return nil
            }

            try audioFile.read(into: buffer)

            guard let channelData = buffer.floatChannelData else {
                print("❌ No channel data available")
                return nil
            }

            let channelCount = Int(buffer.format.channelCount)
            let frameLength = Int(buffer.frameLength)
            let sampleRate = format.sampleRate

            // Convert to mono if stereo
            var samples: [Float]
            if channelCount == 2 {
                samples = stride(from: 0, to: frameLength, by: 1).map { index in
                    (channelData[0][index] + channelData[1][index]) / 2.0
                }
            } else {
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            }

            // Calculate energy envelope (simplified beat detection)
            let bpm = calculateBPM(from: samples, sampleRate: sampleRate)

            print("✅ BPM detected: \(Int(bpm)) BPM")
            return bpm

        } catch {
            print("❌ BPM detection error: \(error)")
            return nil
        }
    }

    /// Calcula el BPM usando autocorrelación
    private static func calculateBPM(from samples: [Float], sampleRate: Double) -> Double {
        // Downsample para procesamiento más rápido
        let downsampleFactor = 4
        let downsampledSamples = stride(from: 0, to: samples.count, by: downsampleFactor).map { samples[$0] }
        let downsampledRate = sampleRate / Double(downsampleFactor)

        // Calculate RMS energy envelope (using squared values)
        let windowSize = 1024
        let hopSize = windowSize / 2
        var energyEnvelope: [Float] = []

        for i in stride(from: 0, to: downsampledSamples.count - windowSize, by: hopSize) {
            let window = Array(downsampledSamples[i..<min(i + windowSize, downsampledSamples.count)])
            // Use RMS (root mean square) instead of absolute values
            let sumSquares = window.reduce(0.0) { $0 + ($1 * $1) }
            let rms = sqrt(sumSquares / Float(window.count))
            energyEnvelope.append(rms)
        }

        // Normalize energy
        if let maxEnergy = energyEnvelope.max(), maxEnergy > 0 {
            energyEnvelope = energyEnvelope.map { $0 / maxEnergy }
        }

        // Apply onset detection (first-order difference with half-wave rectification)
        var onsets: [Float] = []
        for i in 1..<energyEnvelope.count {
            let diff = energyEnvelope[i] - energyEnvelope[i - 1]
            // Only keep positive changes (onsets)
            onsets.append(max(0, diff))
        }

        // Apply smoothing to onsets
        var smoothedOnsets: [Float] = []
        let smoothWindow = 3
        for i in 0..<onsets.count {
            let start = max(0, i - smoothWindow)
            let end = min(onsets.count, i + smoothWindow + 1)
            let avg = onsets[start..<end].reduce(0.0, +) / Float(end - start)
            smoothedOnsets.append(avg)
        }

        // Autocorrelation to find tempo
        let bpm = findTempo(from: smoothedOnsets, sampleRate: downsampledRate, hopSize: hopSize)

        return bpm
    }

    /// Encuentra el tempo usando autocorrelación normalizada
    private static func findTempo(from signal: [Float], sampleRate: Double, hopSize: Int) -> Double {
        // BPM range: 60-180 (common for most music)
        let minBPM = 60.0
        let maxBPM = 180.0

        // Convert BPM to samples (lag in onset envelope frames)
        let samplesPerFrame = Double(hopSize) / sampleRate
        let minInterval = Int((60.0 / maxBPM) / samplesPerFrame)
        let maxInterval = Int((60.0 / minBPM) / samplesPerFrame)

        // Calculate energy at lag 0 for normalization
        var energy0: Float = 0
        for i in 0..<signal.count {
            energy0 += signal[i] * signal[i]
        }

        // Normalized autocorrelation
        var bestCorrelation: Float = 0
        var bestLag = minInterval

        for lag in minInterval..<min(maxInterval, signal.count / 2) {
            var correlation: Float = 0
            var energyLag: Float = 0
            var count = 0

            for i in 0..<(signal.count - lag) {
                correlation += signal[i] * signal[i + lag]
                energyLag += signal[i + lag] * signal[i + lag]
                count += 1
            }

            // Normalize by geometric mean of energies
            let normalization = sqrt(energy0 * energyLag)
            if normalization > 0 {
                correlation /= normalization
            }

            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        // Refine peak with parabolic interpolation for sub-sample accuracy
        var refinedLag = Double(bestLag)

        // If we're not at the edges, do parabolic interpolation
        if bestLag > minInterval && bestLag < min(maxInterval - 1, signal.count / 2 - 1) {
            // Get neighboring correlation values
            let prev = calculateNormalizedCorrelation(signal: signal, lag: bestLag - 1, energy0: energy0)
            let curr = bestCorrelation
            let next = calculateNormalizedCorrelation(signal: signal, lag: bestLag + 1, energy0: energy0)

            // Parabolic interpolation
            let delta = 0.5 * (next - prev) / (2.0 * curr - prev - next)
            refinedLag = Double(bestLag) + Double(delta)
        }

        // Convert lag to BPM
        let intervalInSeconds = refinedLag * samplesPerFrame
        var bpm = 60.0 / intervalInSeconds

        // Intelligent harmonic refinement
        bpm = refineHarmonic(bpm: bpm, correlation: bestCorrelation)

        // Round to 1 decimal place for display
        return round(bpm * 10.0) / 10.0
    }

    /// Calcula correlación normalizada para un lag específico
    private static func calculateNormalizedCorrelation(signal: [Float], lag: Int, energy0: Float) -> Float {
        var correlation: Float = 0
        var energyLag: Float = 0

        for i in 0..<(signal.count - lag) {
            correlation += signal[i] * signal[i + lag]
            energyLag += signal[i + lag] * signal[i + lag]
        }

        let normalization = sqrt(energy0 * energyLag)
        return normalization > 0 ? correlation / normalization : 0
    }

    /// Refina el BPM detectado evaluando armónicos
    private static func refineHarmonic(bpm: Double, correlation: Float) -> Double {
        let harmonics = [0.5, 1.0, 2.0, 3.0]
        let targetRange = 90.0...140.0 // Ideal range for most dance music

        var bestBPM = bpm
        var bestScore: Double = 0

        for harmonic in harmonics {
            let candidateBPM = bpm * harmonic

            // Score based on: 1) being in target range, 2) correlation strength
            var score = Double(correlation)

            // Bonus for being in target range
            if targetRange.contains(candidateBPM) {
                score *= 1.5
            }

            // Penalty for extreme values
            if candidateBPM < 70 || candidateBPM > 180 {
                score *= 0.5
            }

            if score > bestScore {
                bestScore = score
                bestBPM = candidateBPM
            }
        }

        return bestBPM
    }
}
