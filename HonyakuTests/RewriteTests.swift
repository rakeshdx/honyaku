import XCTest
@testable import Honyaku

// MARK: - Templates, prompts and output

final class RewriteTemplateTests: XCTestCase {
    func testAutomaticTemplateByCategory() {
        XCTAssertEqual(RewriteTemplateID.automatic(for: .chat), .chatMessage)
        XCTAssertEqual(RewriteTemplateID.automatic(for: .terminal), .agentPrompt)
        XCTAssertEqual(RewriteTemplateID.automatic(for: .codeEditor), .agentPrompt)
        XCTAssertEqual(RewriteTemplateID.automatic(for: .email), .email)
        XCTAssertEqual(RewriteTemplateID.automatic(for: .browser), .jiraTicket)
        XCTAssertEqual(RewriteTemplateID.automatic(for: .other), .jiraTicket)
    }

    func testCaps() {
        XCTAssertEqual(RewriteTemplateID.commitMessage.tokenCap, 200)
        XCTAssertEqual(RewriteTemplateID.chatMessage.tokenCap, 300)
        XCTAssertEqual(RewriteTemplateID.standupUpdate.tokenCap, 300)
        XCTAssertEqual(RewriteTemplateID.agentPrompt.tokenCap, 400)
        XCTAssertEqual(RewriteTemplateID.jiraTicket.tokenCap, 700)
        XCTAssertEqual(RewriteTemplateID.prDescription.tokenCap, 700)
        XCTAssertEqual(RewriteTemplateID.email.tokenCap, 700)
    }

    func testCapIsReducedForShortDictations() {
        // 3 words ≈ 4 tokens: 150 + 3 × 4
        XCTAssertEqual(RewritePrompt.tokenCap(for: .jiraTicket, transcript: "ship it today"), 162)
        let long = Array(repeating: "word", count: 300).joined(separator: " ")
        XCTAssertEqual(RewritePrompt.tokenCap(for: .jiraTicket, transcript: long), 700)
        XCTAssertEqual(RewritePrompt.tokenCap(for: .commitMessage, transcript: long), 200)
    }

    func testNamesInSentences() {
        XCTAssertEqual(RewriteCopy.recording(.chatMessage), "Rewriting as chat message")
        XCTAssertEqual(RewriteCopy.generating(.jiraTicket), "Rewriting as Jira ticket…")
        XCTAssertEqual(RewriteCopy.historyCaption(.prDescription), "Rewritten as PR description")
        XCTAssertEqual(RewriteCopy.recording(.agentPrompt), "Rewriting as coding-agent prompt")
        for template in RewriteTemplateID.allCases {
            XCTAssertFalse(RewriteCopy.recording(template).contains("·"), "No middle-dot separators")
        }
    }

    func testRequestCombinesSharedRulesTemplateAndVocabulary() {
        let plan = RewritePlan(template: .chatMessage, templatePrompt: "Rewrite as one sentence")
        let request = plan.request(for: "we ship today", extraRules: ["Write these terms exactly as listed: Paramount+"],
                                   englishFillers: true)
        XCTAssertEqual(request.systemPrompt, RewritePrompt.sharedRules + "\nRewrite as one sentence")
        XCTAssertEqual(request.extraRules, ["Write these terms exactly as listed: Paramount+"])
        XCTAssertEqual(request.faithfulness, CleanupRequest.Faithfulness.none)
        XCTAssertEqual(request.maxTokens, RewritePrompt.tokenCap(for: .chatMessage, transcript: "we ship today"))
        XCTAssertEqual(request.transcriptLabel, "Dictation to rewrite:")
        XCTAssertTrue(RewritePrompt.sharedRules.contains("Never invent names, numbers, dates, links, ticket IDs or facts."))
        XCTAssertTrue(RewritePrompt.sharedRules.contains("write TBD"))
    }

