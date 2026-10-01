import Foundation

/// Before transcription: the Whisper spelling hint and the cleanup prompt's "write these exactly" rule,
/// from the list as it is now.
@MainActor
struct VocabularyPreparer: DictationContextPreparer {
    let store: VocabularyStore

    func prepare(_ context: inout DictationContext) {
        let enabled = store.enabledTerms
        guard !enabled.isEmpty else { return }
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

/// After transcription and the speaker-label merge: listed spellings become the terms as written.
@MainActor
struct VocabularyCorrectionStage: TextStage {
    let store: VocabularyStore

    func apply(_ text: String, context: inout DictationContext) -> String {
        store.matcher.apply(text)
    }
}
