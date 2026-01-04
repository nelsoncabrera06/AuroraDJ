//
//  ZoomedWaveformView.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 27.12.2025.
//

import SwiftUI

/// Vista de waveform con zoom que muestra una ventana temporal móvil
/// ESTILO VIRTUALDJ: Playhead siempre en el centro, waveform se desplaza
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
    let visibleWindowSeconds: TimeInterval

    /// Tempo actual (0.5 a 2.0) - ajusta la ventana visible
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
                // Dibujar waveform con ventana móvil
                drawScrollingWaveform(context: context, size: size, data: data)

                // Dibujar playhead siempre en el centro
                drawPlayhead(context: context, size: size, x: size.width / 2)
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

    /// Dibuja el waveform con scroll - ESTILO VIRTUALDJ
    /// El waveform siempre está centrado en currentTime, mostrando espacio vacío al inicio/final
    private func drawScrollingWaveform(context: GraphicsContext, size: CGSize, data: WaveformData) {
        let samples = data.samples
        guard samples.count > 0, data.duration > 0 else { return }

        // Ajustar ventana visible por tempo
        let tempoAdjustedWindow = visibleWindowSeconds / tempo
        let windowDuration = tempoAdjustedWindow

        // ESTILO VIRTUALDJ: Siempre centrar en currentTime (puede ser negativo al inicio)
        let startTime = currentTime - (windowDuration / 2.0)
        let endTime = currentTime + (windowDuration / 2.0)

        // Calcular qué parte de la ventana tiene audio real
        let audioStartTime = max(0, startTime)
        let audioEndTime = min(data.duration, endTime)

        // Si no hay audio visible, salir
        guard audioEndTime > audioStartTime else { return }

        // Convertir tiempos a índices de samples
        let audioStartIndex = data.sampleIndex(for: audioStartTime)
        let audioEndIndex = data.sampleIndex(for: audioEndTime)
        let visibleSamples = Array(samples[audioStartIndex...min(audioEndIndex, samples.count - 1)])

        guard visibleSamples.count > 0 else { return }

        // Calcular offset X donde empieza el audio real
        let audioOffsetX: CGFloat
        if startTime < 0 {
            let emptyDuration = -startTime
            audioOffsetX = CGFloat(emptyDuration / windowDuration) * size.width
        } else {
            audioOffsetX = 0
        }

        // Calcular ancho disponible para el audio
        let audioDuration = audioEndTime - audioStartTime
        let audioWidth = CGFloat(audioDuration / windowDuration) * size.width

        // Calcular dimensiones de las barras
        let barWidth = audioWidth / CGFloat(visibleSamples.count)
        let centerY = size.height / 2
        let maxHeight = (size.height / 2) * 0.9

        // Dibujar todas las barras con un solo path (sin gradiente de opacidad)
        let waveformPath = Path { p in
            for (index, amplitude) in visibleSamples.enumerated() {
                let x = audioOffsetX + CGFloat(index) * barWidth
                let barHeight = CGFloat(amplitude) * maxHeight

                p.move(to: CGPoint(x: x, y: centerY - barHeight))
                p.addLine(to: CGPoint(x: x, y: centerY + barHeight))
            }
        }

        context.stroke(
            waveformPath,
            with: .color(color),
            lineWidth: max(1, barWidth * 0.8)
        )
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
        // Zoomed waveform con datos (simulado)
        ZoomedWaveformView(
            waveformData: WaveformData(
                trackID: UUID(),
                samples: (0..<1000).map { _ in Float.random(in: 0.2...1.0) },
                samplesPerSecond: 50,
                duration: 180
            ),
            currentTime: 60,
            duration: 180,
            color: .cyan,
            height: 100,
            visibleWindowSeconds: 30,
            tempo: 1.0
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