    func testSpeakerLineOnlyWithLabels() {
        let request = RewritePlan(template: .jiraTicket).request(for: "x", extraRules: [], englishFillers: true)
        let labelled = CleanupService.systemPrompt(for: request, transcript: "[Speaker 1] ship it [Speaker 2] okay")
        XCTAssertTrue(labelled.contains(RewritePrompt.speakerLabelRule))
        XCTAssertFalse(labelled.contains(CleanupService.speakerLabelRule), "Cleanup's keep-the-labels rule isn't used")
        let plain = CleanupService.systemPrompt(for: request, transcript: "ship it")
        XCTAssertFalse(plain.contains("speaker labels"))
        XCTAssertTrue(plain.hasSuffix(RewriteTemplateID.jiraTicket.defaultPrompt))
    }

    func testCleanupRequestsKeepTheirOwnFrameAndLabelRule() {
        let request = CleanupRequest(systemPrompt: "Clean")
        XCTAssertEqual(request.transcriptLabel, "Transcript to clean:")
        XCTAssertEqual(CleanupService.systemPrompt(for: request, transcript: "[Speaker 1] hi"),
                       "Clean\n" + CleanupService.speakerLabelRule)
    }

    func testRewriteOutputIsUsedAsWrittenEvenEmpty() {
        let request = RewritePlan(template: .jiraTicket).request(for: "x", extraRules: [], englishFillers: true)
        XCTAssertEqual(CleanupService.accept("", raw: "we ship it", request: request), "",
                       "Empty output must reach the caller as a failure, not as the transcript")
        XCTAssertEqual(CleanupService.accept("Summary: ship it\n\n- today", raw: "we ship it today", request: request),
                       "Summary: ship it\n\n- today")
    }

    func testEchoedLabelsAreStripped() {
        XCTAssertEqual(strip("Rewrite:\nSummary: x"), "Summary: x")
        XCTAssertEqual(strip("Dictation to rewrite: hello"), "hello")
        XCTAssertEqual(strip("  \n "), "")
        XCTAssertEqual(strip("Summary: rewrite the parser"), "Summary: rewrite the parser")
        XCTAssertEqual(strip("Rewritten chat message:\nReview the login bug - no rush.", .chatMessage),
                       "Review the login bug - no rush.")
        XCTAssertEqual(strip("Jira ticket:\n\nSummary: x"), "Summary: x")
        XCTAssertEqual(strip("Here's your Jira ticket:\n\nSummary: x"), "Summary: x")
        XCTAssertEqual(strip(
            "Rewrite the dictation as a Jira ticket in exactly this layout:\n\nSummary: x  \n- y  "), "Summary: x\n- y",
            "A line copied from the prompt and trailing spaces go")
        XCTAssertEqual(strip("- Use only what the speaker said. Never invent names, numbers, dates, links, ticket IDs or facts.\nAdd retries"),
                       "Add retries", "A copied shared rule goes")
        XCTAssertEqual(strip("Acceptance criteria:\n- works"), "Acceptance criteria:\n- works",
                       "A section label is content, not an echo")
    }

    func testContentThatLooksLikeAnInstructionIsKept() {
        XCTAssertEqual(strip("Rewrite the dictation pipeline as stages", .commitMessage),
                       "Rewrite the dictation pipeline as stages")
        XCTAssertEqual(strip("Here's the plan:\n- Ship it", .standupUpdate), "Here's the plan:\n- Ship it")
        XCTAssertEqual(strip("Changes to the email template:\n- New footer", .prDescription),
                       "Changes to the email template:\n- New footer", "Naming a template inside a heading isn't an echo")
        XCTAssertEqual(strip("Rewrite: the parser is slow", .commitMessage), "Rewrite: the parser is slow")
    }

    func testOneLineForTerminals() {
        let ticket = "Summary: Export does nothing\n\nDescription: Clicking export\ndoes nothing.\n\n- Downloads a CSV\n"
        XCTAssertEqual(RewritePrompt.joinedOnOneLine(ticket),
                       "Summary: Export does nothing Description: Clicking export does nothing. - Downloads a CSV")
        XCTAssertEqual(RewritePrompt.joinedOnOneLine("Run `make test` with $PATH set\r\n"), "Run `make test` with $PATH set",
                       "Backticks and $ are kept; the trailing line break goes")
    }

