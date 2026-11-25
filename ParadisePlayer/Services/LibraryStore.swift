import Foundation
import Observation

/// Speichert Bewertungen, BPM und Tonart pro Track lokal in der App (library.json).
@MainActor
@Observable
final class LibraryStore {
    private(set) var infos: [String: TrackInfo] = [:]

    private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "library.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: TrackInfo].self, from: data) {
            infos = decoded
        }
    }

    func info(_ id: String) -> TrackInfo {
        infos[id] ?? TrackInfo()
    }

    func update(_ id: String, _ change: (inout TrackInfo) -> Void) {
        var info = info(id)
        change(&info)
        infos[id] = info
        scheduleSave()
    }

    func remove(_ id: String) {
        infos[id] = nil
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(infos) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
