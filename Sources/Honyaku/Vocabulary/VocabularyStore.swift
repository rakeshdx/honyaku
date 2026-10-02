import Foundation
import Observation
import OSLog

/// The user's word list: `vocabulary.json` next to `history.json`, private to this Mac.
/// One store per `FeatureEnvironment`, shared by the pipeline stages and the Vocabulary tab.
@Observable
@MainActor
final class VocabularyStore: FeatureStore {
    static let fileName = "vocabulary.json"
    /// Terms in the cleanup prompt's "write these exactly" rule.
    static let promptRuleLimit = 40
    /// Import limits: a bigger file is refused rather than freezing the app.
    static let importByteLimit = 1_000_000
    static let importTermLimit = 2_000

    private static let log = Logger(subsystem: "com.honyaku.app", category: "vocabulary")

    /// The user's order: the top of the list matters most.
    private(set) var terms: [VocabularyTerm] = []
    /// Set when `vocabulary.json` couldn't be read and was set aside; shown in the tab until dismissed.
    var corruptFileNotice: String?
    /// Set when the last change couldn't be saved; shown in the tab until dismissed or a save succeeds.
    var saveFailureNotice: String?
    /// The damaged file couldn't be set aside: never overwrite it. Edits still apply until quit.
    @ObservationIgnored private var savingBlocked = false

    @ObservationIgnored let fileURL: URL
    /// Rebuilt only when the list changes, not on every dictation.
    @ObservationIgnored private var cachedMatcher: VocabularyMatcher?

    init(environment: FeatureEnvironment) {
        fileURL = environment.directory.appending(path: Self.fileName)
        load()
    }

    // MARK: - What the pipeline uses

    var enabledTerms: [VocabularyTerm] { terms.filter(\.enabled) }

    var matcher: VocabularyMatcher {
        if let cachedMatcher { return cachedMatcher }
        let built = VocabularyMatcher(terms: terms)
        cachedMatcher = built
        return built
    }

    /// "Write these terms exactly as listed: …" for `terms` (the ones a transcript contains, in list
    /// order), at most `promptRuleLimit` of them; nil without terms. Never the whole list: a rewrite used
    /// unsaid terms as material to invent from.
    static func promptRule(for terms: [String]) -> String? {
        let listed = terms.prefix(promptRuleLimit)
        guard !listed.isEmpty else { return nil }
        return "Write these terms exactly as listed: \(listed.joined(separator: ", "))."
    }

    // MARK: - Editing

    /// Adds a term at the end of the list.
    @discardableResult
    func add(term: String, heardAs: [String] = []) throws -> VocabularyTerm {
        let entry = try validated(VocabularyTerm(term: term, heardAs: heardAs), replacing: nil)
        terms.append(entry)
        changed()
        return entry
    }

    func update(_ id: VocabularyTerm.ID, term: String, heardAs: [String]) throws {
        guard let index = terms.firstIndex(where: { $0.id == id }) else { return }
        var edited = terms[index]
        edited.term = term
        edited.heardAs = heardAs
        terms[index] = try validated(edited, replacing: id)
        changed()
    }

    func setEnabled(_ id: VocabularyTerm.ID, _ enabled: Bool) {
        guard let index = terms.firstIndex(where: { $0.id == id }), terms[index].enabled != enabled else { return }
        terms[index].enabled = enabled
        changed()
    }

    func delete(_ id: VocabularyTerm.ID) {
        terms.removeAll { $0.id == id }
        changed()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        terms.move(fromOffsets: source, toOffset: destination)
        changed()
    }

    /// One place up (`by: -1`) or down (`by: 1`), for keyboard and VoiceOver users.
    func move(_ id: VocabularyTerm.ID, by offset: Int) {
        guard let index = terms.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard terms.indices.contains(target) else { return }
        terms.swapAt(index, target)
        changed()
    }

    /// From a History row: adds `heardAs` to the term written `writeAs` if it's already listed (ignoring
    /// case), otherwise adds a new term. `heardAs` may be empty when only the letter case was wrong.
    func addFromHistory(heardAs: String, writeAs: String) throws {
        let spelling = VocabularyText.normalized(writeAs)
        if let existing = terms.first(where: { VocabularyText.fold($0.term) == VocabularyText.fold(spelling) }) {
            let heard = VocabularyText.normalized(heardAs)
            guard !heard.isEmpty else { return }
            try update(existing.id, term: existing.term, heardAs: existing.heardAs + [heard])
        } else {
            try add(term: spelling, heardAs: heardAs.isEmpty ? [] : [heardAs])
        }
    }

    // MARK: - Import and export

    func exportData() throws -> Data {
        try Self.encoder.encode(VocabularyFile(terms: terms))
    }