    func testEveryKindOfLineBreakIsJoinedAndControlsGo() {
        for lineBreak in ["\r\n", "\r", "\u{2028}", "\u{2029}", "\u{85}", "\u{0B}", "\u{0C}"] {
            XCTAssertEqual(RewritePrompt.joinedOnOneLine("one" + lineBreak + "two" + lineBreak), "one two",
                           "Line break U+\(String(lineBreak.unicodeScalars.first!.value, radix: 16))")
        }
        XCTAssertEqual(RewritePrompt.joinedOnOneLine("ls\u{1B}[2J -la\u{07}\u{7F}"), "ls[2J -la", "Escape, bell and delete go")
        XCTAssertEqual(RewritePrompt.joinedOnOneLine("a\tb"), "a\tb", "Tab stays")
    }

    func testCapCountsScriptsWithoutSpaces() {
        let japanese = String(repeating: "エクスポートボタンを押しても何も起きません。", count: 14)  // about a minute
        XCTAssertGreaterThan(RewritePrompt.estimatedTokens(japanese), 250)
        XCTAssertEqual(RewritePrompt.tokenCap(for: .jiraTicket, transcript: japanese), 700)
        XCTAssertEqual(RewritePrompt.estimatedTokens("githubを使う"), 2 + 3, "One word, plus three characters")
        XCTAssertEqual(RewritePrompt.estimatedTokens("ship it today"), 4, "Spaced text is unchanged")
    }

    func testCutShortTrimsToTheLastCompleteLineOrSentence() {
        XCTAssertEqual(RewritePrompt.trimmedToLastComplete("Summary: Export\n\nAcceptance criteria:\n- Downloads a C"),
                       "Summary: Export\n\nAcceptance criteria:")
        XCTAssertEqual(RewritePrompt.trimmedToLastComplete("Add retries. Make sure you log the err"), "Add retries.")
        XCTAssertEqual(RewritePrompt.trimmedToLastComplete("All done."), "All done.")
        XCTAssertEqual(RewritePrompt.trimmedToLastComplete("Add retries to the upl"), "", "Nothing complete is left")
    }

    func testUnclosedReasoningIsDropped() {
        XCTAssertEqual(CleanupService.stripDelimiters("<think>\nThe user wants a ticket and"), "")
        XCTAssertEqual(CleanupService.stripDelimiters("<think>a</think>Send it.<think>more"), "Send it.")
        XCTAssertTrue(CleanupService.hasUnclosedReasoning("<think>\nThe user wants"))
        XCTAssertFalse(CleanupService.hasUnclosedReasoning("<think>a</think>Send it."))
    }

    func testPromptCacheKeepsThreePromptsMostRecentLast() {
        let cache = PromptPrefixCache()
        for key in ["dictation", "jira", "chat"] { cache.put(.init(key: key, prefix: [1])) }
        XCTAssertNotNil(cache.take("dictation"))
        cache.put(.init(key: "dictation", prefix: [1]))
        cache.put(.init(key: "email", prefix: [1]))
        XCTAssertEqual(cache.entries.map(\.key), ["chat", "dictation", "email"], "The least recently used went")
        cache.invalidate()
        XCTAssertTrue(cache.entries.isEmpty)
    }

    private func strip(_ output: String, _ template: RewriteTemplateID = .jiraTicket) -> String {
        RewritePrompt.stripEchoes(output, plan: RewritePlan(template: template))
    }
}

// MARK: - Settings

