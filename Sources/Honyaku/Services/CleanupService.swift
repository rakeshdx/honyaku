import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import os

enum CleanupError: Error {
    case timedOut
    case modelNotLoaded
}

/// One call to the cleanup model.
struct CleanupRequest: Equatable, Sendable {
    enum Faithfulness: Equatable, Sendable {
        /// Output may only delete words from the transcript; anything else falls back to the transcript.
        case strict
        /// Output is used as the model wrote it. The caller is responsible for its safety.
        case none
    }

    var systemPrompt: String
    /// Extra lines appended to the system prompt, each on its own line.
    var extraRules: [String] = []
    var faithfulness: Faithfulness = .strict
    /// Output token cap; nil uses `CleanupService.outputTokenLimit(for:)`.
    var maxTokens: Int?
    /// Whether um/uh and the set-off English fillers may be dropped. Only for English transcripts.
    var englishFillers = true
    /// Vocabulary terms strict output must keep exactly: as many occurrences as the input has, with the same
    /// letter case and characters such as "+" that the word comparison ignores.
    var protectedTerms: [String] = []
}

actor CleanupService: CleanupServiceProtocol {
    private var loadedModelID: String?
    private var container: ModelContainer?
    private var loadedInfo: ModelInfo?
    private let promptCache = PromptPrefixCache()
    /// Pins one model instead of following the user's selection (benchmarks compare tiers side by side).
    private let fixedModelID: String?

    init(modelID: String? = nil) {
        fixedModelID = modelID
    }
    // In-flight load, so a launch warm-up and a dictation never load the model twice
    private var loading: (modelID: String, task: Task<ModelContainer, Error>)?
    private let timeoutSeconds: Double = 60

    static let defaultPrompt = """
    You clean up dictated text. Return the transcript with these changes only:
    - Delete the filler sounds um, umm, uh and hmm.
    - Add punctuation and capital letters.
    Keep every other word exactly as spoken, in the same order. Do not add, reword, answer or summarize anything.
    Output only the cleaned transcript.
    Examples:
    Transcript: um so I think we should uh maybe ship it or not
    Cleaned: So I think we should maybe ship it or not.
    Transcript: are you, like, coming tomorrow or not
    Cleaned: Are you coming tomorrow or not?
    """

    /// Only speaker-labelled transcripts get the label rule: given to every dictation, it made Qwen3-4B
    /// answer "[Speaker 1]" to ordinary sentences.
    static let speakerLabelRule = "Keep every [Speaker N] label exactly as it appears."

    static func prompt(_ base: String, for transcript: String) -> String {
        transcript.contains("[Speaker ") ? base + "\n" + speakerLabelRule : base
    }

    /// The system prompt for `request`: the speaker-label rule when the transcript has labels, then each
    /// extra rule on its own line.
    static func systemPrompt(for request: CleanupRequest, transcript: String) -> String {
        ([prompt(request.systemPrompt, for: transcript)] + request.extraRules).joined(separator: "\n")
    }

    /// The text to use for the model's `output`: the transcript when the output is empty, or when a strict
    /// request's output changed the transcript's words.
    static func accept(_ output: String, raw rawText: String, request: CleanupRequest) -> String {
        if output.isEmpty { return rawText }
        guard request.faithfulness == .strict else { return output }
        // Never trust the model with the user's words: if it lost or added any, keep theirs
        guard isFaithful(raw: rawText, cleaned: output, englishFillers: request.englishFillers),
              keepsTerms(request.protectedTerms, raw: rawText, cleaned: output) else {
            // Transcript text is never logged
            log.info("Cleanup output changed the transcript's words; using raw transcript")
            return request.englishFillers ? removeUnambiguousFillers(rawText) : rawText
        }
        return output
    }


    /// No protected term lost an exact occurrence ("Paramount+" → "Paramount" passes the word comparison).
    static func keepsTerms(_ terms: [String], raw: String, cleaned: String) -> Bool {
        terms.allSatisfy { term in
            term.isEmpty || occurrences(of: term, in: cleaned) >= occurrences(of: term, in: raw)
        }
    }

    private static func occurrences(of term: String, in text: String) -> Int {
        text.components(separatedBy: term).count - 1
    }

    func clean(_ rawText: String, request: CleanupRequest) async throws -> String {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rawText
        }
        let (model, info) = try await loadModel()
        let promptCache = self.promptCache

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                let output = try await CleanupService.modelOutput(
                    for: rawText, prompt: CleanupService.systemPrompt(for: request, transcript: rawText),
                    maxTokens: request.maxTokens ?? CleanupService.outputTokenLimit(for: rawText),
                    model: model, info: info, reuse: promptCache)
                return CleanupService.accept(output, raw: rawText, request: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(self.timeoutSeconds))
                throw CleanupError.timedOut
            }
            do {
                let result = try await group.next()!
                group.cancelAll()
                return result
            } catch {
                // A generation still running after a timeout mustn't hand its cache to the next dictation
                promptCache.invalidate()
                throw error
            }
        }
    }

    /// The model's cleaned text before the faithfulness check. Integration tests use it so the
    /// fallback can't hide a model that drops or adds words.
    func modelOutput(for rawText: String, prompt: String) async throws -> String {
        let (model, info) = try await loadModel()
        return try await CleanupService.modelOutput(for: rawText, prompt: CleanupService.prompt(prompt, for: rawText),
                                                    maxTokens: CleanupService.outputTokenLimit(for: rawText),
                                                    model: model, info: info, reuse: promptCache)
    }

    private static func modelOutput(for rawText: String, prompt: String, maxTokens: Int, model: ModelContainer,
                                    info: ModelInfo, reuse: PromptPrefixCache) async throws -> String {
        // Qwen3 reasons before answering unless its chat template is told not to
        let templateContext: [String: any Sendable]? = info.disablesThinking ? ["enable_thinking": false] : nil
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0)
        let cacheKey = "\(info.id)\n\(info.disablesThinking)\n\(prompt)"

        let generation = reuse.generation
        let response: String = try await model.perform { context in
            func tokens(for transcript: String) async throws -> [Int] {
                let input = UserInput(chat: [.system(prompt), .user(frame(transcript))], additionalContext: templateContext)
                return try await context.processor.prepare(input: input).text.tokens.asArray(Int.self)
            }
            let full = try await tokens(for: rawText)

            if reuse.key != cacheKey {
                // The part every dictation shares: the system prompt and the user turn's opening markup
                let (a, b) = (try await tokens(for: "a"), try await tokens(for: "b"))
                reuse.prefix = zip(a, b).prefix { $0 == $1 }.map(\.0)
                reuse.cache = nil
                reuse.key = cacheKey
            }

            // Reuse the system prompt's key/value cache so each dictation only processes its own words
            let prefix = reuse.prefix
            var cache: [KVCache]
            var input = full
            if let primed = reuse.cache, !prefix.isEmpty, full.count > prefix.count,
               full.starts(with: prefix), primed.first?.offset == prefix.count {
                cache = primed
                input = Array(full[prefix.count...])
            } else {
                cache = context.model.newCache(parameters: parameters)
            }
            reuse.cache = nil  // held again below only once it's trimmed back to the shared prefix

            var text = ""
            for await item in try generate(input: LMInput(tokens: MLXArray(input)), cache: cache,
                                           parameters: parameters, context: context) {
                if case .chunk(let chunk) = item { text += chunk }
            }

            // Drop this dictation from the cache, keeping only the shared prefix for the next one —
            // unless the cache was invalidated meanwhile (a timeout), in which case start fresh next time
            if reuse.generation == generation, !prefix.isEmpty, full.starts(with: prefix), canTrimPromptCache(cache),
               let offset = cache.first?.offset, offset >= prefix.count {
                for layer in cache { layer.trim(offset - prefix.count) }
                reuse.cache = cache
            }
            return text
        }
        return stripDelimiters(response)
    }

    /// Framed as data: a bare question like "Are you working or not?" otherwise gets answered or rewritten.
    private static func frame(_ transcript: String) -> String {
        "Transcript to clean:\n\"\"\"\n\(transcript)\n\"\"\""
    }

    /// Cleanup only deletes words, so output needs about as many tokens as the input; the cap stops a
    /// model that starts rambling. Roughly three characters per token for English.
    static func outputTokenLimit(for rawText: String) -> Int {
        min(512, 2 * (rawText.count / 3 + 1) + 32)
    }

    /// The prompt text a model in `directory` receives for one turn, built with its chat template the way
    /// cleanup builds it. Loads only the tokenizer, not the weights. Throws when the folder has no template,
    /// where mlx-swift-lm would otherwise fall back to plain text. Lets integration tests check the format.
    static func chatPromptText(modelDirectory directory: URL, system: String, user: String) async throws -> String {
        let tokenizer = try await loadTokenizer(configuration: ModelConfiguration(directory: directory),
                                                hub: defaultHubApi)
        let tokens = try tokenizer.applyChatTemplate(messages: [["role": "system", "content": system],
                                                                ["role": "user", "content": user]])
        return tokenizer.decode(tokens: tokens)
    }

    /// Loads the selected model ahead of the first dictation (launch warm-up).
    func prepare() async throws {
        _ = try await loadModel()
    }

    private func loadModel() async throws -> (ModelContainer, ModelInfo) {
        let modelID = fixedModelID
            ?? UserDefaults.standard.string(forKey: "selectedCleanupModelID") ?? ModelRegistry.defaultCleanupModelID
        if let existing = container, let loadedInfo, loadedModelID == modelID { return (existing, loadedInfo) }
        guard let info = ModelRegistry.model(id: modelID), info.engine == .mlx else { throw CleanupError.modelNotLoaded }
        if let loading, loading.modelID == modelID { return (try await loading.task.value, info) }

        let modelDir = ModelStore.shared.modelDirectory(for: info)
        guard ModelInstaller.isMLXComplete(at: modelDir) else {
            throw CleanupError.modelNotLoaded
        }

        let task = Task { try await loadModelContainer(directory: modelDir) }
        loading = (modelID, task)
        defer { if loading?.task == task { loading = nil } }  // only clear our own load
        let loaded = try await task.value
        container = loaded
        loadedInfo = info
        loadedModelID = modelID
        return (loaded, info)
    }

    // MARK: - Output checks

    private static let log = Logger(subsystem: "com.honyaku.app", category: "cleanup")
    /// Always filler, removable anywhere.
    private static let unambiguousFillers = #"um|umm|uh|hmm"#
    /// Filler only when set off — followed by a comma, and after a comma or at a sentence start —
    /// since "I like it", "turn right" and "I think so" are content.
    private static let ambiguousFillers = #"you know|sort of|kind of|like|so|right|basically|literally"#

    /// Characters the model may never introduce: line breaks and control characters (pasting into a
    /// terminal could run something) and shell metacharacters. Allowed only if the raw text had them.
    private static let forbiddenIntroduced = CharacterSet.newlines
        .union(.controlCharacters)
        .union(CharacterSet(charactersIn: "`|&;$<>\\{}"))

    /// True when `cleaned` is `raw` with only deletions — every word kept in order apart from removable
    /// fillers, nothing added or reordered — and introduces no forbidden character.
    /// With `englishFillers` off (a non-English transcript) no word counts as a filler.
    static func isFaithful(raw: String, cleaned: String, englishFillers: Bool = true) -> Bool {
        let rawWords = words(in: raw)
        let cleanedWords = words(in: cleaned)
        let required = englishFillers ? words(in: removableFillersStripped(raw)) : rawWords
        let introducesForbidden = cleaned.unicodeScalars.contains {
            forbiddenIntroduced.contains($0) && !raw.unicodeScalars.contains($0)
        }
        return !introducesForbidden
            && isSubsequence(cleanedWords, of: rawWords)
            && isSubsequence(required, of: cleanedWords)
    }

    private static func isSubsequence(_ needle: [String], of haystack: [String]) -> Bool {
        var remaining = haystack[...]
        for word in needle {
            guard let index = remaining.firstIndex(of: word) else { return false }
            remaining = remaining[remaining.index(after: index)...]
        }
        return true
    }

    private static func removableFillersStripped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "(?i)(?<![\\w'’-])(\(unambiguousFillers))(?![\\w'’-])", with: " ", options: .regularExpression)
            // Lookahead keeps the comma, so it can anchor the next filler in a chain ("Right, so, we…")
            .replacingOccurrences(of: "(?i)(^|[.!?,])\\s*(\(ambiguousFillers))\\s*(?=,)", with: "$1 ", options: .regularExpression)
    }

    /// Fallback text: the raw transcript minus fillers that are never content ("uh-huh" stays intact).
    /// Spacing and punctuation are tidied only where a filler was removed, so a standalone "." elsewhere
    /// ("git add .") stays standalone.
    static func removeUnambiguousFillers(_ text: String) -> String {
        let gap = "\u{E000}"  // private-use marker for "a filler was here"
        return text.replacingOccurrences(of: gap, with: "")
            .replacingOccurrences(of: "(?i)(?<![\\w'’-])(\(unambiguousFillers))(?![\\w'’-]),?", with: gap, options: .regularExpression)
            // Fillers at the start take their trailing punctuation with them ("Um. So we go")
            .replacingOccurrences(of: "^[\\s,.;:]*\(gap)[\\s,.;:\(gap)]*", with: "", options: .regularExpression)
            // A filler right before punctuation: the punctuation moves up to the previous word ("it uh.")
            .replacingOccurrences(of: "\\s*\(gap)[\\s\(gap)]*([,.!?])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\(gap)[\\s\(gap)]*", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Removes the triple-quote framing and a `Cleaned:` label if the model echoes them back.
    static func stripDelimiters(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\"\"\"", with: "")
            // A thinking model that ignored enable_thinking: false must never have its reasoning pasted
            .replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["Transcript to clean:", "Cleaned:"] where result.lowercased().hasPrefix(label.lowercased()) {
            result = String(result.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Only a pure wrapper: a dictated quotation has quotes inside too and must survive
        if result.count >= 2, result.first == "\"", result.last == "\"",
           !result.dropFirst().dropLast().contains("\"") {
            result = String(result.dropFirst().dropLast())
        }
        return result
    }

    private static func words(in text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map(String.init)
    }
}

/// The key/value cache for the system prompt, reused across dictations for the same model and prompt.
/// Only touched inside `ModelContainer.perform`, which `CleanupService` runs one dictation at a time.
final class PromptPrefixCache: @unchecked Sendable {
    var key: String?
    var prefix: [Int] = []
    var cache: [KVCache]?
    /// Bumped by `invalidate()`; a generation that started before the bump never stores its cache back.
    var generation = 0

    func invalidate() {
        generation += 1
        key = nil
        cache = nil
    }
}
