import Foundation

// MARK: - Track

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var duration: TimeInterval

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    init(id: UUID = UUID(), name: String, path: String, duration: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.path = path
        self.duration = duration
    }

    init(url: URL, duration: TimeInterval = 0) {
        self.id = UUID()
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.duration = duration
    }
}

// MARK: - Playlist

struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var tracks: [Track]
    var color: RGBAColor
    var order: Int

    init(id: UUID = UUID(),
         name: String,
         tracks: [Track] = [],
         color: RGBAColor = RGBAColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1.0),
         order: Int = 0) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.color = color
        self.order = order
    }
}

// MARK: - Codable color
// Храним цвет как обычные числа. SwiftUI Color не является Codable,
// а NSColor(color) на некоторых версиях SDK ведёт себя нестабильно,
// поэтому весь выбор цвета идёт через RGB-компоненты.

struct RGBAColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    static let palette: [RGBAColor] = [
        RGBAColor(red: 0.20, green: 0.55, blue: 1.00),
        RGBAColor(red: 1.00, green: 0.27, blue: 0.35),
        RGBAColor(red: 0.15, green: 0.80, blue: 0.45),
        RGBAColor(red: 1.00, green: 0.65, blue: 0.10),
        RGBAColor(red: 0.65, green: 0.35, blue: 0.95),
        RGBAColor(red: 0.10, green: 0.75, blue: 0.85),
        RGBAColor(red: 0.95, green: 0.45, blue: 0.75)
    ]
}

// MARK: - Settings

struct AppSettings: Codable {
    var crossfadeEnabled: Bool = false
    var crossfadeDuration: Double = 3.0
    var highCutEnabled: Bool = false
    var highCutDuration: Double = 2.0

    init() {}

    init(crossfadeEnabled: Bool,
         crossfadeDuration: Double,
         highCutEnabled: Bool,
         highCutDuration: Double) {
        self.crossfadeEnabled = crossfadeEnabled
        self.crossfadeDuration = crossfadeDuration
        self.highCutEnabled = highCutEnabled
        self.highCutDuration = highCutDuration
    }

    // Декодер со значениями по умолчанию — чтобы старый файл состояния
    // без новых полей не ронял загрузку.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        crossfadeEnabled = try c.decodeIfPresent(Bool.self, forKey: .crossfadeEnabled) ?? false
        crossfadeDuration = try c.decodeIfPresent(Double.self, forKey: .crossfadeDuration) ?? 3.0
        highCutEnabled = try c.decodeIfPresent(Bool.self, forKey: .highCutEnabled) ?? false
        highCutDuration = try c.decodeIfPresent(Double.self, forKey: .highCutDuration) ?? 2.0
    }
}

// MARK: - Persisted application state

struct AppState: Codable {
    var playlists: [Playlist]
    var settings: AppSettings
    var selectedPlaylistID: UUID?

    init(playlists: [Playlist], settings: AppSettings, selectedPlaylistID: UUID?) {
        self.playlists = playlists
        self.settings = settings
        self.selectedPlaylistID = selectedPlaylistID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? [Playlist(name: "Плейлист 1", order: 0)]
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        selectedPlaylistID = try c.decodeIfPresent(UUID.self, forKey: .selectedPlaylistID)
    }

    static func fresh() -> AppState {
        let first = Playlist(name: "Плейлист 1", order: 0)
        return AppState(playlists: [first], settings: AppSettings(), selectedPlaylistID: first.id)
    }
}
