import Foundation

/// The last good copy of every feed, on disk.
///
/// Florin reads a server that is often on a LAN or a tailnet, which means the
/// app spends real time with no way to reach it — on a plane, on a train, on a
/// phone that has just woken up. Showing "injoignable" in that situation is a
/// choice, and the wrong one: the figures were true an hour ago and an hour-old
/// balance is worth far more than an error screen.
///
/// So every successful response is written here, and a failed one falls back to
/// it. The UI is told the data is stale rather than being lied to — see
/// `OverviewModel.staleSince`.
///
/// This is a cache, not a database: it is read-only, it is keyed by endpoint,
/// and losing it costs nothing but a refresh. It is also the first half of
/// running the app without a server at all, which is a much larger job.
enum SnapshotCache {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static func file(_ key: String) -> URL {
        // Endpoint paths contain slashes and query strings; neither survives a
        // file name.
        let safe = key.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "=", with: "_")
            .replacingOccurrences(of: "&", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    static func write(_ data: Data, for key: String) {
        // Excluded from iCloud backup: it is a copy of the user's whole ledger
        // and it can always be fetched again.
        var url = file(key)
        try? data.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    static func read(_ key: String) -> (data: Data, savedAt: Date)? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date
        else { return nil }
        return (data, date)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }
}