@MainActor
final class RewriteSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var environment: FeatureEnvironment!

    override func setUp() {
        super.setUp()
        suiteName = "HonyakuRewriteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        environment = FeatureEnvironment(
            directory: FileManager.default.temporaryDirectory.appending(path: "honyaku-tests-\(UUID().uuidString)"),
            defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: environment.directory)
        super.tearDown()
    }

    private var slack: TargetApp { TargetApp(bundleID: "com.tinyspeck.slackmacgap", pid: 1) }
    private var terminal: TargetApp { TargetApp(bundleID: "com.apple.Terminal", pid: 2) }

    func testAutomaticByDefault() {
        let settings = RewriteSettings(environment: environment)
        XCTAssertNil(settings.fixedTemplate)
        XCTAssertEqual(settings.resolvedTemplate(forAppAtStart: slack), .chatMessage)
        XCTAssertEqual(settings.resolvedTemplate(forAppAtStart: terminal), .agentPrompt)
        XCTAssertEqual(settings.resolvedTemplate(forAppAtStart: nil), .jiraTicket, "An unknown app is everything else")
    }

    func testFixedChoiceWinsAndPersists() {
        let settings = RewriteSettings(environment: environment)
        settings.fixedTemplate = .commitMessage
        XCTAssertEqual(settings.resolvedTemplate(forAppAtStart: slack), .commitMessage)
        XCTAssertEqual(RewriteSettings(environment: environment).fixedTemplate, .commitMessage, "Survives a relaunch")
        settings.fixedTemplate = nil
        XCTAssertNil(RewriteSettings(environment: environment).fixedTemplate)
        XCTAssertEqual(settings.resolvedTemplate(forAppAtStart: slack), .chatMessage)
    }

    func testCategoryTemplateIsStoredOnlyWhenChanged() {
        let settings = RewriteSettings(environment: environment)
        settings.setTemplate(.commitMessage, for: .terminal)
        XCTAssertEqual(settings.resolvedTemplate(forAppAtStart: terminal), .commitMessage)
        XCTAssertEqual(RewriteSettings(environment: environment).template(for: .terminal), .commitMessage)
        settings.setTemplate(.agentPrompt, for: .terminal)
        XCTAssertNil(defaults.object(forKey: RewriteSettings.categoryTemplatesKey), "Back to the default: nothing stored")
    }

    func testAnEmptiedPromptCountsAsTheDefault() {
        let settings = RewriteSettings(environment: environment)
        settings.setPrompt("  \n", for: .chatMessage)
        XCTAssertEqual(settings.editorText(for: .chatMessage), "  \n", "The editor keeps what's typed")
        XCTAssertTrue(settings.isEdited(.chatMessage))
        XCTAssertEqual(settings.prompt(for: .chatMessage), RewriteTemplateID.chatMessage.defaultPrompt)
        XCTAssertEqual(settings.plan(forAppAtStart: slack).templatePrompt, RewriteTemplateID.chatMessage.defaultPrompt)
        settings.resetPrompt(for: .chatMessage)
        XCTAssertFalse(settings.isEdited(.chatMessage))
    }

    func testEditedPromptAndReset() {
        let settings = RewriteSettings(environment: environment)
        settings.setPrompt("Rewrite as one sentence", for: .chatMessage)
        XCTAssertEqual(settings.plan(forAppAtStart: slack), RewritePlan(template: .chatMessage, templatePrompt: "Rewrite as one sentence"))
        XCTAssertEqual(RewriteSettings(environment: environment).prompt(for: .chatMessage), "Rewrite as one sentence")
        settings.resetPrompt(for: .chatMessage)
        XCTAssertEqual(settings.prompt(for: .chatMessage), RewriteTemplateID.chatMessage.defaultPrompt)
        XCTAssertNil(defaults.object(forKey: RewriteSettings.promptKey(for: .chatMessage)), "No edited copy is kept")
    }

    func testPlannerOnlyPlansRewrites() {
        let planner = RewritePlanner(settings: RewriteSettings(environment: environment))
        var dictation = DictationContext(mode: .dictate, appAtStart: slack)
        planner.prepare(&dictation)
        XCTAssertNil(dictation.rewrite)
        var rewrite = DictationContext(mode: .rewrite, appAtStart: slack)
        planner.prepare(&rewrite)
        XCTAssertEqual(rewrite.rewrite?.template, .chatMessage)
    }

    func testStoreIsSharedThroughTheEnvironment() {
        XCTAssertTrue(environment.store(RewriteSettings.self) === environment.store(RewriteSettings.self))
    }
}

// MARK: - The pipeline

