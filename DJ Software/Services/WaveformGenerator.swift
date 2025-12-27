//
//  WaveformGenerator.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 27.12.2025.
//

import Foundation
import AVFoundation
import Accelerate

/// Servicio para generar datos de forma de onda desde archivos de audio
class WaveformGenerator {

    // MARK: - Constants

    /// Número de muestras por segundo para la visualización
    private static let samplesPerSecond = 50

    /// Tamaño de ventana para cálculo RMS
    private static let rmsWindowSize = 2048

    // MARK: - Public Methods

    /// Genera datos de waveform desde un archivo de audio
    /// - Parameters:
    ///   - url: URL del archivo de audio
    ///   - trackID: ID del track para asociación
    /// - Returns: WaveformData o nil si hay error
    static func generate(from url: URL, trackID: UUID) async -> WaveformData? {
        do {
            // 1. Cargar archivo de audio
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let totalFrames = audioFile.length
            let sampleRate = format.sampleRate
            let duration = Double(totalFrames) / sampleRate

            print("📊 Generating waveform: \(url.lastPathComponent)")
            print("   Duration: \(String(format: "%.1f", duration))s, Sample Rate: \(sampleRate)Hz")

            // 2. Calcular número de muestras necesarias
            let targetSampleCount = Int(duration * Double(samplesPerSecond))
            let framesPerSample = max(1, Int(totalFrames) / targetSampleCount)

            print("   Target samples: \(targetSampleCount), Frames per sample: \(framesPerSample)")

            // 3. Procesar audio en chunks
            var waveformSamples: [Float] = []
            waveformSamples.reserveCapacity(targetSampleCount)

            let bufferSize = min(rmsWindowSize, framesPerSample)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(bufferSize)
            ) else {
                print("❌ Failed to create audio buffer")
                return nil
            }

            // 4. Leer y calcular RMS para cada muestra
            var processedFrames = 0
            let totalFramesInt = Int(totalFrames)

            for targetFrame in stride(from: 0, to: totalFramesInt, by: framesPerSample) {
                // Posicionar el lector
                audioFile.framePosition = AVAudioFramePosition(targetFrame)

                // Leer chunk de audio
                let framesToRead = min(bufferSize, totalFramesInt - targetFrame)
                buffer.frameLength = 0 // Reset buffer

                do {
                    try audioFile.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
                } catch {
                    // Si hay error leyendo, usar silencio
                    waveformSamples.append(0.0)
                    continue
                }

                // Calcular RMS para este chunk
                let rms = calculateRMS(buffer: buffer)
                waveformSamples.append(rms)

                processedFrames += framesPerSample
            }

            // 5. Normalizar a rango 0.0-1.0
            let maxAmplitude = waveformSamples.max() ?? 1.0
            if maxAmplitude > 0 {
                waveformSamples = waveformSamples.map { $0 / maxAmplitude }
            }

            print("   ✅ Waveform generated: \(waveformSamples.count) samples")

            return WaveformData(
                trackID: trackID,
                samples: waveformSamples,
                samplesPerSecond: samplesPerSecond,
                duration: duration
            )

        } catch {
            print("❌ Waveform generation error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Methods

    /// Calcula RMS (Root Mean Square) desde un buffer de audio
    /// - Parameter buffer: Buffer de audio PCM
    /// - Returns: Valor RMS normalizado
    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        let channelCount = Int(buffer.format.channelCount)

        var sumSquares: Float = 0.0

        // Mezclar a mono y calcular RMS
        if channelCount == 2 {
            // Estéreo: promediar ambos canales
            let leftChannel = channelData[0]
            let rightChannel = channelData[1]

            for i in 0..<frameLength {
                let mono = (leftChannel[i] + rightChannel[i]) / 2.0
                sumSquares += mono * mono
            }
        } else if channelCount == 1 {
            // Mono: usar directamente
            let channel = channelData[0]

            for i in 0..<frameLength {
                let sample = channel[i]
                sumSquares += sample * sample
            }
        } else {
            // Multicanal: promediar todos los canales
            for i in 0..<frameLength {
                var sum: Float = 0.0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                let avg = sum / Float(channelCount)
                sumSquares += avg * avg
            }
        }

        // Calcular RMS
        let rms = sqrt(sumSquares / Float(frameLength))

        return rms
    }
}
