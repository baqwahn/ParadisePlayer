import Foundation

/// Eine Audiodatei im gewählten Ordner.
nonisolated struct Track: Identifiable, Hashable, Sendable {
    /// Relativer Pfad innerhalb des gewählten Ordners, dient als stabile ID.
    let id: String
    let url: URL
    let fileName: String
    var isDownloaded: Bool
    let fileSize: Int64?

    /// Fallback, solange keine Tags gelesen wurden: "Artist - Title" aus dem Dateinamen.
    var parsedArtist: String? {
        let parts = fileName.components(separatedBy: " - ")
        return parts.count >= 2 ? parts[0].trimmingCharacters(in: .whitespaces) : nil
    }

    var parsedTitle: String {
        let parts = fileName.components(separatedBy: " - ")
        guard parts.count >= 2 else { return fileName }
        return parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
    }
}

/// Gespeicherte Informationen pro Track (Bewertung, BPM, Tonart, Tags).
nonisolated struct TrackInfo: Codable, Sendable, Equatable {
    var title: String?
    var artist: String?
    var bpm: Double?
    var bpmFromTag = false
    var camelot: String?
    var rating = 0
    var tagsVersion = 0

    init() {}

    enum CodingKeys: String, CodingKey {
        case title, artist, bpm, bpmFromTag, camelot, rating, tagsVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm)
        bpmFromTag = try c.decodeIfPresent(Bool.self, forKey: .bpmFromTag) ?? false
        camelot = try c.decodeIfPresent(String.self, forKey: .camelot)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        tagsVersion = try c.decodeIfPresent(Int.self, forKey: .tagsVersion) ?? 0
    }

    /// Herz-Modus: ab 4 Sternen gilt ein Track als "mit Herz".
    var isHearted: Bool { rating >= 4 }
}

/// Bewertungsart: fünf Sterne oder ein Herz (an/aus).
/// Intern wird immer `rating` 0–5 gespeichert, Herz an = 5, Herz aus = 0.
nonisolated enum RatingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case stars, heart
    var id: String { rawValue }
    var label: String {
        switch self {
        case .stars: "Sterne (1–5)"
        case .heart: "Herz"
        }
    }
}

nonisolated enum StartMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginning, seconds30, quarter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .beginning: "Anfang"
        case .seconds30: "Nach 30 Sekunden"
        case .quarter: "Bei 25 % der Laufzeit"
        }
    }
}

nonisolated struct AppSettings: Codable, Sendable {
    var minBPM: Double = 80
    var jumpBeats = 16
    var pitchRange: Double = 8
    var startMode: StartMode = .beginning
    var autoPlayNext = true
    var ratingStyle: RatingStyle = .stars

    init() {}

    enum CodingKeys: String, CodingKey {
        case minBPM, jumpBeats, pitchRange, startMode, autoPlayNext, ratingStyle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        minBPM = try c.decodeIfPresent(Double.self, forKey: .minBPM) ?? d.minBPM
        jumpBeats = try c.decodeIfPresent(Int.self, forKey: .jumpBeats) ?? d.jumpBeats
        pitchRange = try c.decodeIfPresent(Double.self, forKey: .pitchRange) ?? d.pitchRange
        startMode = try c.decodeIfPresent(StartMode.self, forKey: .startMode) ?? d.startMode
        autoPlayNext = try c.decodeIfPresent(Bool.self, forKey: .autoPlayNext) ?? d.autoPlayNext
        ratingStyle = try c.decodeIfPresent(RatingStyle.self, forKey: .ratingStyle) ?? d.ratingStyle
    }

    static let defaultsKey = "appSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

nonisolated enum TrackFilter: String, CaseIterable, Identifiable, Sendable {
    case all, unrated, rated, top
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Alle"
        case .unrated: "Neu"
        case .rated: "Bewertet"
        case .top: "4+"
        }
    }

    /// Im Herz-Modus gibt es nur Alle, Neu (ohne Herz) und Herz.
    static func cases(for style: RatingStyle) -> [TrackFilter] {
        style == .heart ? [.all, .unrated, .top] : allCases
    }

    func label(for style: RatingStyle) -> String {
        guard style == .heart else { return label }
        switch self {
        case .all: return "Alle"
        case .unrated: return "Neu"
        case .rated, .top: return "Herz"
        }
    }
}

nonisolated enum TrackSort: String, CaseIterable, Identifiable, Sendable {
    case name, bpm, camelot, rating
    var id: String { rawValue }
    var label: String {
        switch self {
        case .name: "Name"
        case .bpm: "BPM"
        case .camelot: "Tonart"
        case .rating: "Bewertung"
        }
    }
}

nonisolated enum LoadState: Equatable, Sendable {
    case idle, downloading, loading, ready, failed
}