@MainActor
final class RewritePipelineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var appState: AppState!
    private var store: TranscriptStore!
    private var audio: FakeAudioCapture!
    private var transcription: FakeTranscription!
    private var cleanup: FakeCleanup!
    private var paste: FakePaste!
    private var models: FakeModels!
    private var targets: FakeTargets!
    private var environment: FeatureEnvironment!

    private let ticket = "Summary: Export does nothing\n\nAcceptance criteria:\n- Downloads a CSV"

    override func setUp() {
        super.setUp()
        suiteName = "HonyakuRewritePipelineTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        appState = AppState(defaults: defaults)
        store = TranscriptStore(inMemory: [])
        audio = FakeAudioCapture()
        transcription = FakeTranscription()
        transcription.text = "um the export button does nothing"
        cleanup = FakeCleanup()
        paste = FakePaste()
        models = FakeModels()
        targets = FakeTargets()
        environment = FeatureEnvironment(
            directory: FileManager.default.temporaryDirectory.appending(path: "honyaku-tests-\(UUID().uuidString)"),
            defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: environment.directory)
        super.tearDown()
    }

    private func makePipeline(extra: PipelineStages? = nil) -> TranscriptionPipeline {
        let services = PipelineServices(audioCapture: audio, transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: models, targets: targets)
        return TranscriptionPipeline(appState: appState, transcriptStore: store, services: services,
                                     stages: .combined([extra ?? .none, RewriteStages.make(environment)]),
                                     defaults: defaults)
    }

    /// One Control+Shift hold: start as dictation, end as a rewrite.
    private func rewrite(_ pipeline: TranscriptionPipeline, beforeStop: () -> Void = {}) async {
        pipeline.startRecording()
        beforeStop()
        await pipeline.stopRecordingAndProcess(mode: .rewrite)?.value
    }

    func testRewritePastesTheModelsTextAndSavesBoth() async {
        targets.front = TargetApp(bundleID: "com.google.Chrome", pid: 3)
        cleanup.respond = { [ticket] _ in ticket }
        await rewrite(makePipeline())

        XCTAssertEqual(paste.pasted, [ticket], "Sections keep their blank lines: no filler pass on a rewrite")
        let request = cleanup.requests.first
        XCTAssertEqual(request?.faithfulness, CleanupRequest.Faithfulness.none)
        XCTAssertEqual(request?.systemPrompt, RewritePrompt.sharedRules + "\n" + RewriteTemplateID.jiraTicket.defaultPrompt)
        XCTAssertEqual(request?.maxTokens, RewritePrompt.tokenCap(for: .jiraTicket, transcript: "um the export button does nothing"))
        let entry = store.entries.first
        XCTAssertEqual(entry?.mode, "rewrite")
        XCTAssertEqual(entry?.rewriteTemplateID, "jiraTicket")
        XCTAssertEqual(entry?.rawText, "um the export button does nothing", "Your words")
        XCTAssertEqual(entry?.cleanedText, ticket)
        XCTAssertEqual(appState.status, .idle)
    }

    func testTemplateFollowsTheAppAtStartNotAtPaste() async {
        cleanup.respond = { _ in "Line one\nLine two" }
        await rewrite(makePipeline()) {
            // Slack at start; the user switches to Terminal before the paste
            targets.front = TargetApp(bundleID: "com.apple.Terminal", pid: 7)
        }
        XCTAssertEqual(store.entries.first?.rewriteTemplateID, "chatMessage")
        XCTAssertEqual(paste.pasted, ["Line one Line two"], "Formatted for the terminal it landed in")
    }

    func testRewriteIntoATerminalIsOneLine() async {
        targets.front = TargetApp(bundleID: "com.apple.Terminal", pid: 7)
        cleanup.respond = { _ in "Add a retry to `upload()` in uploader.swift\nand run $TESTS.\n" }
        await rewrite(makePipeline())
        XCTAssertEqual(paste.pasted, ["Add a retry to `upload()` in uploader.swift and run $TESTS."])
        XCTAssertEqual(store.entries.first?.rewriteTemplateID, "agentPrompt")
    }

    func testDictationIntoATerminalIsUnchangedByRewrite() async {
        targets.front = TargetApp(bundleID: "com.apple.Terminal", pid: 7)
        transcription.text = "hello world"
        let pipeline = makePipeline()
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess(mode: .dictate)?.value
        XCTAssertEqual(paste.pasted, ["hello world"])
        XCTAssertEqual(cleanup.requests.first?.faithfulness, .strict)
        XCTAssertNil(store.entries.first?.rewriteTemplateID)
    }

    func testFixedTemplateFromTheMenu() async {
        environment.store(RewriteSettings.self).fixedTemplate = .standupUpdate
        await rewrite(makePipeline())
        XCTAssertEqual(store.entries.first?.rewriteTemplateID, "standupUpdate")
    }

    func testRewriteRunsWithCleanupOff() async {
        appState.cleanupEnabled = false
        cleanup.respond = { _ in "Rewritten." }
        await rewrite(makePipeline())
        XCTAssertEqual(paste.pasted, ["Rewritten."])
    }

    func testVocabularyRulesReachTheRewrite() async {
        let vocabulary = PipelineStages(preparers: [RecordingPreparer()])
        await rewrite(makePipeline(extra: vocabulary))
        XCTAssertEqual(cleanup.requests.first?.extraRules, ["Write Paramount+ exactly."])
    }

    func testNoModelPastesTheWordsWithANotice() async {
        models.missing = [appState.selectedCleanupModelID]
        await rewrite(makePipeline())

        XCTAssertTrue(cleanup.inputs.isEmpty, "No model call")
        XCTAssertTrue(models.downloads.isEmpty, "No download is started for a rewrite")
        XCTAssertEqual(paste.pasted, ["the export button does nothing"], "Fillers removed, no model")
        XCTAssertEqual(store.entries.first?.mode, "dictate")
        XCTAssertNil(store.entries.first?.rewriteTemplateID)
        XCTAssertEqual(appState.status, .error(RewriteCopy.noModelNotice))
    }

    func testModelErrorPastesTheWordsWithANotice() async {
        cleanup.respond = nil
        await rewrite(makePipeline())

        XCTAssertEqual(cleanup.inputs.count, 1, "No second model call")
        XCTAssertEqual(paste.pasted, ["the export button does nothing"])
        XCTAssertEqual(store.entries.first?.mode, "dictate")
        XCTAssertEqual(appState.status, .error(RewriteCopy.failedNotice))
    }

    func testCutShortIsTrimmedAndFlagged() async {
        cleanup.respond = { _ in "Summary: Export does nothing\n\nAcceptance criteria:\n- Downloads a C" }
        cleanup.hitTokenLimit = true
        await rewrite(makePipeline())
        XCTAssertEqual(paste.pasted, ["Summary: Export does nothing\n\nAcceptance criteria:"])
        XCTAssertEqual(store.entries.first?.mode, "rewrite")
        XCTAssertEqual(appState.status, .error(RewriteCopy.cutShortNotice))
    }

    func testCutShortWithNothingCompleteIsAFailure() async {
        cleanup.respond = { _ in "Add retries to the upl" }
        cleanup.hitTokenLimit = true
        await rewrite(makePipeline())
        XCTAssertEqual(paste.pasted, ["the export button does nothing"])
        XCTAssertEqual(appState.status, .error(RewriteCopy.failedNotice))
    }

    func testReasoningCutOffIsAFailure() async {
        cleanup.respond = { _ in "Summary: half a thought" }
        cleanup.reasoningCutOff = true
        await rewrite(makePipeline())
        XCTAssertEqual(paste.pasted, ["the export button does nothing"], "None of the model's output is pasted")
        XCTAssertEqual(store.entries.first?.mode, "dictate")
        XCTAssertEqual(appState.status, .error(RewriteCopy.failedNotice))
    }

    func testAFailedRewriteIntoAPasswordFieldShowsOnlyTheBlock() async {
        cleanup.respond = nil
        targets.secureField = true
        await rewrite(makePipeline())
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }

    func testAFailedRewriteSavedOnlyShowsOnlyThatNotice() async {
        cleanup.respond = nil
        targets.honyakuIsFrontmost = true
        await rewrite(makePipeline())
        XCTAssertTrue(paste.pasted.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.savedWhileInFrontMessage))
    }

    func testFallbackNoticeDoesNotClaimAPaste() {
        XCTAssertFalse(RewriteCopy.failedNotice.contains("pasted"))
    }

    func testEmptyOutputIsAFailure() async {
        cleanup.respond = { _ in "  \n" }
        await rewrite(makePipeline())
        XCTAssertEqual(paste.pasted, ["the export button does nothing"])
        XCTAssertEqual(appState.status, .error(RewriteCopy.failedNotice))
    }

    func testRewriteWithoutThePlannerUsesTheDefaultTemplate() async {
        let services = PipelineServices(audioCapture: audio, transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: models, targets: targets)
        let pipeline = TranscriptionPipeline(appState: appState, transcriptStore: store, services: services,
                                             defaults: defaults)
        await rewrite(pipeline)
        XCTAssertEqual(store.entries.first?.rewriteTemplateID, "chatMessage", "Slack, by the defaults")
    }

    func testAppAtStartIsExposedForTheCapsule() {
        let pipeline = makePipeline()
        XCTAssertNil(pipeline.recordingAppAtStart)
        pipeline.startRecording()
        XCTAssertEqual(pipeline.recordingAppAtStart?.category, .chat)
        pipeline.cancelRecording()
        XCTAssertNil(pipeline.recordingAppAtStart)
    }
}

