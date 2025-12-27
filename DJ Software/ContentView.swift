//
//  ContentView.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var deckAViewModel: DeckViewModel
    @StateObject private var deckBViewModel: DeckViewModel
    @StateObject private var mixerViewModel: MixerViewModel
    @StateObject private var midiService = MIDIService()
    @StateObject private var midiViewModel: MIDIViewModel

    init() {
        let engine = AudioEngine()
        _audioEngine = StateObject(wrappedValue: engine)
        _deckAViewModel = StateObject(wrappedValue: DeckViewModel(deckID: .deckA, audioEngine: engine))
        _deckBViewModel = StateObject(wrappedValue: DeckViewModel(deckID: .deckB, audioEngine: engine))
        _mixerViewModel = StateObject(wrappedValue: MixerViewModel(audioEngine: engine))

        let midi = MIDIService()
        _midiService = StateObject(wrappedValue: midi)
        _midiViewModel = StateObject(wrappedValue: MIDIViewModel(midiService: midi))
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("DJ Software - Test UI")
                .font(.title)
                .bold()

            // MIDI Status
            HStack {
                Text("MIDI:")
                    .font(.headline)

                if midiViewModel.isConnected {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    Text(midiViewModel.connectedDeviceName ?? "Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)

                    Text("Not connected")
                        .font(.caption)
                        .foregroundColor(.red)

                    Button("Connect Behringer") {
                        midiViewModel.connectToBehringer()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
            .padding(.horizontal)

            // Large Zoomed Waveforms (Full Width) - VirtualDJ Style
            VStack(spacing: 10) {
                // Deck A Waveform (Zoomed with scrolling)
                ZoomedWaveformView(
                    waveformData: deckAViewModel.state.waveformData,
                    currentTime: deckAViewModel.state.currentTime,
                    duration: deckAViewModel.state.duration,
                    color: .blue,
                    height: 100,
                    visibleWindowSeconds: 30.0  // ~10-12 bars at 120 BPM
                )

                // Deck B Waveform (Zoomed with scrolling)
                ZoomedWaveformView(
                    waveformData: deckBViewModel.state.waveformData,
                    currentTime: deckBViewModel.state.currentTime,
                    duration: deckBViewModel.state.duration,
                    color: .red,
                    height: 100,
                    visibleWindowSeconds: 30.0  // ~10-12 bars at 120 BPM
                )
            }
            .padding(.horizontal)

            HStack(spacing: 30) {
                // Deck A
                DeckTestView(viewModel: deckAViewModel)

                // Mixer in the middle
                MixerView(viewModel: mixerViewModel)
                    .frame(width: 350)

                // Deck B
                DeckTestView(viewModel: deckBViewModel)
            }
            .padding()
        }
        .frame(minWidth: 1200, minHeight: 600)
        .onAppear {
            // Setup position updates callback
            audioEngine.onPositionUpdate = { deckID, time in
                Task { @MainActor in
                    if deckID == .deckA {
                        deckAViewModel.updatePosition(time)
                    } else {
                        deckBViewModel.updatePosition(time)
                    }
                }
            }

            // Connect MIDI to decks and mixer
            Task { @MainActor in
                midiViewModel.connectDecks(deckA: deckAViewModel, deckB: deckBViewModel)
                midiViewModel.connectMixer(mixerViewModel)

                // Auto-connect to Behringer
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    midiViewModel.connectToBehringer()
                }
            }
        }
    }
}

struct DeckTestView: View {
    @ObservedObject var viewModel: DeckViewModel

    @State private var showFilePicker = false
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Deck \(viewModel.deckID.rawValue)")
                .font(.title2)
                .bold()

            // Track info with Drag & Drop zone
            Group {
                if let track = viewModel.state.currentTrack {
                    VStack(spacing: 5) {
                        Text(track.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        Text("\(track.formattedDuration) • \(track.fileFormat)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(viewModel.state.formattedBPM)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                            .monospacedDigit()
                    }
                    .frame(height: 80)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)

                        Text("Arrastra música aquí")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 80)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDragging ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isDragging ? Color.blue : Color.gray.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: isDragging ? [] : [5])
                    )
            )
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
                handleDrop(providers: providers)
                return true
            }

            // Waveform visualization (small reference)
            WaveformView(
                waveformData: viewModel.state.waveformData,
                currentTime: viewModel.state.currentTime,
                duration: viewModel.state.duration,
                color: viewModel.deckID == .deckA ? .blue : .red,
                height: 35
            )
            .padding(.horizontal)

            // Load button
            Button("Load Track") {
                showFilePicker = true
            }
            .buttonStyle(.borderedProminent)

            Divider()

            // Playback controls
            HStack(spacing: 20) {
                // CUE button (left of play)
                Button(action: {
                    viewModel.jumpToCue()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 30))
                        Text("CUE")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(viewModel.state.cuePoint != nil ? .orange : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.state.hasTrack)

                // PLAY/PAUSE button (center)
                Button(action: {
                    viewModel.togglePlayPause()
                }) {
                    Image(systemName: viewModel.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.state.hasTrack)

                // SYNC button (right of play)
                Button(action: {
                    viewModel.syncWithOppositeDeck()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 30))
                        Text("SYNC")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.state.hasTrack)

                Button(action: {
                    viewModel.stop()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.state.hasTrack)
            }

            // Time display
            VStack(spacing: 5) {
                Text(viewModel.state.formattedCurrentTime)
                    .font(.title3)
                    .monospacedDigit()

                ProgressView(value: viewModel.state.progress)
                    .frame(width: 300)

                Text(viewModel.state.formattedTimeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Divider()

            // Tempo control
            VStack(spacing: 5) {
                Text("Tempo: \(viewModel.state.tempoPercentage)")
                    .font(.caption)
                    .monospacedDigit()

                Slider(value: Binding(
                    get: { viewModel.state.tempo },
                    set: { viewModel.setTempo($0) }
                ), in: 0.5...2.0)
                .frame(width: 250)

                HStack {
                    Text("50%")
                        .font(.caption2)
                    Spacer()
                    Button("Reset") {
                        viewModel.setTempo(1.0)
                    }
                    .font(.caption2)
                    Spacer()
                    Text("200%")
                        .font(.caption2)
                }
                .frame(width: 250)
            }

            Divider()

            // Cue points
            HStack(spacing: 10) {
                Button("Set Cue") {
                    viewModel.setCuePoint()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.state.hasTrack)

                Button("Jump to Cue") {
                    viewModel.jumpToCue()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.state.cuePoint == nil)
            }
        }
        .frame(width: 400)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                UTType.audio,
                UTType(filenameExtension: "mp3")!,
                UTType(filenameExtension: "m4a")!,
                UTType(filenameExtension: "wav")!
            ],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    print("📁 File selected: \(url.path)")

                    Task {
                        await viewModel.loadTrack(url: url)
                    }
                }
            case .failure(let error):
                print("❌ File picker error: \(error)")
            }
        }
    }

    // MARK: - Drag & Drop Handler

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else {
            print("❌ No provider in drop")
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let error = error {
                print("❌ Error loading dropped item: \(error)")
                return
            }

            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                print("❌ Could not extract URL from dropped item")
                return
            }

            // Validate file extension
            let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff"]
            let fileExtension = url.pathExtension.lowercased()

            guard audioExtensions.contains(fileExtension) else {
                print("❌ Invalid file type: \(fileExtension)")
                return
            }

            print("🎵 Dropped audio file: \(url.lastPathComponent)")

            // Load track
            Task {
                await viewModel.loadTrack(url: url)
            }
        }
    }
}

#Preview {
    ContentView()
}
