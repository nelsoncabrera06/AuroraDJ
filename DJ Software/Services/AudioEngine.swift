//
//  AudioEngine.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import AVFoundation
import Combine

/// Motor de audio central que maneja la reproducción de dos decks independientes
class AudioEngine: ObservableObject {
    // MARK: - Properties

    private let engine = AVAudioEngine()

    // Deck A components
    private let playerA = AVAudioPlayerNode()
    private let timePitchA = AVAudioUnitTimePitch()
    private let eqA = AVAudioUnitEQ(numberOfBands: 3)

    // Deck B components
    private let playerB = AVAudioPlayerNode()
    private let timePitchB = AVAudioUnitTimePitch()
    private let eqB = AVAudioUnitEQ(numberOfBands: 3)

    // Mixer
    private let mixer = AVAudioMixerNode()

    // Audio files
    private var audioFileA: AVAudioFile?
    private var audioFileB: AVAudioFile?

    // Current tracks (for BPM access)
    private var currentTrackA: Track?
    private var currentTrackB: Track?

    // Security-scoped URLs
    private var securityScopedURLA: URL?
    private var securityScopedURLB: URL?

    // Playback state
    private var isPlayingA = false
    private var isPlayingB = false

    // Tempo tracking
    private var tempoA: Double = 1.0
    private var tempoB: Double = 1.0

    // Position tracking
    private var framePositionA: AVAudioFramePosition = 0
    private var framePositionB: AVAudioFramePosition = 0

    private var lastRenderTimeA: AVAudioTime?
    private var lastRenderTimeB: AVAudioTime?

    // Timers for position updates
    private var updateTimer: Timer?

    // Callbacks para actualizar UI
    var onPositionUpdate: ((DeckID, TimeInterval) -> Void)?

    // MARK: - Initialization

    init() {
        setupAudioEngine()
        startEngine()
    }