// MARK: - History and the menu bar icon

@MainActor
final class RewriteHistoryTests: XCTestCase {
    func testRewriteEntryRoundTripsAndOldEntriesDecode() throws {
        let entry = TranscriptEntry(rawText: "ship it", cleanedText: "Summary: Ship it", modelTier: "m",
                                    durationSeconds: 1, mode: "rewrite", rewriteTemplateID: "jiraTicket")
        let decoded = try JSONDecoder().decode(TranscriptEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decoded, entry)

        let old = #"{"id":"6F1C9A52-6C1F-4C34-9F66-1D7C1C7C9E10","rawText":"a","cleanedText":"A.","timestamp":0,"modelTier":"m","durationSeconds":1,"hasSpeakerLabels":false}"#
        let oldEntry = try JSONDecoder().decode(TranscriptEntry.self, from: Data(old.utf8))
        XCTAssertNil(oldEntry.rewriteTemplateID)
    }

    func testSearchMatchesTheSpokenWordsOfARewrite() {
        let rewrite = TranscriptEntry(rawText: "the flaky upload test", cleanedText: "Summary: Fix a test", modelTier: "m",
                                      durationSeconds: 1, mode: "rewrite", rewriteTemplateID: "jiraTicket")
        let dictation = TranscriptEntry(rawText: "um flaky", cleanedText: "Something else", modelTier: "m", durationSeconds: 1)
        XCTAssertEqual(TranscriptStore.filter([rewrite, dictation], matching: "flaky").map(\.id), [rewrite.id])
        XCTAssertEqual(TranscriptStore.filter([rewrite, dictation], matching: "Fix a").map(\.id), [rewrite.id])
    }

