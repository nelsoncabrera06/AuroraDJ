//
//  MixerView.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import SwiftUI

struct MixerView: View {
    @ObservedObject var viewModel: MixerViewModel

    var body: some View {
        VStack(spacing: 20) {
            Text("MIXER")
                .font(.headline)
                .foregroundColor(.secondary)

            // EQ Controls for both decks
            HStack(spacing: 40) {
                // Deck A Channel Strip
                VStack(spacing: 15) {
                    Text("DECK A")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // EQ Knobs
                    EQKnobView(label: "HIGH", value: $viewModel.eqHighA, color: .blue)
                    EQKnobView(label: "MID", value: $viewModel.eqMidA, color: .blue)
                    EQKnobView(label: "LOW", value: $viewModel.eqLowA, color: .blue)

                    Spacer()
                        .frame(height: 10)

                    // Volume Fader (vertical)
                    Text("VOLUME")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    VerticalFaderView(value: $viewModel.deckAVolume, color: .blue)
                        .frame(width: 40, height: 120)
                        // OPTIMIZADO v2: Eliminado onChange redundante - el binding ya actualiza el ViewModel

                    Text("\(Int(viewModel.deckAVolume * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Divider()
                    .frame(height: 400)

                // Deck B Channel Strip
                VStack(spacing: 15) {
                    Text("DECK B")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // EQ Knobs
                    EQKnobView(label: "HIGH", value: $viewModel.eqHighB, color: .red)
                    EQKnobView(label: "MID", value: $viewModel.eqMidB, color: .red)
                    EQKnobView(label: "LOW", value: $viewModel.eqLowB, color: .red)

                    Spacer()
                        .frame(height: 10)

                    // Volume Fader (vertical)
                    Text("VOLUME")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    VerticalFaderView(value: $viewModel.deckBVolume, color: .red)
                        .frame(width: 40, height: 120)
                        // OPTIMIZADO v2: Eliminado onChange redundante

                    Text("\(Int(viewModel.deckBVolume * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()

            // Crossfader
            VStack(spacing: 10) {
                Text("CROSSFADER")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 15) {
                    Text("A")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)

                    CrossfaderView(position: $viewModel.crossfaderPosition)
                        .frame(width: 300, height: 60)
                        // OPTIMIZADO v2: Eliminado onChange redundante

                    Text("B")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }

                // Crossfader position indicator
                Text(crossfaderPositionText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
    }

    private var crossfaderPositionText: String {
        if viewModel.crossfaderPosition < 0.45 {
            return "← DECK A \(Int((0.5 - viewModel.crossfaderPosition) * 200))%"
        } else if viewModel.crossfaderPosition > 0.55 {
            return "DECK B \(Int((viewModel.crossfaderPosition - 0.5) * 200))% →"
        } else {
            return "⚖️ CENTER"
        }
    }
}

// MARK: - EQ Knob View

struct EQKnobView: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

            ZStack {
                // Background circle
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)

                // Value indicator arc
                Circle()
                    .trim(from: 0, to: normalizedValue)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(-90))

                // Center knob
                Circle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 35, height: 35)

                // Value text
                Text(formattedValue)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        // Calculate angle from center
                        let center = CGPoint(x: 25, y: 25)
                        let angle = atan2(gesture.location.y - center.y, gesture.location.x - center.x)

                        // Convert to 0-1 range (0 = -12dB, 0.5 = 0dB, 1 = +12dB)
                        var normalized = (angle + .pi / 2) / (2 * .pi)
                        if normalized < 0 { normalized += 1 }

                        value = min(max(normalized, 0), 1)
                    }
            )

            // Reset button
            Button("Reset") {
                value = 0.5 // 0dB
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    private var normalizedValue: Double {
        value
    }

    private var formattedValue: String {
        let db = (value - 0.5) * 24.0 // -12 to +12 dB
        return String(format: "%+.0fdB", db)
    }
}

// MARK: - Vertical Fader View

struct VerticalFaderView: View {
    @Binding var value: Double
    let color: Color
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 30)

                // Active fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.6))
                    .frame(width: 30, height: value * geometry.size.height)

                // Fader handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(isDragging ? Color.white : Color.gray)
                    .frame(width: 38, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height - (value * geometry.size.height)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDragging = true
                                let newValue = 1.0 - (gesture.location.y / geometry.size.height)
                                value = min(max(newValue, 0), 1)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
        }
    }
}

// MARK: - Crossfader View

struct CrossfaderView: View {
    @Binding var position: Double
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 30)

                // Center indicator
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 2, height: 40)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                // Active side indicator
                if position < 0.5 {
                    // Deck A (left) active
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: (0.5 - position) * geometry.size.width * 2, height: 30)
                        .position(x: ((0.5 - position) * geometry.size.width), y: geometry.size.height / 2)
                } else if position > 0.5 {
                    // Deck B (right) active
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.3))
                        .frame(width: (position - 0.5) * geometry.size.width * 2, height: 30)
                        .offset(x: geometry.size.width / 2)
                        .position(x: geometry.size.width / 2 + (position - 0.5) * geometry.size.width, y: geometry.size.height / 2)
                }

                // Fader handle
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDragging ? Color.white : Color.gray)
                    .frame(width: 40, height: 50)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .position(
                        x: position * geometry.size.width,
                        y: geometry.size.height / 2
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDragging = true
                                let newPosition = gesture.location.x / geometry.size.width
                                position = min(max(newPosition, 0), 1)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
        }
    }
}

#Preview {
    MixerView(viewModel: MixerViewModel(audioEngine: AudioEngine()))
        .frame(width: 500, height: 500)
        .padding()
}