    /// Merges a file by term, ignoring case: existing terms gain spellings and keep their place and on/off
    /// state, new terms go at the end, nothing is deleted. Throws, changing nothing, for an unreadable file
    /// or one over the import limits. One pass, with lookups by folded spelling, so time is linear.
    func importData(_ data: Data) throws -> VocabularyImportSummary {
        guard data.count <= Self.importByteLimit else { throw VocabularyImportError.tooLarge }
        let file = try Self.decodeFile(data)
        guard file.terms.count <= Self.importTermLimit else { throw VocabularyImportError.tooLarge }
        var summary = VocabularyImportSummary()
        var merged = terms
        // Folded term → its index, and folded spelling (term or heard-as) → the index of the term using it
        var termIndex: [String: Int] = [:]
        var owners: [String: Int] = [:]
        for (index, term) in merged.enumerated() {
            termIndex[VocabularyText.fold(term.term)] = index
            owners[VocabularyText.fold(term.term)] = index
            for heard in term.heardAs { owners[VocabularyText.fold(heard)] = index }
        }
        for incoming in file.terms {
            let spelling = VocabularyText.normalized(incoming.term)
            guard !spelling.isEmpty, spelling.count <= VocabularyError.maxLength else { continue }
            let foldedSpelling = VocabularyText.fold(spelling)
            let index = termIndex[foldedSpelling]
            // A new term that another term already lists as a heard-as spelling would make both ambiguous
            if index == nil, let owner = owners[foldedSpelling] {
                summary.skipped.append((spelling, merged[owner].term))
                continue
            }
            let targetIndex = index ?? merged.count
            var target = index.map { merged[$0] } ?? VocabularyTerm(term: spelling, enabled: incoming.enabled)
            var gained: [String] = []
            for heard in incoming.heardAs.map(VocabularyText.normalized) {
                let foldedHeard = VocabularyText.fold(heard)
                guard !heard.isEmpty, heard.count <= VocabularyError.maxLength,
                      foldedHeard != VocabularyText.fold(target.term),
                      !target.heardAs.contains(where: { VocabularyText.fold($0) == foldedHeard })
                else { continue }
                if let owner = owners[foldedHeard], owner != targetIndex {
                    summary.skipped.append((heard, merged[owner].term))
                    continue
                }
                target.heardAs.append(heard)
                gained.append(foldedHeard)
            }
            if let index {
                guard !gained.isEmpty else { continue }
                merged[index] = target
                summary.updated += 1
            } else {
                merged.append(target)
                termIndex[foldedSpelling] = targetIndex
                owners[foldedSpelling] = targetIndex
                summary.added += 1
            }
            for folded in gained { owners[folded] = targetIndex }
        }
        if merged != terms {
            terms = merged
            changed()
        }
        return summary
    }

    // MARK: - Validation

    /// Trims and checks an edited or new term against the rest of the list (`replacing` is the term being
    /// edited). Heard-as spellings matching the term itself are dropped: the term always matches itself.
    private func validated(_ candidate: VocabularyTerm, replacing id: VocabularyTerm.ID?) throws -> VocabularyTerm {
        var result = candidate
        result.term = VocabularyText.normalized(candidate.term)
        guard !result.term.isEmpty else { throw VocabularyError.emptyTerm }
        guard result.term.count <= VocabularyError.maxLength else { throw VocabularyError.tooLong }
        let others = terms.filter { $0.id != id }
        let folded = VocabularyText.fold(result.term)
        if others.contains(where: { VocabularyText.fold($0.term) == folded }) { throw VocabularyError.duplicateTerm }
        if let owner = others.first(where: { $0.heardAs.contains { VocabularyText.fold($0) == folded } }) {
            throw VocabularyError.heardAsInUse(spelling: result.term, term: owner.term)
        }

        var spellings: [String] = []
        for heard in candidate.heardAs.map(VocabularyText.normalized) where !heard.isEmpty {
            guard heard.count <= VocabularyError.maxLength else { throw VocabularyError.tooLong }
            let foldedHeard = VocabularyText.fold(heard)
            guard foldedHeard != folded, !spellings.contains(where: { VocabularyText.fold($0) == foldedHeard }) else { continue }
            if let owner = Self.owner(of: heard, in: others, excluding: nil) {
                throw VocabularyError.heardAsInUse(spelling: heard, term: owner.term)
            }
            spellings.append(heard)
        }
        result.heardAs = spellings
        return result
    }

    /// The term other than `excluding` that already uses `spelling`, as its own spelling or a heard-as one.
    private static func owner(of spelling: String, in terms: [VocabularyTerm],
                              excluding id: VocabularyTerm.ID?) -> VocabularyTerm? {
        let folded = VocabularyText.fold(spelling)
        return terms.first { term in
            term.id != id && (VocabularyText.fold(term.term) == folded
                || term.heardAs.contains { VocabularyText.fold($0) == folded })
        }
    }

    // MARK: - File

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static func decodeFile(_ data: Data) throws -> VocabularyFile {
        let file = try JSONDecoder().decode(VocabularyFile.self, from: data)
        guard file.version <= VocabularyFile.currentVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return file
    }

    private func changed() {
        cachedMatcher = nil
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            terms = try Self.decodeFile(Data(contentsOf: fileURL)).terms
        } catch {
            setAsideCorruptFile()
        }
    }

    /// Keeps the unreadable file for the user and starts an empty list; dictation never stops for it.
    private func setAsideCorruptFile() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "vocabulary.corrupt-\(stamp).json"
        let backup = fileURL.deletingLastPathComponent().appending(path: name)
        terms = []
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
            corruptFileNotice = "Your word list couldn\u{2019}t be read. It was saved as \(name), and Honyaku started a new one."
        } catch {
            // Never overwrite a file the user may want back
            savingBlocked = true
            Self.log.error("Couldn't set aside the damaged vocabulary file: \(error.localizedDescription, privacy: .public)")
            corruptFileNotice = "Couldn\u{2019}t set aside the damaged vocabulary file. Changes won\u{2019}t be saved until it\u{2019}s fixed or removed."
        }
    }

    /// Atomic, owner-only and excluded from backup, like `history.json`.
    private func persist() {
        guard !savingBlocked else { return }
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try exportData().write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = fileURL
            try url.setResourceValues(values)
            saveFailureNotice = nil
        } catch {
            // Operational metadata only, never the terms
            Self.log.error("Couldn't save the vocabulary: \(error.localizedDescription, privacy: .public)")
            saveFailureNotice = "Couldn\u{2019}t save your word list: \(error.localizedDescription) Your changes apply until you quit Honyaku."
        }
    }
}
