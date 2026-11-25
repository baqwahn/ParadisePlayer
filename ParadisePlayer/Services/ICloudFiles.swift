import Foundation

nonisolated enum FileAccessError: LocalizedError {
    case accessDenied
    case downloadTimeout

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Kein Zugriff auf den Ordner. Bitte den Ordner erneut auswählen."
        case .downloadTimeout: "Der Download aus iCloud hat zu lange gedauert. Bitte Verbindung prüfen."
        }
    }
}

/// Dateizugriff auf einen vom Nutzer gewählten Ordner, typischerweise in iCloud Drive.
///
/// iCloud-Dateien, die noch nicht auf dem Gerät liegen, erscheinen im Ordner als
/// Platzhalter (".Name.mp3.icloud"). Die App zeigt sie trotzdem in der Liste an
/// und lädt sie erst beim Abspielen. Die nächsten Tracks werden im Hintergrund vorgeladen.
nonisolated enum ICloudFiles {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "flac", "caf", "alac"]
    static let trashFolderName = "_Papierkorb"

    // MARK: Ordner einlesen

    static func scan(root: URL) throws -> [Track] {
        var result: [Track] = []
        var coordError: NSError?
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .ubiquitousItemDownloadingStatusKey]

        NSFileCoordinator().coordinate(readingItemAt: root, options: [], error: &coordError) { dir in
            guard let enumerator = FileManager.default.enumerator(
                at: dir,
                includingPropertiesForKeys: keys,
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { return }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                let values = try? url.resourceValues(forKeys: Set(keys))

                if values?.isDirectory == true {
                    if name == trashFolderName || name.hasPrefix(".") { enumerator.skipDescendants() }
                    continue
                }

                var realURL = url
                var relative = relativePath(of: url, root: dir)
                var downloaded = true

                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    // iCloud-Platzhalter: ".Track.mp3.icloud" -> "Track.mp3"
                    let realName = String(name.dropFirst().dropLast(".icloud".count))
                    realURL = url.deletingLastPathComponent().appendingPathComponent(realName)
                    let relDir = (relative as NSString).deletingLastPathComponent
                    relative = relDir.isEmpty ? realName : relDir + "/" + realName
                    downloaded = false
                } else if name.hasPrefix(".") {
                    continue
                } else if let status = values?.ubiquitousItemDownloadingStatus {
                    downloaded = status == .current || status == .downloaded
                }

                guard audioExtensions.contains(realURL.pathExtension.lowercased()) else { continue }

                result.append(Track(
                    id: relative,
                    url: realURL,
                    fileName: realURL.deletingPathExtension().lastPathComponent,
                    isDownloaded: downloaded,
                    fileSize: values?.fileSize.map { Int64($0) }
                ))
            }
        }

        if let coordError { throw coordError }
        return result.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    // MARK: Download

    /// Wartet, bis die Datei lokal vorliegt, und stößt den Download bei Bedarf an.
    static func ensureDownloaded(_ url: URL, timeout: Duration = .seconds(180)) async throws {
        if isLocallyAvailable(url) { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
            if isLocallyAvailable(url) { return }
        }
        throw FileAccessError.downloadTimeout
    }

    /// Stößt den Download an, ohne zu warten (für die nächsten Tracks in der Liste).
    static func prefetch(_ urls: [URL]) {
        for url in urls where !isLocallyAvailable(url) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    static func isLocallyAvailable(_ url: URL) -> Bool {
        var u = url
        u.removeAllCachedResourceValues()
        let exists = FileManager.default.fileExists(atPath: u.path(percentEncoded: false))
        guard exists else { return false }
        if let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           v.isUbiquitousItem == true,
           let status = v.ubiquitousItemDownloadingStatus {
            return status == .current || status == .downloaded
        }
        return true
    }

    // MARK: Papierkorb

    /// Verschiebt die Datei in den Unterordner "_Papierkorb" des gewählten Ordners.
    @discardableResult
    static func moveToTrash(_ url: URL, root: URL) throws -> URL {
        let trash = root.appendingPathComponent(trashFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let destination = uniqueURL(for: url.lastPathComponent, in: trash)

        var coordError: NSError?
        var moveError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordError
        ) { src, dst in
            do { try FileManager.default.moveItem(at: src, to: dst) } catch { moveError = error }
        }
        if let coordError { throw coordError }
        if let moveError { throw moveError }
        return destination
    }

    /// Löscht alle Dateien im Papierkorb endgültig. Gibt die Anzahl zurück.
    static func emptyTrash(root: URL) -> Int {
        let trash = root.appendingPathComponent(trashFolderName, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) else { return 0 }
        var count = 0
        for item in items {
            var coordError: NSError?
            var deleteError: Error?
            NSFileCoordinator().coordinate(writingItemAt: item, options: .forDeleting, error: &coordError) { u in
                do { try FileManager.default.removeItem(at: u) } catch { deleteError = error }
            }
            if coordError == nil, deleteError == nil { count += 1 }
        }
        return count
    }

    // MARK: Hilfsfunktionen

    private static func uniqueURL(for name: String, in dir: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = dir.appendingPathComponent("\(base) (\(i))").appendingPathExtension(ext)
            i += 1
        }
        return candidate
    }

    private static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path(percentEncoded: false)
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }
}
