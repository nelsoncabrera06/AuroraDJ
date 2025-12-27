//
//  WaveformView.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 27.12.2025.
//

import SwiftUI

/// Vista que muestra la forma de onda de audio con indicador de posición
struct WaveformView: View {
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

    var body: some View {
        Canvas { context, size in
            if let data = waveformData {
                // Dibujar waveform
                drawWaveform(context: context, size: size, data: data)

                // Dibujar playhead
                drawPlayhead(context: context, size: size)
            } else {
                // Estado vacío
                drawEmptyState(context: context, size: size)
            }
        }
        .frame(height: height)
        .background(Color.black.opacity(0.8))
        .cornerRadius(4)
    }

    // MARK: - Drawing Methods

    /// Dibuja el waveform como barras verticales simétricas
    private func drawWaveform(context: GraphicsContext, size: CGSize, data: WaveformData) {
        let samples = data.samples
        guard samples.count > 0 else { return }

        let barWidth = size.width / CGFloat(samples.count)
        let centerY = size.height / 2
        let maxHeight = (size.height / 2) * 0.9 // 90% de la mitad de altura

        for (index, amplitude) in samples.enumerated() {
            let x = CGFloat(index) * barWidth
            let barHeight = CGFloat(amplitude) * maxHeight

            // Waveform simétrico (espejo arriba/abajo)
            let path = Path { p in
                p.move(to: CGPoint(x: x, y: centerY - barHeight))
                p.addLine(to: CGPoint(x: x, y: centerY + barHeight))
            }

            context.stroke(
                path,
                with: .color(color.opacity(0.8)),
                lineWidth: max(1, barWidth * 0.8)
            )
        }
    }

    /// Dibuja el indicador de playhead (línea vertical blanca)
    private func drawPlayhead(context: GraphicsContext, size: CGSize) {
        guard duration > 0 else { return }

        // Calcular posición X basada en progreso
        let progress = min(max(currentTime / duration, 0), 1)
        let x = size.width * progress

        // Línea vertical
        let path = Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }

        context.stroke(
            path,
            with: .color(.white),
            lineWidth: 2
        )

        // Triángulo superior para mejor visibilidad
        let triangleSize: CGFloat = 8
        let trianglePath = Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x - triangleSize/2, y: triangleSize))
            p.addLine(to: CGPoint(x: x + triangleSize/2, y: triangleSize))
            p.closeSubpath()
        }

        context.fill(trianglePath, with: .color(.white))
    }

    /// Dibuja el estado vacío cuando no hay waveform
    private func drawEmptyState(context: GraphicsContext, size: CGSize) {
        let centerY = size.height / 2

        // Línea horizontal punteada
        let path = Path { p in
            p.move(to: CGPoint(x: 0, y: centerY))
            p.addLine(to: CGPoint(x: size.width, y: centerY))
        }

        context.stroke(
            path,
            with: .color(.gray.opacity(0.3)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Waveform con datos (simulado)
        WaveformView(
            waveformData: WaveformData(
                trackID: UUID(),
                samples: (0..<100).map { _ in Float.random(in: 0.2...1.0) },
                samplesPerSecond: 50,
                duration: 180
            ),
            currentTime: 60,
            duration: 180,
            color: .blue,
            height: 70
        )
        .padding()

        // Waveform sin datos
        WaveformView(
            waveformData: nil,
            currentTime: 0,
            duration: 0,
            color: .red,
            height: 70
        )
        .padding()
    }
    .background(Color.gray.opacity(0.2))
}
