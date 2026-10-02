import Foundation

/// The list as it was when a dictation started, shared by the preparer and the correction stage so one
/// dictation never mixes two versions of the list. Dictations never overlap (the pipeline's busy guard).
@MainActor
final class VocabularySnapshot {
    var matcher: VocabularyMatcher?
}

/// Before transcription: the snapshot, the terms for later stages, the Whisper hint and the cleanup
/// prompt's "write these exactly" rule.
@MainActor
struct VocabularyPreparer: DictationContextPreparer {
    let store: VocabularyStore
    let snapshot: VocabularySnapshot

    func prepare(_ context: inout DictationContext) {
        let enabled = store.enabledTerms
        snapshot.matcher = enabled.isEmpty ? nil : store.matcher
        guard !enabled.isEmpty else { return }
        context.vocabularyTerms = enabled.map(\.term)
        if let rule = store.promptRule { context.cleanupRules.append(rule) }
        if Self.sendsWhisperHint(speechModelID: context.speechModelID, language: context.speechHints.language) {
            // Most important last: WhisperKit drops the start of a long prompt
            context.speechHints.glossary = enabled.map(\.term).reversed()
        }
    }

    /// Whisper only, and only for English or Auto-detect: an English glossary can pull other languages
    /// toward English.
    static func sendsWhisperHint(speechModelID: String?, language: String?) -> Bool {
        guard let speechModelID, ModelRegistry.model(id: speechModelID)?.engine == .whisperKit else { return false }
        guard let language else { return true }
        return language.lowercased().hasPrefix("en")
    }
}

/// After transcription and the speaker-label merge: listed spellings become the terms as written, using
/// the list from when the dictation started.
@MainActor
struct VocabularyCorrectionStage: TextStage {
    let snapshot: VocabularySnapshot

    func apply(_ text: String, context: inout DictationContext) -> String {
        snapshot.matcher?.apply(text) ?? text
    }
}
