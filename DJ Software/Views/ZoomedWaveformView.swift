//
//  ZoomedWaveformView.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 27.12.2025.
//

import SwiftUI

/// Vista de waveform con zoom que muestra una ventana temporal móvil
/// Similar a VirtualDJ - el playhead está fijo en el centro y el waveform se mueve
struct ZoomedWaveformView: View {
    /// Datos de waveform a visualizar
    let waveformData: WaveformData?

    /// Tiempo actual de reproducción en segundos
    let currentTime: TimeInterval

    /// Duración total del track
    let duration: TimeInterval

    /// Color del waveform (azul para Deck A, rojo para Deck B)
    let color: Color

    /// Altura del componente
    let height: CGFloat

    /// Ventana visible en segundos (cuántos segundos mostrar a la vez)
    /// Por ejemplo: 30 segundos = ~10-12 compases a 120 BPM
    let visibleWindowSeconds: TimeInterval

    /// Tempo actual (0.5 a 2.0) - ajusta la ventana visible
    /// Si tempo = 1.2, muestra más segundos de audio (comprimido)
    /// Si tempo = 0.8, muestra menos segundos de audio (estirado)
    let tempo: Double

    init(
        waveformData: WaveformData?,
        currentTime: TimeInterval,
        duration: TimeInterval,
        color: Color,
        height: CGFloat,
        visibleWindowSeconds: TimeInterval = 30.0,
        tempo: Double = 1.0
    ) {
        self.waveformData = waveformData
        self.currentTime = currentTime
        self.duration = duration
        self.color = color
        self.height = height
        self.visibleWindowSeconds = visibleWindowSeconds
        self.tempo = tempo
    }

    var body: some View {
        Canvas { context, size in
            if let data = waveformData {
                // Calcular playheadX basado en la ventana visible
                let playheadX = calculatePlayheadX(data: data, size: size)

                // Dibujar waveform con ventana móvil
                drawScrollingWaveform(context: context, size: size, data: data)

                // Dibujar playhead en la posición calculada
                drawPlayhead(context: context, size: size, x: playheadX)
            } else {
                // Estado vacío
                drawEmptyState(context: context, size: size)
            }
        }
        .frame(height: height)
        .background(Color.black.opacity(0.9))
        .cornerRadius(4)
    }

    // MARK: - Drawing Methods

    /// Calcula la posición X del playhead basado en la ventana visible
    private func calculatePlayheadX(data: WaveformData, size: CGSize) -> CGFloat {
        guard data.duration > 0 else { return size.width / 2 }

        // Calcular ventana visible ajustada por tempo
        let tempoAdjustedWindow = visibleWindowSeconds / tempo
        let windowDuration = min(tempoAdjustedWindow, data.duration)
        var startTime: TimeInterval

        if currentTime < windowDuration / 2.0 {
            // Inicio: ventana fija desde 0
            startTime = 0
        } else if currentTime > data.duration - (windowDuration / 2.0) {
            // Final: ventana fija al final
            startTime = max(0, data.duration - windowDuration)
        } else {
            // Medio: ventana centrada
            startTime = currentTime - (windowDuration / 2.0)
        }

        let endTime = startTime + windowDuration

        // Calcular posición del playhead dentro de la ventana visible
        let playheadTimeInWindow = currentTime - startTime
        let windowSpan = endTime - startTime

        return windowSpan > 0 ? (playheadTimeInWindow / windowSpan) * size.width : size.width / 2
    }