    deinit {
        stop(deck: .deckA)
        stop(deck: .deckB)
        updateTimer?.invalidate()

        // Release security-scoped resources
        if let url = securityScopedURLA {
            url.stopAccessingSecurityScopedResource()
        }
        if let url = securityScopedURLB {
            url.stopAccessingSecurityScopedResource()
        }

        engine.stop()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(playerA)
        engine.attach(timePitchA)
        engine.attach(eqA)

        engine.attach(playerB)
        engine.attach(timePitchB)
        engine.attach(eqB)

        engine.attach(mixer)

        // Setup format (44.1kHz, stereo)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

        // Connect Deck A: Player → TimePitch → EQ → Mixer
        engine.connect(playerA, to: timePitchA, format: format)
        engine.connect(timePitchA, to: eqA, format: format)
        engine.connect(eqA, to: mixer, format: format)

        // Connect Deck B: Player → TimePitch → EQ → Mixer
        engine.connect(playerB, to: timePitchB, format: format)
        engine.connect(timePitchB, to: eqB, format: format)
        engine.connect(eqB, to: mixer, format: format)

        // Connect mixer to output
        engine.connect(mixer, to: engine.mainMixerNode, format: format)

        // Setup EQ bands (High, Mid, Low)
        setupEQ(eqA)
        setupEQ(eqB)

        // Start position update timer (30 FPS)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePositions()
            }
        }
    }

    private func setupEQ(_ eq: AVAudioUnitEQ) {
        guard eq.bands.count >= 3 else { return }

        // High: 12kHz
        eq.bands[0].filterType = .parametric
        eq.bands[0].frequency = 12000
        eq.bands[0].bandwidth = 1.0
        eq.bands[0].gain = 0
        eq.bands[0].bypass = false

        // Mid: 1kHz
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = 1000
        eq.bands[1].bandwidth = 1.0
        eq.bands[1].gain = 0
        eq.bands[1].bypass = false

        // Low: 100Hz
        eq.bands[2].filterType = .parametric
        eq.bands[2].frequency = 100
        eq.bands[2].bandwidth = 1.0
        eq.bands[2].gain = 0
        eq.bands[2].bypass = false
    }

    private func startEngine() {
        do {
            try engine.start()
            print("✅ Audio engine started successfully")
        } catch {
            print("❌ Error starting audio engine: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API: Load Track

    /// Carga una pista en el deck especificado
    func loadTrack(url: URL, deck: DeckID, track: Track? = nil) -> Bool {
        print("🔄 AudioEngine: Attempting to load \(url.lastPathComponent) into Deck \(deck.rawValue)")

        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        print("🔒 Security-scoped access: \(accessing)")

        do {
            let audioFile = try AVAudioFile(forReading: url)
            print("✅ AudioFile created successfully")

            switch deck {
            case .deckA:
                // Release previous security-scoped resource if any
                if let oldURL = securityScopedURLA {
                    oldURL.stopAccessingSecurityScopedResource()
                }

                audioFileA = audioFile
                currentTrackA = track
                framePositionA = 0
                securityScopedURLA = accessing ? url : nil
                print("✅ Track loaded in Deck A: \(url.lastPathComponent)")

            case .deckB:
                // Release previous security-scoped resource if any
                if let oldURL = securityScopedURLB {
                    oldURL.stopAccessingSecurityScopedResource()
                }

                audioFileB = audioFile
                currentTrackB = track
                framePositionB = 0
                securityScopedURLB = accessing ? url : nil
                print("✅ Track loaded in Deck B: \(url.lastPathComponent)")
            }

            return true
        } catch {
            print("❌ Error loading audio file for \(deck.rawValue): \(error.localizedDescription)")
            print("❌ Error details: \(error)")

            // If we started accessing but failed, stop
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }

            return false
        }
    }

    // MARK: - Public API: Playback Control

    /// Reproduce el deck especificado
    func play(deck: DeckID) {
        switch deck {
        case .deckA:
            guard let audioFile = audioFileA else {
                print("⚠️ No track loaded in Deck A")
                return
            }

            if !isPlayingA {
                scheduleFile(audioFile, player: playerA, framePosition: framePositionA)
                playerA.play()
                isPlayingA = true
                lastRenderTimeA = playerA.lastRenderTime
                print("▶️ Deck A playing from position \(framePositionA)")
            }

        case .deckB:
            guard let audioFile = audioFileB else {
                print("⚠️ No track loaded in Deck B")
                return
            }

            if !isPlayingB {
                scheduleFile(audioFile, player: playerB, framePosition: framePositionB)
                playerB.play()
                isPlayingB = true
                lastRenderTimeB = playerB.lastRenderTime
                print("▶️ Deck B playing from position \(framePositionB)")
            }
        }
    }

    /// Pausa el deck especificado
    func pause(deck: DeckID) {
        switch deck {
        case .deckA:
            if isPlayingA {
                playerA.pause()
                isPlayingA = false
                print("⏸️ Deck A paused")
            }

        case .deckB:
            if isPlayingB {
                playerB.pause()
                isPlayingB = false
                print("⏸️ Deck B paused")
            }
        }
    }

    /// Detiene el deck especificado y resetea la posición
    func stop(deck: DeckID) {
        switch deck {
        case .deckA:
            playerA.stop()
            isPlayingA = false
            framePositionA = 0
            print("⏹️ Deck A stopped")

        case .deckB:
            playerB.stop()
            isPlayingB = false
            framePositionB = 0
            print("⏹️ Deck B stopped")
        }
    }

    /// Toggle play/pause
    func togglePlayPause(deck: DeckID) {
        switch deck {
        case .deckA:
            if isPlayingA {
                pause(deck: .deckA)
            } else {
                play(deck: .deckA)
            }

        case .deckB:
            if isPlayingB {
                pause(deck: .deckB)
            } else {
                play(deck: .deckB)
            }
        }
    }

    /// Retorna si el deck está reproduciendo
    func isPlaying(deck: DeckID) -> Bool {
        switch deck {
        case .deckA:
            return isPlayingA
        case .deckB:
            return isPlayingB
        }
    }

    // MARK: - Public API: Seeking

    /// Salta a una posición específica en segundos
    func seek(to time: TimeInterval, deck: DeckID) {
        let wasPlaying: Bool
        let audioFile: AVAudioFile?
        let player: AVAudioPlayerNode

        switch deck {
        case .deckA:
            wasPlaying = isPlayingA
            audioFile = audioFileA
            player = playerA

        case .deckB:
            wasPlaying = isPlayingB
            audioFile = audioFileB
            player = playerB
        }

        guard let file = audioFile else { return }

        // Stop current playback
        player.stop()

        // Calculate frame position
        let sampleRate = file.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(time * sampleRate)

        switch deck {
        case .deckA:
            framePositionA = framePosition
            isPlayingA = false
        case .deckB:
            framePositionB = framePosition
            isPlayingB = false
        }

        // Resume if was playing
        if wasPlaying {
            play(deck: deck)
        }
    }

    /// Retorna la posición actual en segundos
    func getCurrentTime(deck: DeckID) -> TimeInterval {
        let framePosition: AVAudioFramePosition
        let audioFile: AVAudioFile?

        switch deck {
        case .deckA:
            framePosition = framePositionA
            audioFile = audioFileA
        case .deckB:
            framePosition = framePositionB
            audioFile = audioFileB
        }

        guard let file = audioFile else { return 0 }

        let sampleRate = file.processingFormat.sampleRate
        return TimeInterval(framePosition) / sampleRate
    }

    // MARK: - Public API: Tempo & Pitch

    /// Ajusta el tempo (velocidad) del deck (0.5 a 2.0, donde 1.0 es normal)
    func setTempo(_ tempo: Double, deck: DeckID) {
        let clampedTempo = min(max(tempo, 0.5), 2.0)

        switch deck {
        case .deckA:
            tempoA = clampedTempo
            timePitchA.rate = Float(clampedTempo)
        case .deckB:
            tempoB = clampedTempo
            timePitchB.rate = Float(clampedTempo)
        }
    }

    /// Ajusta el pitch en semitonos (-12 a +12)
    func setPitch(_ semitones: Double, deck: DeckID) {
        let clampedPitch = min(max(semitones, -12), 12)

        switch deck {
        case .deckA:
            timePitchA.pitch = Float(clampedPitch * 100) // cents
        case .deckB:
            timePitchB.pitch = Float(clampedPitch * 100)
        }
    }

    // MARK: - Public API: Volume

    /// Ajusta el volumen del deck (0.0 a 1.0)
    func setVolume(_ volume: Double, deck: DeckID) {
        let clampedVolume = Float(min(max(volume, 0.0), 1.0))

        switch deck {
        case .deckA:
            playerA.volume = clampedVolume
        case .deckB:
            playerB.volume = clampedVolume
        }
    }

    // MARK: - Public API: EQ

    /// Ajusta una banda de EQ (-12dB a +12dB)
    func setEQ(deck: DeckID, band: EQBand, gain: Double) {
        let clampedGain = Float(min(max(gain, -12), 12))
        let eq = deck == .deckA ? eqA : eqB

        let bandIndex: Int
        switch band {
        case .high:
            bandIndex = 0
        case .mid:
            bandIndex = 1
        case .low:
            bandIndex = 2
        }

        guard bandIndex < eq.bands.count else { return }
        eq.bands[bandIndex].gain = clampedGain
    }

    // MARK: - Private: Audio Scheduling

    private func scheduleFile(_ file: AVAudioFile, player: AVAudioPlayerNode, framePosition: AVAudioFramePosition) {
        guard let buffer = createBuffer(from: file, startingFrame: framePosition) else {
            print("❌ Failed to create audio buffer")
            return
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func createBuffer(from file: AVAudioFile, startingFrame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(file.length - startingFrame)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return nil
        }

        file.framePosition = startingFrame

        do {
            try file.read(into: buffer)
            return buffer
        } catch {
            print("❌ Error reading audio file: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private: Position Tracking

    private func updatePositions() {
        // Update Deck A
        if isPlayingA, let lastTime = lastRenderTimeA, let nodeTime = playerA.lastRenderTime {
            let sampleRate = audioFileA?.processingFormat.sampleRate ?? 44100
            let deltaFrames = nodeTime.sampleTime - lastTime.sampleTime
            framePositionA += deltaFrames
            lastRenderTimeA = nodeTime

            let currentTime = TimeInterval(framePositionA) / sampleRate
            onPositionUpdate?(.deckA, currentTime)

            // Check if reached end
            if let file = audioFileA, framePositionA >= file.length {
                stop(deck: .deckA)
            }
        }

        // Update Deck B
        if isPlayingB, let lastTime = lastRenderTimeB, let nodeTime = playerB.lastRenderTime {
            let sampleRate = audioFileB?.processingFormat.sampleRate ?? 44100
            let deltaFrames = nodeTime.sampleTime - lastTime.sampleTime
            framePositionB += deltaFrames
            lastRenderTimeB = nodeTime

            let currentTime = TimeInterval(framePositionB) / sampleRate
            onPositionUpdate?(.deckB, currentTime)

            // Check if reached end
            if let file = audioFileB, framePositionB >= file.length {
                stop(deck: .deckB)
            }
        }
    }

    // MARK: - Public API: Sync

    /// Obtiene el BPM actual de un deck (BPM original * tempo)
    func getCurrentBPM(deck: DeckID) -> Double? {
        switch deck {
        case .deckA:
            return currentTrackA?.bpm.map { $0 * tempoA }
        case .deckB:
            return currentTrackB?.bpm.map { $0 * tempoB }
        }
    }

    /// Obtiene el BPM original de un deck
    func getOriginalBPM(deck: DeckID) -> Double? {
        switch deck {
        case .deckA:
            return currentTrackA?.bpm
        case .deckB:
            return currentTrackB?.bpm
        }
    }

    /// Calcula la posición del beat actual dentro de un compás de 4 tiempos (0.0 a 4.0)
    func getBeatPosition(deck: DeckID) -> Double? {
        guard let bpm = getCurrentBPM(deck: deck) else {
            return nil
        }

        let currentTime = getCurrentTime(deck: deck)

        // Calcular número de beats transcurridos
        let beatsElapsed = currentTime * (bpm / 60.0)

        // Retornar posición dentro del compás (0.0 a 4.0)
        return beatsElapsed.truncatingRemainder(dividingBy: 4.0)
    }

    /// Sincroniza el deck follower con el deck leader (matchea BPM y alinea beats)
    func sync(followerDeck: DeckID, leaderDeck: DeckID) {
        // 1. Verificar que ambos decks tengan tracks con BPM
        guard let leaderBPM = getCurrentBPM(deck: leaderDeck),
              let followerOriginalBPM = getOriginalBPM(deck: followerDeck) else {
            print("⚠️ Cannot sync: missing BPM data")
            print("  Leader BPM: \(getCurrentBPM(deck: leaderDeck) as Double?)")
            print("  Follower Original BPM: \(getOriginalBPM(deck: followerDeck) as Double?)")
            return
        }

        // 2. Calcular nuevo tempo para matchear BPM
        let newTempo = leaderBPM / followerOriginalBPM
        let clampedTempo = min(max(newTempo, 0.5), 2.0)

        // 3. Aplicar nuevo tempo
        setTempo(clampedTempo, deck: followerDeck)

        print("🔄 Synced \(followerDeck): tempo=\(String(format: "%.3f", clampedTempo)), BPM=\(String(format: "%.1f", leaderBPM))")

        // 4. Si follower está en play, sincronizar beats
        let isFollowerPlaying = (followerDeck == .deckA) ? isPlayingA : isPlayingB
        if isFollowerPlaying {
            alignBeats(followerDeck: followerDeck, leaderDeck: leaderDeck)
        }
    }

    /// Alinea los beats del follower deck con el leader deck
    private func alignBeats(followerDeck: DeckID, leaderDeck: DeckID) {
        guard let leaderBeatPos = getBeatPosition(deck: leaderDeck),
              let followerBeatPos = getBeatPosition(deck: followerDeck),
              let followerBPM = getCurrentBPM(deck: followerDeck) else {
            print("  ⚠️ Cannot align beats: missing beat position data")
            return
        }

        let followerCurrentTime = getCurrentTime(deck: followerDeck)

        // Calcular diferencia de fase (en beats)
        var phaseDiff = leaderBeatPos - followerBeatPos

        // Normalizar a [-2, 2] (buscar el ajuste más corto dentro del compás)
        if phaseDiff > 2.0 { phaseDiff -= 4.0 }
        if phaseDiff < -2.0 { phaseDiff += 4.0 }

        // Convertir diferencia de beats a tiempo (segundos)
        let timeAdjustment = phaseDiff / (followerBPM / 60.0)

        // Seek a nueva posición
        let newTime = followerCurrentTime + timeAdjustment
        seek(to: max(0, newTime), deck: followerDeck)

        print("  🎵 Beat aligned: phase diff = \(String(format: "%.3f", phaseDiff)) beats, time adjust = \(String(format: "%.3f", timeAdjustment))s")
    }
}

// MARK: - Supporting Types

enum EQBand {
    case high
    case mid
    case low
}
