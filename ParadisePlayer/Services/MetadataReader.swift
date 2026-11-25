import AVFoundation

/// Liest Titel, Interpret, BPM und Tonart aus den Tags.
/// Mixed In Key schreibt die Tonart je nach Einstellung ins Tonart-Feld (ID3: TKEY)
/// und/oder ins Kommentarfeld. Beides wird ausgewertet, das Tonart-Feld hat Vorrang.
nonisolated enum MetadataReader {
    struct Tags: Sendable {
        var title: String?
        var artist: String?
        var bpm: Double?
        var camelot: String?
    }

    /// Wird erhöht, wenn sich das Auslesen ändert. Tracks mit älterer Version werden neu gelesen.
    static let version = 2

    static func read(url: URL) async -> Tags {
        var tags = Tags()
        let asset = AVURLAsset(url: url)

        // Alle Metadaten-Formate einzeln laden (ID3, iTunes, QuickTime …)
        var items = (try? await asset.load(.metadata)) ?? []
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let more = try? await asset.loadMetadata(for: format) { items.append(contentsOf: more) }
            }
        }

        #if DEBUG
        print("── Tags: \(url.lastPathComponent)")
        for item in items {
            let value = (try? await item.load(.stringValue)) ?? nil
            print("   \(item.identifier?.rawValue ?? "?")  =  \(value ?? "–")")
        }
        #endif

        var keyFields: [String] = []
        var commentFields: [String] = []

        for item in items {
            let id = (item.identifier?.rawValue.lowercased() ?? "") + "|" + ((item.key as? String)?.lowercased() ?? "")
            let string = (try? await item.load(.stringValue)) ?? nil

            if item.commonKey == .commonKeyTitle, tags.title == nil, let string, !string.isEmpty {
                tags.title = string
            }
            if item.commonKey == .commonKeyArtist, tags.artist == nil, let string, !string.isEmpty {
                tags.artist = string
            }

            if tags.bpm == nil, item.identifier == .id3MetadataBeatsPerMinute
                || item.identifier == .iTunesMetadataBeatsPerMin
                || id.contains("tbpm") || id.contains("tmpo") || id.hasSuffix("bpm") {
                if let string, let value = parseBPM(string) {
                    tags.bpm = value
                } else if let number = (try? await item.load(.numberValue)) ?? nil, let value = parseBPM(number.stringValue) {
                    tags.bpm = value
                }
            }

            if item.identifier == .id3MetadataInitialKey || id.contains("tkey") || id.contains("initialkey") {
                if let string { keyFields.append(string) }
            }

            if item.identifier == .id3MetadataComments || item.identifier == .iTunesMetadataUserComment
                || id.contains("comm") || id.contains("cmt") || item.commonKey == .commonKeyDescription {
                if let string { commentFields.append(string) }
            }
        }

        tags.camelot = keyFields.lazy.compactMap { Camelot.parse($0, allowMusicalNotation: true) }.first
            ?? commentFields.lazy.compactMap { Camelot.parse($0, allowMusicalNotation: false) }.first
        return tags
    }

    private static func parseBPM(_ s: String) -> Double? {
        let cleaned = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), (40...250).contains(value) else { return nil }
        return value
    }
}
