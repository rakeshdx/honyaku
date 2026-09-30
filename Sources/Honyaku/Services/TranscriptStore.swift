import Foundation

@MainActor
final class TranscriptStore: ObservableObject {
    @Published private(set) var entries: [TranscriptEntry] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Honyaku/history.json")
    }()

    private let persistsToDisk: Bool

    init() {
        persistsToDisk = true
        prepareDirectory()
        load()
    }

    /// A store that never reads or writes history.json — for tests and design renders.
    init(inMemory entries: [TranscriptEntry]) {
        persistsToDisk = false
        self.entries = entries
    }

    func save(_ entry: TranscriptEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func delete(_ id: TranscriptEntry.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    /// Entries whose cleaned text contains `query`, case- and diacritic-insensitively; all entries for a blank query.
    static func filter(_ entries: [TranscriptEntry], matching query: String) -> [TranscriptEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.cleanedText.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func clearAll() {
        entries.removeAll()
        guard persistsToDisk else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private

    private func prepareDirectory() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Exclude from backup
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(rv)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard persistsToDisk, let data = try? JSONEncoder().encode(entries) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            // Enforce permissions 600 (owner rw, no group/other access)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            // Ensure backup exclusion on the file itself
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            var mutableURL = fileURL
            try? mutableURL.setResourceValues(rv)
        } catch {
            // Log operational metadata only — no content
            print("[TranscriptStore] persist failed: \(error.localizedDescription)")
        }
    }
}