    func testVoiceOverSaysRewriting() {
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .processing, rewriting: true), "Rewriting")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .transcribing, rewriting: true), "Rewriting")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .recording, rewriting: true), "Recording")
        XCTAssertEqual(StatusItemController.accessibilityValue(for: .processing), "Cleaning up")
    }

    func testMenuChecksTheCurrentChoiceAndSetsIt() throws {
        let suite = "HonyakuRewriteMenuTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appending(path: "honyaku-tests-\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = RewriteSettings(environment: FeatureEnvironment(directory: directory, defaults: defaults))
        let menu = RewriteMenu(settings: settings)
        let submenu = try XCTUnwrap(menu.item.submenu)
        XCTAssertEqual(submenu.items.filter { !$0.isSeparatorItem }.map(\.title),
                       ["Automatic (by app)"] + RewriteTemplateID.allCases.map(\.name))
        XCTAssertEqual(submenu.items.first?.state, .on)

        let standup = try XCTUnwrap(submenu.items.first { $0.title == "Standup update" })
        _ = standup.target?.perform(standup.action, with: standup)
        XCTAssertEqual(settings.fixedTemplate, .standupUpdate)
        menu.menuNeedsUpdate(submenu)
        XCTAssertEqual(standup.state, .on)
        XCTAssertEqual(submenu.items.first?.state, .off)
    }
}
