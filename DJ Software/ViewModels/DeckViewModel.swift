//
//  DeckViewModel.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import Combine

/// ViewModel que gestiona el estado y lógica de un deck
@MainActor
class DeckViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var state = DeckState()

    // MARK: - Properties

    let deckID: DeckID
    private let audioEngine: AudioEngine
    private var cancellables = Set<AnyCancellable>()

    // CPU Optimization: Additional throttling for position updates
    // Only update state if visual change would be noticeable
    private var lastUIUpdateTime: TimeInterval = 0
    private let uiUpdateThreshold: TimeInterval = 0.05 // 50ms = 20 FPS max for UI updates

    // MARK: - Initialization

    init(deckID: DeckID, audioEngine: AudioEngine) {
        self.deckID = deckID
        self.audioEngine = audioEngine
    }

    // MARK: - Track Loading

    /// Carga una pista desde una URL
    func loadTrack(url: URL) async {
        print("🔄 DeckViewModel: Starting to load track from \(url.path)")

        do {
            print("🔄 DeckViewModel: Creating Track object...")
            let track = try await Track.from(url: url)
            print("✅ DeckViewModel: Track object created - \(track.displayName)")

            // Update state on MainActor
            await MainActor.run {
                state.currentTrack = track
                print("🔄 State updated with track: \(track.displayName)")
            }

            // Cargar en el audio engine
            print("🔄 DeckViewModel: Loading into AudioEngine...")
            let success = audioEngine.loadTrack(url: url, deck: deckID, track: track)

            if success {
                await MainActor.run {
                    // Reset state
                    state.isPlaying = false
                    state.currentTime = 0
                    state.tempo = 1.0
                    state.pitch = 0.0
                    state.cuePoint = nil
                    state.hotCuePoints = [:]
                    state.loopStart = nil
                    state.loopEnd = nil
                    state.isLooping = false
                }

                print("✅ Track loaded successfully in Deck \(deckID.rawValue): \(track.displayName)")
            } else {
                print("❌ AudioEngine failed to load track in Deck \(deckID.rawValue)")
            }
        } catch {
            print("❌ Error loading track: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
        }
    }

    /// Carga una pista directamente (ya creada)
    func loadTrack(_ track: Track) {
        state.currentTrack = track

        let success = audioEngine.loadTrack(url: track.url, deck: deckID, track: track)

        if success {
            // Reset state
            state.isPlaying = false
            state.currentTime = 0
            state.tempo = 1.0
            state.pitch = 0.0
            state.cuePoint = nil
            state.hotCuePoints = [:]
            state.loopStart = nil
            state.loopEnd = nil
            state.isLooping = false

            print("✅ Track loaded in Deck \(deckID.rawValue): \(track.displayName)")
        }
    }

    // MARK: - Playback Control

    /// Toggle play/pause
    func togglePlayPause() {
        guard state.hasTrack else {
            print("⚠️ No track loaded in Deck \(deckID.rawValue)")
            return
        }

        audioEngine.togglePlayPause(deck: deckID)
        state.isPlaying = audioEngine.isPlaying(deck: deckID)
    }

    /// Play
    func play() {
        guard state.hasTrack else { return }
        audioEngine.play(deck: deckID)
        state.isPlaying = true
    }

    /// Pause
    func pause() {
        audioEngine.pause(deck: deckID)
        state.isPlaying = false
    }

    /// Stop y resetear posición
    func stop() {
        audioEngine.stop(deck: deckID)
        state.isPlaying = false
        state.currentTime = 0
    }

    // MARK: - Cue Points

    /// Establece el cue point en la posición actual
    func setCuePoint() {
        state.cuePoint = state.currentTime
        print("🎯 Cue point set at \(state.currentTime)s in Deck \(deckID.rawValue)")
    }

    /// Salta al cue point
    func jumpToCue() {
        guard let cuePoint = state.cuePoint else {
            print("⚠️ No cue point set in Deck \(deckID.rawValue)")
            return
        }

        seek(to: cuePoint)
        pause()
    }

    /// Establece un hot cue en un slot (0-3)
    func setHotCue(slot: Int) {
        guard (0...3).contains(slot) else { return }
        state.hotCuePoints[slot] = state.currentTime
        print("🔥 Hot cue \(slot) set at \(state.currentTime)s in Deck \(deckID.rawValue)")
    }

    /// Salta a un hot cue
    func triggerHotCue(slot: Int) {
        guard let time = state.hotCuePoints[slot] else {
            print("⚠️ Hot cue \(slot) not set in Deck \(deckID.rawValue)")
            return
        }

        seek(to: time)
        if !state.isPlaying {
            play()
        }
    }

    // MARK: - Seeking

    /// Salta a una posición específica
    func seek(to time: TimeInterval) {
        guard state.hasTrack else { return }

        let clampedTime = min(max(time, 0), state.duration)
        audioEngine.seek(to: clampedTime, deck: deckID)
        state.currentTime = clampedTime
    }

    /// Actualiza la posición actual (llamado por AudioEngine)
    /// OPTIMIZADO: Solo actualiza el state si el cambio es visualmente significativo
    func updatePosition(_ time: TimeInterval) {
        // CPU Optimization: Skip update if change is too small to be noticeable
        let timeDelta = abs(time - lastUIUpdateTime)
        guard timeDelta >= uiUpdateThreshold else { return }

        state.currentTime = time
        lastUIUpdateTime = time
    }

    // MARK: - Tempo & Pitch

    /// Ajusta el tempo (0.5 a 2.0)
    func setTempo(_ tempo: Double) {
        let clampedTempo = min(max(tempo, 0.5), 2.0)
        state.tempo = clampedTempo
        audioEngine.setTempo(clampedTempo, deck: deckID)
    }

    /// Ajusta el pitch en semitonos (-12 a +12)
    func setPitch(_ semitones: Double) {
        let clampedPitch = min(max(semitones, -12), 12)
        state.pitch = clampedPitch
        audioEngine.setPitch(clampedPitch, deck: deckID)
    }

    // MARK: - Volume

    /// Ajusta el volumen (0.0 a 1.0)
    func setVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0.0), 1.0)
        state.volume = clampedVolume
        audioEngine.setVolume(clampedVolume, deck: deckID)
    }

    // MARK: - Loop

    /// Establece el inicio del loop
    func setLoopStart() {
        state.loopStart = state.currentTime
        print("🔁 Loop start set at \(state.currentTime)s in Deck \(deckID.rawValue)")
    }

    /// Establece el fin del loop
    func setLoopEnd() {
        state.loopEnd = state.currentTime
        print("🔁 Loop end set at \(state.currentTime)s in Deck \(deckID.rawValue)")
    }

    /// Toggle loop on/off
    func toggleLoop() {
        guard state.loopStart != nil, state.loopEnd != nil else {
            print("⚠️ Loop points not set in Deck \(deckID.rawValue)")
            return
        }

        state.isLooping.toggle()
        print("🔁 Loop \(state.isLooping ? "enabled" : "disabled") in Deck \(deckID.rawValue)")
    }

    // MARK: - Sync

    /// Sincroniza este deck con el deck opuesto (matchea BPM y alinea beats)
    func syncWithOppositeDeck() {
        let oppositeDeck: DeckID = (self.deckID == .deckA) ? .deckB : .deckA
        audioEngine.sync(followerDeck: self.deckID, leaderDeck: oppositeDeck)

        // Actualizar el tempo en el state después de sincronizar
        if let originalBPM = state.originalBPM,
           let leaderBPM = audioEngine.getCurrentBPM(deck: oppositeDeck) {
            let newTempo = leaderBPM / originalBPM
            state.tempo = min(max(newTempo, 0.5), 2.0)
        }
    }
}
