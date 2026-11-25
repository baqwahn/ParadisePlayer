import Foundation
import Observation

/// Merkt sich den gewählten Musikordner dauerhaft (Security-Scoped Bookmark),
/// damit die App nach dem Neustart ohne erneute Auswahl darauf zugreifen kann.
/// Für Ordner in iCloud Drive ist keine eigene iCloud-Berechtigung nötig:
/// Die Freigabe erfolgt über die Ordnerauswahl des Systems.
@MainActor
@Observable
final class FolderAccess {
    private(set) var rootURL: URL?

    @ObservationIgnored private var isAccessing = false
    private let defaultsKey = "rootFolderBookmark"

    init() {
        restore()
    }

    func select(_ url: URL) throws {
        stopAccessing()
        guard url.startAccessingSecurityScopedResource() else { throw FileAccessError.accessDenied }
        isAccessing = true
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: defaultsKey)
        rootURL = url
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale),
              url.startAccessingSecurityScopedResource() else { return }
        isAccessing = true
        if isStale, let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: defaultsKey)
        }
        rootURL = url
    }

    private func stopAccessing() {
        if isAccessing, let rootURL { rootURL.stopAccessingSecurityScopedResource() }
        isAccessing = false
    }
}