    /// Dibuja el waveform con scroll - muestra solo la ventana visible alrededor del tiempo actual
    private func drawScrollingWaveform(context: GraphicsContext, size: CGSize, data: WaveformData) {
        let samples = data.samples
        guard samples.count > 0, data.duration > 0 else { return }

        // Ajustar ventana visible por tempo
        // Si tempo > 1.0 (más rápido), mostrar más segundos de audio (comprimido)
        // Si tempo < 1.0 (más lento), mostrar menos segundos de audio (estirado)
        // Esto hace que el waveform coincida con lo que escuchas
        let tempoAdjustedWindow = visibleWindowSeconds / tempo
        let windowDuration = min(tempoAdjustedWindow, data.duration)
        var startTime: TimeInterval
        var endTime: TimeInterval

        if currentTime < windowDuration / 2.0 {
            // Inicio: ventana fija desde 0
            startTime = 0
            endTime = windowDuration
        } else if currentTime > data.duration - (windowDuration / 2.0) {
            // Final: ventana fija al final
            startTime = max(0, data.duration - windowDuration)
            endTime = data.duration
        } else {
            // Medio: ventana centrada
            startTime = currentTime - (windowDuration / 2.0)
            endTime = currentTime + (windowDuration / 2.0)
        }

        // Convertir tiempos a índices de samples
        let startIndex = data.sampleIndex(for: startTime)
        let endIndex = data.sampleIndex(for: endTime)
        let visibleSamples = Array(samples[startIndex...min(endIndex, samples.count - 1)])

        guard visibleSamples.count > 0 else { return }

        // Calcular ancho de cada barra
        let barWidth = size.width / CGFloat(visibleSamples.count)
        let centerY = size.height / 2
        let maxHeight = (size.height / 2) * 0.9

        // Dibujar las barras visibles
        for (index, amplitude) in visibleSamples.enumerated() {
            let x = CGFloat(index) * barWidth
            let barHeight = CGFloat(amplitude) * maxHeight

            // Waveform simétrico
            let path = Path { p in
                p.move(to: CGPoint(x: x, y: centerY - barHeight))
                p.addLine(to: CGPoint(x: x, y: centerY + barHeight))
            }

            // Variar opacidad según distancia del centro (efecto de profundidad)
            let distanceFromCenter = abs(CGFloat(index) - CGFloat(visibleSamples.count) / 2.0)
            let maxDistance = CGFloat(visibleSamples.count) / 2.0
            let normalizedDistance = distanceFromCenter / maxDistance
            let opacity = 0.4 + (1.0 - normalizedDistance) * 0.6 // 0.4 a 1.0

            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                lineWidth: max(1, barWidth * 0.8)
            )
        }
    }

    /// Dibuja el playhead en la posición X especificada
    private func drawPlayhead(context: GraphicsContext, size: CGSize, x: CGFloat) {
        // Línea vertical principal
        let linePath = Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }

        context.stroke(
            linePath,
            with: .color(.white),
            lineWidth: 3
        )

        // Triángulo superior
        let triangleSize: CGFloat = 10
        let topTriangle = Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x - triangleSize/2, y: triangleSize))
            p.addLine(to: CGPoint(x: x + triangleSize/2, y: triangleSize))
            p.closeSubpath()
        }

        context.fill(topTriangle, with: .color(.white))

        // Triángulo inferior
        let bottomTriangle = Path { p in
            p.move(to: CGPoint(x: x, y: size.height))
            p.addLine(to: CGPoint(x: x - triangleSize/2, y: size.height - triangleSize))
            p.addLine(to: CGPoint(x: x + triangleSize/2, y: size.height - triangleSize))
            p.closeSubpath()
        }

        context.fill(bottomTriangle, with: .color(.white))
    }

    /// Dibuja el estado vacío cuando no hay waveform
    private func drawEmptyState(context: GraphicsContext, size: CGSize) {
        let centerY = size.height / 2
        let centerX = size.width / 2

        // Línea horizontal punteada
        let horizontalPath = Path { p in
            p.move(to: CGPoint(x: 0, y: centerY))
            p.addLine(to: CGPoint(x: size.width, y: centerY))
        }

        context.stroke(
            horizontalPath,
            with: .color(.gray.opacity(0.3)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
        )

        // Línea vertical en el centro
        let verticalPath = Path { p in
            p.move(to: CGPoint(x: centerX, y: 0))
            p.addLine(to: CGPoint(x: centerX, y: size.height))
        }

        context.stroke(
            verticalPath,
            with: .color(.gray.opacity(0.3)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Zoomed waveform con datos (simulado) - tempo normal
        ZoomedWaveformView(
            waveformData: WaveformData(
                trackID: UUID(),
                samples: (0..<1000).map { _ in Float.random(in: 0.2...1.0) },
                samplesPerSecond: 50,
                duration: 180
            ),
            currentTime: 60,
            duration: 180,
            color: .blue,
            height: 100,
            visibleWindowSeconds: 30,
            tempo: 1.0
        )
        .padding()

        // Zoomed waveform con tempo rápido (1.2x)
        ZoomedWaveformView(
            waveformData: WaveformData(
                trackID: UUID(),
                samples: (0..<1000).map { _ in Float.random(in: 0.2...1.0) },
                samplesPerSecond: 50,
                duration: 180
            ),
            currentTime: 60,
            duration: 180,
            color: .green,
            height: 100,
            visibleWindowSeconds: 30,
            tempo: 1.2
        )
        .padding()

        // Zoomed waveform sin datos
        ZoomedWaveformView(
            waveformData: nil,
            currentTime: 0,
            duration: 0,
            color: .red,
            height: 100
        )
        .padding()
    }
    .background(Color.gray.opacity(0.2))
}
