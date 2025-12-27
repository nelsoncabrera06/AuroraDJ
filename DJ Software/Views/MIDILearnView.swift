//
//  MIDILearnView.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import SwiftUI
import Combine

struct MIDILearnView: View {
    @ObservedObject var midiViewModel: MIDIViewModel
    @State private var learningControl: String?
    @State private var capturedMappings: [String: String] = [:]
    @State private var lastMIDIEvent: String = "Waiting for MIDI..."

    let controlsToMap = [
        "Deck A - Play",
        "Deck A - Cue",
        "Deck A - Sync",
        "Deck A - Hot Cue 1",
        "Deck A - Hot Cue 2",
        "Deck A - Hot Cue 3",
        "Deck A - Hot Cue 4",
        "Deck B - Play",
        "Deck B - Cue",
        "Deck B - Sync",
        "Deck B - Hot Cue 1",
        "Deck B - Hot Cue 2",
        "Deck B - Hot Cue 3",
        "Deck B - Hot Cue 4"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("MIDI Learn - Mapeo de Controles")
                .font(.title)
                .bold()

            Text("Haz click en un control y presiona el botón correspondiente en tu controladora")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Last MIDI Event
            HStack {
                Text("Último evento MIDI:")
                    .font(.caption)
                Text(lastMIDIEvent)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }

            Divider()

            // Controls list
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(controlsToMap, id: \.self) { control in
                        HStack {
                            Text(control)
                                .font(.body)

                            Spacer()

                            if let mapping = capturedMappings[control] {
                                Text(mapping)
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(4)
                            }

                            Button(learningControl == control ? "Esperando..." : "Learn") {
                                startLearning(control)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(learningControl == control ? .orange : .blue)
                            .disabled(learningControl != nil && learningControl != control)
                        }
                        .padding(.horizontal)
                    }
                }
            }

            Divider()

            HStack(spacing: 20) {
                Button("Guardar Mapeo") {
                    saveMappings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(capturedMappings.isEmpty)

                Button("Cancelar") {
                    learningControl = nil
                }
                .buttonStyle(.bordered)
                .disabled(learningControl == nil)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            setupMIDIListener()
        }
    }

    private func setupMIDIListener() {
        midiViewModel.midiService.midiEventsPublisher
            .receive(on: DispatchQueue.main)
            .sink { event in
                handleMIDIEvent(event)
            }
            .store(in: &midiViewModel.cancellables)
    }

    private func handleMIDIEvent(_ event: MIDIEvent) {
        switch event {
        case .noteOn(let channel, let note, let velocity):
            lastMIDIEvent = "Note On: CH\(channel) Note:\(note) Vel:\(velocity)"

            if let control = learningControl {
                capturedMappings[control] = "Note \(note)"
                print("✅ Mapped \(control) → Note \(note)")
                learningControl = nil
            }

        case .noteOff(let channel, let note):
            lastMIDIEvent = "Note Off: CH\(channel) Note:\(note)"

        case .controlChange(let channel, let controller, let value):
            lastMIDIEvent = "CC: CH\(channel) Controller:\(controller) Value:\(value)"

            if let control = learningControl {
                capturedMappings[control] = "CC \(controller)"
                print("✅ Mapped \(control) → CC \(controller)")
                learningControl = nil
            }

        case .pitchBend(let channel, let value):
            lastMIDIEvent = "Pitch Bend: CH\(channel) Value:\(value)"
        }
    }

    private func startLearning(_ control: String) {
        learningControl = control
        print("🎹 Learning mode activated for: \(control)")
    }

    private func saveMappings() {
        // Save to UserDefaults
        let mappingsDict = Dictionary(uniqueKeysWithValues: capturedMappings.map { ($0.key, $0.value) })
        UserDefaults.standard.set(mappingsDict, forKey: "MIDIControlMappings")

        print("💾 Saved MIDI mappings:")
        for (control, mapping) in capturedMappings {
            print("  \(control) → \(mapping)")
        }

        // TODO: Reload mappings in MIDIMapping
    }
}


#Preview {
    MIDILearnView(midiViewModel: MIDIViewModel(midiService: MIDIService()))
}
