//
//  Track.swift
//  DJ Software
//
//  Created by Nelson Cabrera on 25.12.2025.
//

import Foundation
import AVFoundation

/// Representa una pista de audio con su metadata
struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let fileFormat: String
    let bpm: Double?
    let waveformData: WaveformData?

    init(id: UUID = UUID(), url: URL, title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval, fileFormat: String, bpm: Double? = nil, waveformData: WaveformData? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileFormat = fileFormat
        self.bpm = bpm
        self.waveformData = waveformData
    }

    /// Crea un Track desde un archivo de audio, extrayendo metadata automáticamente
    static func from(url: URL) async throws -> Track {
        let asset = AVAsset(url: url)

        // Obtener duración
        let duration = try await asset.load(.duration).seconds

        // Obtener metadata
        let metadata = try await asset.load(.commonMetadata)

        var title = url.deletingPathExtension().lastPathComponent
        var artist: String?
        var album: String?

        for item in metadata {
            guard let key = item.commonKey?.rawValue,
                  let value = try? await item.load(.stringValue) else { continue }

            switch key {
            case "title":
                title = value
            case "artist":
                artist = value
            case "albumName":
                album = value
            default:
                break
            }
        }

        let fileFormat = url.pathExtension.uppercased()

        // Create track ID for waveform association
        let trackID = UUID()

        // Detect BPM and generate waveform in parallel
        async let bpm = BPMDetector.detectBPM(from: url)
        async let waveform = WaveformGenerator.generate(from: url, trackID: trackID)

        let (detectedBPM, generatedWaveform) = await (bpm, waveform)

        return Track(
            id: trackID,
            url: url,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileFormat: fileFormat,
            bpm: detectedBPM,
            waveformData: generatedWaveform
        )
    }

    /// Formatea la duración en formato MM:SS
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Retorna el nombre para mostrar (Artista - Título o solo Título)
    var displayName: String {
        if let artist = artist {
            return "\(artist) - \(title)"
        }
        return title
    }

    /// Retorna el BPM formateado
    var formattedBPM: String {
        if let bpm = bpm {
            return "\(Int(bpm)) BPM"
        }
        return "-- BPM"
    }
}
