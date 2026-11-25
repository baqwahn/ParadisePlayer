import Foundation
import Observation

/// Zentrale App-Logik: Ordner, Trackliste, Auswahl, Bewertung, Papierkorb, Analyse.
@MainActor
@Observable
final class AppModel {
    let engine = AudioEngine()
    let store = LibraryStore()
    let folder = FolderAccess()

    var tracks: [Track] = []
    var currentID: Track.ID?
    var waveform: Waveform?
    var loadState: LoadState = .idle
    var isScanning = false
    var errorMessage: String?
    var filter: TrackFilter = .all
    var sort: TrackSort = .name

    var settings = AppSettings.load() {
        didSet {
            settings.save()
            let range = settings.pitchRange
            if abs(engine.pitchPercent) > range {
                engine.pitchPercent = max(-range, min(range, engine.pitchPercent))
            }
        }
    }

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init() {
        engine.onTrackFinished = { [weak self] in
            guard let self, self.settings.autoPlayNext else { return }
            self.next()
        }
    }

    // MARK: Abgeleitete Werte

    var currentTrack: Track? {
        guard let currentID else { return nil }
        return tracks.first { $0.id == currentID }
    }

    var currentInfo: TrackInfo? {
        currentID.map { store.info($0) }
    }

    var visibleTracks: [Track] {
        let filtered = tracks.filter { track in
            let rating = store.info(track.id).rating
            switch filter {
            case .all: return true
            case .unrated: return rating == 0
            case .rated: return rating > 0
            case .top: return rating >= 4
            }
        }
        switch sort {
        case .name:
            return filtered
        case .bpm:
            return filtered.sorted { (store.info($0.id).bpm ?? .infinity) < (store.info($1.id).bpm ?? .infinity) }
        case .camelot:
            return filtered.sorted { Camelot.sortKey(store.info($0.id).camelot) < Camelot.sortKey(store.info($1.id).camelot) }
        case .rating:
            return filtered.sorted { store.info($0.id).rating > store.info($1.id).rating }
        }
    }

    func title(for track: Track) -> String {
        store.info(track.id).title ?? track.parsedTitle
    }

    func artist(for track: Track) -> String? {
        store.info(track.id).artist ?? track.parsedArtist
    }

    func isCompatibleWithCurrent(_ track: Track) -> Bool {
        guard track.id != currentID,
              let a = currentInfo?.camelot,
              let b = store.info(track.id).camelot else { return false }
        return Camelot.isCompatible(a, b)
    }

    /// Nächster Track in der aktuellen Liste (für die Vorschau unter dem Player).
    var upcomingTrack: Track? {
        if let current = currentTrack { return track(after: current) }
        return visibleTracks.first
    }

    var jumpSeconds: Double {
        if let bpm = currentInfo?.bpm, bpm > 0 { return Double(settings.jumpBeats) * 60 / bpm }
        return 10
    }

    var jumpLabel: String {
        currentInfo?.bpm != nil ? "\(settings.jumpBeats)" : "10s"
    }

    // MARK: Ordner

