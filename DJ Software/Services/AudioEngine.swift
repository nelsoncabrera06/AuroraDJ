//
//  AudioEngine.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import AVFoundation
import Combine
import CoreVideo

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

    // PRE-CARGA RAM: Buffers completos en memoria para seeks instantáneos
    // Cada track stereo 44.1kHz de 5 min ≈ 106 MB RAM
    private var preloadedBufferA: AVAudioPCMBuffer?
    private var preloadedBufferB: AVAudioPCMBuffer?

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

    // CVDisplayLink for synchronized position updates (replaces Timer)
    private var displayLink: CVDisplayLink?
    private var displayLinkRunning = false

    // Frame skipping for waveform updates (reduces CPU load)
    // OPTIMIZADO v3: Subido a 30Hz - con imagen pre-renderizada es muy liviano
    private var frameCounter: UInt64 = 0
    private let waveformUpdateFrequency: UInt64 = 2 // Update waveforms every 2 frames (~30Hz)

    // Callbacks para actualizar UI
    var onPositionUpdate: ((DeckID, TimeInterval) -> Void)?

    // CPU Optimization: Cache last position updates for throttling
    // OPTIMIZADO v3: Subido a 30 FPS (33ms) - con imagen pre-renderizada es liviano
    private var lastUpdateTimeA: TimeInterval = 0
    private var lastUpdateTimeB: TimeInterval = 0
    private let updateThreshold: TimeInterval = 0.033 // 33ms = 30 FPS

    // CPU Optimization: Cache sample rates
    private var sampleRateA: Double = 44100
    private var sampleRateB: Double = 44100

    // MARK: - Initialization

    init() {
        setupAudioEngine()
        startEngine()
    }

    deinit {
        stop(deck: .deckA)
        stop(deck: .deckB)

        // Stop and release CVDisplayLink
        if let link = displayLink {
            if displayLinkRunning {
                CVDisplayLinkStop(link)
            }
        }
        displayLink = nil

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

        // Setup CVDisplayLink for synchronized position updates
        // DisplayLink only runs when decks are playing (smart pausing)
        setupDisplayLink()
    }

    // MARK: - CVDisplayLink Setup

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)

        guard status == kCVReturnSuccess, let displayLink = link else {
            print("❌ Failed to create CVDisplayLink")
            return
        }

        self.displayLink = displayLink

        // Set output callback
        let callback: CVDisplayLinkOutputCallback = { displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext in
            guard let context = displayLinkContext else { return kCVReturnError }
            let engine = Unmanaged<AudioEngine>.fromOpaque(context).takeUnretainedValue()
            engine.handleDisplayLinkCallback()
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
        print("✅ CVDisplayLink setup complete (smart pausing enabled)")
    }

    /// Handles each display refresh - runs on high-priority display thread
    private func handleDisplayLinkCallback() {
        frameCounter += 1

        // Always calculate positions internally at 60Hz for precision
        let positionA = calculateCurrentPosition(deck: .deckA)
        let positionB = calculateCurrentPosition(deck: .deckB)

        // Only notify UI at reduced rate for waveforms (~30Hz) to reduce CPU
        if frameCounter % waveformUpdateFrequency == 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.notifyPositionUpdates(positionA: positionA, positionB: positionB)
            }
        }
    }

    /// Calculate current position without updating UI (internal precision tracking)
    private func calculateCurrentPosition(deck: DeckID) -> TimeInterval? {
        switch deck {
        case .deckA:
            guard isPlayingA, let lastTime = lastRenderTimeA, let nodeTime = playerA.lastRenderTime else {
                return nil
            }
            let deltaFrames = nodeTime.sampleTime - lastTime.sampleTime
            framePositionA += deltaFrames
            lastRenderTimeA = nodeTime

            // Check if reached end
            if let file = audioFileA, framePositionA >= file.length {
                DispatchQueue.main.async { [weak self] in
                    self?.stop(deck: .deckA)
                }
            }
            return TimeInterval(framePositionA) / sampleRateA

        case .deckB:
            guard isPlayingB, let lastTime = lastRenderTimeB, let nodeTime = playerB.lastRenderTime else {
                return nil
            }
            let deltaFrames = nodeTime.sampleTime - lastTime.sampleTime
            framePositionB += deltaFrames
            lastRenderTimeB = nodeTime

            // Check if reached end
            if let file = audioFileB, framePositionB >= file.length {
                DispatchQueue.main.async { [weak self] in
                    self?.stop(deck: .deckB)
                }
            }
            return TimeInterval(framePositionB) / sampleRateB
        }
    }

    /// Notify UI of position changes (runs on main thread)
    private func notifyPositionUpdates(positionA: TimeInterval?, positionB: TimeInterval?) {
        // Deck A - throttled updates
        if let currentTime = positionA {
            let timeDelta = abs(currentTime - lastUpdateTimeA)
            if timeDelta >= updateThreshold {
                onPositionUpdate?(.deckA, currentTime)
                lastUpdateTimeA = currentTime
            }
        }

        // Deck B - throttled updates
        if let currentTime = positionB {
            let timeDelta = abs(currentTime - lastUpdateTimeB)
            if timeDelta >= updateThreshold {
                onPositionUpdate?(.deckB, currentTime)
                lastUpdateTimeB = currentTime
            }
        }
    }

    /// Start/stop display link based on playback state (smart pausing)
    private func updateDisplayLinkState() {
        let anyPlaying = isPlayingA || isPlayingB

        if anyPlaying && !displayLinkRunning {
            if let link = displayLink {
                CVDisplayLinkStart(link)
                displayLinkRunning = true
            }
        } else if !anyPlaying && displayLinkRunning {
            if let link = displayLink {
                CVDisplayLinkStop(link)
                displayLinkRunning = false
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

            // PRE-CARGA RAM: Leer todo el archivo a memoria para seeks instantáneos
            let preloadedBuffer = preloadEntireFile(audioFile)
            let memoryMB = preloadedBuffer.map { Double($0.frameLength) * Double($0.format.channelCount) * 4 / 1_000_000 } ?? 0

            switch deck {
            case .deckA:
                // Release previous security-scoped resource if any
                if let oldURL = securityScopedURLA {
                    oldURL.stopAccessingSecurityScopedResource()
                }

                audioFileA = audioFile
                preloadedBufferA = preloadedBuffer
                currentTrackA = track
                framePositionA = 0
                sampleRateA = audioFile.processingFormat.sampleRate // Cache sample rate
                securityScopedURLA = accessing ? url : nil
                print("✅ Track loaded in Deck A: \(url.lastPathComponent) (\(String(format: "%.1f", memoryMB)) MB en RAM)")

            case .deckB:
                // Release previous security-scoped resource if any
                if let oldURL = securityScopedURLB {
                    oldURL.stopAccessingSecurityScopedResource()
                }

                audioFileB = audioFile
                preloadedBufferB = preloadedBuffer
                currentTrackB = track
                framePositionB = 0
                sampleRateB = audioFile.processingFormat.sampleRate // Cache sample rate
                securityScopedURLB = accessing ? url : nil
                print("✅ Track loaded in Deck B: \(url.lastPathComponent) (\(String(format: "%.1f", memoryMB)) MB en RAM)")
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
            guard audioFileA != nil else {
                print("⚠️ No track loaded in Deck A")
                return
            }

            if !isPlayingA {
                scheduleFile(deck: .deckA, player: playerA, framePosition: framePositionA)
                playerA.play()
                isPlayingA = true
                lastRenderTimeA = playerA.lastRenderTime
                print("▶️ Deck A playing from position \(framePositionA)")
            }

        case .deckB:
            guard audioFileB != nil else {
                print("⚠️ No track loaded in Deck B")
                return
            }

            if !isPlayingB {
                scheduleFile(deck: .deckB, player: playerB, framePosition: framePositionB)
                playerB.play()
                isPlayingB = true
                lastRenderTimeB = playerB.lastRenderTime
                print("▶️ Deck B playing from position \(framePositionB)")
            }
        }

        // Start display link if not running (smart pausing)
        updateDisplayLinkState()
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

        // Stop display link if no decks playing (smart pausing)
        updateDisplayLinkState()
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

        // Stop display link if no decks playing (smart pausing)
        updateDisplayLinkState()
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

        // OPTIMIZADO v2: Bypass EQ si todas las bandas están en 0 (ahorra CPU)
        updateEQBypass(deck: deck)
    }

    /// Bypass EQ cuando todas las bandas están en 0 para ahorrar CPU
    private func updateEQBypass(deck: DeckID) {
        let eq = deck == .deckA ? eqA : eqB
        let allZero = eq.bands.allSatisfy { abs($0.gain) < 0.1 }
        eq.bypass = allZero
    }

    // MARK: - Private: Audio Scheduling

    /// Pre-carga el archivo de audio completo en RAM para seeks instantáneos
    private func preloadEntireFile(_ file: AVAudioFile) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(file.length)

        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            print("❌ Failed to create preload buffer")
            return nil
        }

        file.framePosition = 0

        do {
            try file.read(into: buffer)
            print("✅ Pre-loaded \(frameCount) frames into RAM")
            return buffer
        } catch {
            print("❌ Error pre-loading audio file: \(error.localizedDescription)")
            return nil
        }
    }

    private func scheduleFile(deck: DeckID, player: AVAudioPlayerNode, framePosition: AVAudioFramePosition) {
        // Obtener archivo y buffer pre-cargado del deck
        let file: AVAudioFile?
        let preloadedBuffer: AVAudioPCMBuffer?

        switch deck {
        case .deckA:
            file = audioFileA
            preloadedBuffer = preloadedBufferA
        case .deckB:
            file = audioFileB
            preloadedBuffer = preloadedBufferB
        }

        guard let audioFile = file else {
            print("❌ No audio file for deck \(deck.rawValue)")
            return
        }

        // Crear sub-buffer desde la posición actual
        guard let buffer = createBufferFromPreloaded(preloadedBuffer, file: audioFile, startingFrame: framePosition) else {
            print("❌ Failed to create audio buffer")
            return
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Crea un buffer desde el buffer pre-cargado en RAM (seek instantáneo, sin I/O de disco)
    private func createBufferFromPreloaded(_ preloaded: AVAudioPCMBuffer?, file: AVAudioFile, startingFrame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        // Si tenemos buffer pre-cargado, extraer sub-buffer (instantáneo)
        if let source = preloaded {
            let remainingFrames = AVAudioFrameCount(source.frameLength) - AVAudioFrameCount(startingFrame)

            guard remainingFrames > 0,
                  let subBuffer = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: remainingFrames) else {
                return nil
            }

            // Copiar datos desde el buffer pre-cargado (operación de memoria, muy rápida)
            let channelCount = Int(source.format.channelCount)
            for channel in 0..<channelCount {
                if let srcData = source.floatChannelData?[channel],
                   let dstData = subBuffer.floatChannelData?[channel] {
                    let srcOffset = srcData.advanced(by: Int(startingFrame))
                    dstData.update(from: srcOffset, count: Int(remainingFrames))
                }
            }
            subBuffer.frameLength = remainingFrames

            return subBuffer
        }

        // Fallback: leer desde disco (más lento)
        return createBufferFromFile(file, startingFrame: startingFrame)
    }

    /// Fallback: crear buffer leyendo desde disco
    private func createBufferFromFile(_ file: AVAudioFile, startingFrame: AVAudioFramePosition) -> AVAudioPCMBuffer? {
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

    /// Calcula el tiempo preciso actual basado en AVAudioTime (más preciso que getCurrentTime)
    private func getPreciseCurrentTime(deck: DeckID) -> TimeInterval? {
        let player: AVAudioPlayerNode
        let audioFile: AVAudioFile?
        let framePosition: AVAudioFramePosition

        switch deck {
        case .deckA:
            player = playerA
            audioFile = audioFileA
            framePosition = framePositionA
        case .deckB:
            player = playerB
            audioFile = audioFileB
            framePosition = framePositionB
        }

        guard let file = audioFile else { return nil }

        let sampleRate = file.processingFormat.sampleRate
        return TimeInterval(framePosition) / sampleRate
    }

    /// Calcula la posición fraccionaria dentro del beat actual (0.0 a 1.0)
    /// Usa tiempo preciso basado en framePosition en vez de updates periódicos
    func getBeatPhase(deck: DeckID) -> Double? {
        guard let bpm = getCurrentBPM(deck: deck),
              let currentTime = getPreciseCurrentTime(deck: deck) else {
            return nil
        }

        // Calcular número de beats transcurridos
        let beatsElapsed = currentTime * (bpm / 60.0)

        // Retornar posición fraccionaria dentro del beat actual (0.0 a 1.0)
        return beatsElapsed.truncatingRemainder(dividingBy: 1.0)
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
    /// Implementa compensación de latencia predictiva para sincronización precisa
    private func alignBeats(followerDeck: DeckID, leaderDeck: DeckID) {
        guard let currentLeaderPhase = getBeatPhase(deck: leaderDeck),
              let followerPhase = getBeatPhase(deck: followerDeck),
              let leaderBPM = getCurrentBPM(deck: leaderDeck),
              let followerBPM = getCurrentBPM(deck: followerDeck),
              let followerCurrentTime = getPreciseCurrentTime(deck: followerDeck) else {
            print("  ⚠️ Cannot align beats: missing beat phase data")
            return
        }

        // COMPENSACIÓN DE LATENCIA PREDICTIVA
        // Estimar latencia del seek (stop + createBuffer + scheduleBuffer + start)
        let estimatedSeekLatency = 0.100 // 100ms aproximado

        // Predecir dónde estará el leader cuando el seek complete
        let leaderBeatsPerSecond = leaderBPM / 60.0
        let phaseDeltaDuringLatency = (estimatedSeekLatency * leaderBeatsPerSecond).truncatingRemainder(dividingBy: 1.0)
        let predictedLeaderPhase = (currentLeaderPhase + phaseDeltaDuringLatency).truncatingRemainder(dividingBy: 1.0)

        // Calcular diferencia de fase usando la fase PREDICHA del leader
        var phaseDiff = predictedLeaderPhase - followerPhase

        // Normalizar a [-0.5, 0.5] (buscar el ajuste más corto)
        if phaseDiff > 0.5 {
            phaseDiff -= 1.0
        } else if phaseDiff < -0.5 {
            phaseDiff += 1.0
        }

        // Convertir diferencia de fase a tiempo (segundos)
        let beatDuration = 60.0 / followerBPM
        let timeAdjustment = phaseDiff * beatDuration

        // Seek a nueva posición
        let newTime = followerCurrentTime + timeAdjustment

        if newTime >= 0 {
            let startTime = CACurrentMediaTime()
            seek(to: newTime, deck: followerDeck)
            let actualLatency = CACurrentMediaTime() - startTime

            print("  🎵 Beat alignment with latency compensation:")
            print("    Leader phase NOW: \(String(format: "%.3f", currentLeaderPhase))")
            print("    Leader phase PREDICTED (+\(Int(estimatedSeekLatency * 1000))ms): \(String(format: "%.3f", predictedLeaderPhase))")
            print("    Follower phase: \(String(format: "%.3f", followerPhase))")
            print("    Phase diff (compensated): \(String(format: "%.3f", phaseDiff)) beats")
            print("    Time adjustment: \(String(format: "%.3f", timeAdjustment))s")
            print("    Actual seek latency: \(String(format: "%.0f", actualLatency * 1000))ms")
        } else {
            print("  ⚠️ Cannot seek to negative time, skipping beat alignment")
        }
    }
}

// MARK: - Supporting Types

enum EQBand {
    case high
    case mid
    case low
}