    func chooseFolder(_ url: URL) {
        do {
            try folder.select(url)
            loadTask?.cancel()
            engine.unload()
            tracks = []
            currentID = nil
            waveform = nil
            loadState = .idle
            Task { await reload() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadIfNeeded() async {
        if tracks.isEmpty { await reload() }
    }

    func reload() async {
        guard let root = folder.rootURL, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            tracks = try await Task.detached(priority: .userInitiated) {
                try ICloudFiles.scan(root: root)
            }.value
        } catch {
            errorMessage = "Der Ordner konnte nicht gelesen werden: \(error.localizedDescription)"
        }
    }

    // MARK: Wiedergabe

    func select(_ track: Track, autoplay: Bool = true) {
        loadTask?.cancel()
        engine.unload()
        currentID = track.id
        waveform = nil
        loadState = track.isDownloaded ? .loading : .downloading

        let url = track.url
        let id = track.id
        loadTask = Task {
            do {
                try await ICloudFiles.ensureDownloaded(url)
                try Task.checkCancellation()
                markDownloaded(id)
                loadState = .loading
                try engine.load(url: url)
                engine.seek(to: startTime(duration: engine.duration))
                if autoplay { engine.play() }
                loadState = .ready
                prefetch(after: id)
                await analyze(id: id, url: url)
            } catch is CancellationError {
                // Track wurde gewechselt
            } catch {
                guard currentID == id else { return }
                loadState = .failed
                errorMessage = "„\(track.fileName)“ konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    func togglePlay() {
        if engine.isLoaded {
            engine.togglePlay()
        } else if let track = currentTrack ?? visibleTracks.first {
            select(track)
        }
    }

    func next() {
        guard let current = currentTrack else {
            if let first = visibleTracks.first { select(first) }
            return
        }
        if let following = track(after: current) { select(following) }
    }

    func previous() {
        if engine.currentTime > 3 {
            engine.seek(to: 0)
            return
        }
        guard let current = currentTrack, let before = track(before: current) else { return }
        select(before)
    }

    func jump(forward: Bool) {
        engine.seek(to: engine.currentTime + (forward ? jumpSeconds : -jumpSeconds))
    }

    // MARK: Bewerten und Aussortieren

    /// Bewertet den aktuellen Track. Erneutes Tippen auf denselben Stern entfernt die Bewertung.
    /// Der Track läuft danach weiter, es wird nicht automatisch gewechselt.
    func rate(_ stars: Int) {
        guard let current = currentTrack else { return }
        let newValue = store.info(current.id).rating == stars ? 0 : stars
        store.update(current.id) { $0.rating = newValue }
    }

    func setRating(_ stars: Int, for track: Track) {
        store.update(track.id) { $0.rating = stars }
    }

    func trashCurrent() {
        if let current = currentTrack { trash(current) }
    }

    /// Verschiebt den Track in "_Papierkorb" und springt beim aktuellen Track weiter.
    func trash(_ track: Track) {
        guard let root = folder.rootURL else { return }
        let isCurrent = track.id == currentID
        let following = isCurrent ? self.track(after: track) : nil
        if isCurrent {
            loadTask?.cancel()
            engine.unload()
        }
        do {
            try ICloudFiles.moveToTrash(track.url, root: root)
            tracks.removeAll { $0.id == track.id }
            store.remove(track.id)
            if isCurrent {
                currentID = nil
                waveform = nil
                loadState = .idle
                if let following { select(following) }
            }
        } catch {
            errorMessage = "Verschieben in den Papierkorb fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    func emptyTrash() -> String {
        guard let root = folder.rootURL else { return "Kein Ordner gewählt." }
        let count = ICloudFiles.emptyTrash(root: root)
        return count == 0 ? "Der Papierkorb ist leer." : "\(count) Dateien endgültig gelöscht."
    }

    // MARK: Intern

    private func track(after track: Track) -> Track? {
        let list = visibleTracks
        guard let i = list.firstIndex(where: { $0.id == track.id }), i + 1 < list.count else { return nil }
        return list[i + 1]
    }

    private func track(before track: Track) -> Track? {
        let list = visibleTracks
        guard let i = list.firstIndex(where: { $0.id == track.id }), i > 0 else { return nil }
        return list[i - 1]
    }

    private func startTime(duration: TimeInterval) -> TimeInterval {
        switch settings.startMode {
        case .beginning: return 0
        case .seconds30: return duration > 60 ? 30 : 0
        case .quarter: return duration * 0.25
        }
    }

    private func markDownloaded(_ id: String) {
        if let i = tracks.firstIndex(where: { $0.id == id }) { tracks[i].isDownloaded = true }
    }

    private func prefetch(after id: String) {
        let list = visibleTracks
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let upcoming = list.dropFirst(i + 1).prefix(2).filter { !$0.isDownloaded }.map(\.url)
        ICloudFiles.prefetch(Array(upcoming))
    }

    /// Tags lesen, Wellenform berechnen, BPM analysieren, falls kein Tag vorhanden.
    private func analyze(id: String, url: URL) async {
        if store.info(id).tagsVersion < MetadataReader.version {
            let tags = await MetadataReader.read(url: url)
            store.update(id) { info in
                if let title = tags.title { info.title = title }
                if let artist = tags.artist { info.artist = artist }
                if let bpm = tags.bpm { info.bpm = bpm; info.bpmFromTag = true }
                if let key = tags.camelot { info.camelot = key }
                info.tagsVersion = MetadataReader.version
            }
        }

        let key = WaveformGenerator.cacheKey(id: id, size: tracks.first { $0.id == id }?.fileSize)
        let generated: Waveform? = await Task.detached(priority: .userInitiated) {
            try? WaveformGenerator.loadOrGenerate(url: url, cacheKey: key)
        }.value
        if currentID == id { waveform = generated }

        if store.info(id).bpm == nil {
            let minBPM = settings.minBPM
            let bpm: Double? = await Task.detached(priority: .utility) {
                try? BPMDetector.detect(url: url, minBPM: minBPM)
            }.value
            if let bpm {
                store.update(id) { $0.bpm = bpm; $0.bpmFromTag = false }
            }
        }
    }
}
