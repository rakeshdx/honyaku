import XCTest
@testable import Honyaku

/// Never reads the real accessibility tree or secure-input state.
@MainActor
final class FakePasteGuardProbe: PasteGuardProbe {
    var reading = PasteGuardReading(focusedSubrole: "AXTextArea", secureInputOn: false, secureInputOwnerPID: nil)
    var names: [pid_t: String] = [:]
    private(set) var reads = 0

    func read() -> PasteGuardReading {
        reads += 1
        return reading
    }

    func appName(pid: pid_t) -> String? { names[pid] }
}

/// The per-app stages run through the real pipeline with fake services, a fake probe and a temporary
/// rules folder.
@MainActor
final class PerAppPipelineTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var directory: URL!
    private var appState: AppState!
    private var history: TranscriptStore!
    private var profiles: AppProfilesStore!
    private var probe: FakePasteGuardProbe!
    private var audio: FakeAudioCapture!
    private var transcription: FakeTranscription!
    private var cleanup: FakeCleanup!
    private var paste: FakePaste!
    private var targets: FakeTargets!

    private let slack = TargetApp(bundleID: "com.tinyspeck.slackmacgap", pid: 42, name: "Slack")
    private let terminal = TargetApp(bundleID: "com.apple.Terminal", pid: 7, name: "Terminal")
    private let outlook = TargetApp(bundleID: "com.microsoft.Outlook", pid: 9, name: "Microsoft Outlook")

    override func setUp() {
        super.setUp()
        suiteName = "HonyakuPerAppTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("honyaku-per-app-\(UUID().uuidString)")
        appState = AppState(defaults: defaults)
        history = TranscriptStore(inMemory: [])
        profiles = AppProfilesStore(directory: directory)
        probe = FakePasteGuardProbe()
        audio = FakeAudioCapture()
        transcription = FakeTranscription()
        cleanup = FakeCleanup()
        paste = FakePaste()
        targets = FakeTargets()
        targets.front = slack
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makePipeline() -> TranscriptionPipeline {
        let services = PipelineServices(audioCapture: audio, transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: FakeModels(), targets: targets)
        return TranscriptionPipeline(appState: appState, transcriptStore: history, services: services,
                                     stages: PerAppStages.make(store: profiles, probe: probe), defaults: defaults)
    }

    private func dictate(_ text: String, switchingTo app: TargetApp? = nil) async {
        cleanup.respond = { _ in text }
        let pipeline = makePipeline()
        pipeline.startRecording()
        if let app { targets.front = app }
        await pipeline.stopRecordingAndProcess()?.value
    }

    // MARK: - Password guard

    func testPasswordFieldBlocksPasteAndHistory() async {
        probe.reading.focusedSubrole = "AXSecureTextField"
        await dictate("hunter two")

        XCTAssertEqual(paste.pasted, [])
        XCTAssertEqual(paste.clears, 0, "nothing reached the pasteboard to clear")
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
        XCTAssertEqual(TranscriptionPipeline.passwordFieldMessage, "Not pasted: a password field is focused")
    }

    func testFrontAppOwningSecureInputIsBlocked() async {
        probe.reading = PasteGuardReading(focusedSubrole: nil, secureInputOn: true, secureInputOwnerPID: slack.pid)
        await dictate("Hello.")
        XCTAssertEqual(paste.pasted, [])
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testTerminalWithSecureKeyboardEntryPastesAndSavesWithoutNotice() async {
        targets.front = terminal
        probe.reading = PasteGuardReading(focusedSubrole: nil, secureInputOn: true, secureInputOwnerPID: terminal.pid)
        await dictate("ls -la.")

        XCTAssertEqual(paste.pasted, ["ls -la"])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(appState.status, .idle, "no notice")
    }

    func testAnotherAppOwningSecureInputPastesWithANotice() async {
        probe.reading = PasteGuardReading(focusedSubrole: "AXTextArea", secureInputOn: true, secureInputOwnerPID: 555)
        probe.names = [555: "1Password"]
        await dictate("Hello.")

        XCTAssertEqual(paste.pasted, ["Hello."])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(appState.status, .error("Pasted. Note: 1Password has secure input on"))
    }

    func testNoWarningWhenTheTextIsSavedInsteadOfPasted() async {
        var chat = profiles.profiles.rules(for: .chat)
        chat.paste = false
        profiles.profiles.setRules(chat, for: .chat)
        probe.reading = PasteGuardReading(focusedSubrole: "AXTextArea", secureInputOn: true, secureInputOwnerPID: 555)
        probe.names = [555: "1Password"]
        await dictate("Hello.")

        XCTAssertEqual(paste.pasted, [])
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(appState.status, .error("Saved to History. Slack is set not to paste"), "no \"Pasted\" warning")
    }

    func testNoWarningWhenHonyakuIsInFront() async {
        targets.front = TargetApp(bundleID: "com.honyaku.app", pid: 1, name: "Honyaku")
        targets.honyakuIsFrontmost = true
        probe.reading = PasteGuardReading(focusedSubrole: "AXTextField", secureInputOn: true, secureInputOwnerPID: 555)
        await dictate("Hello.")
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.savedWhileInFrontMessage))
    }

    func testFocusedDialogOwningSecureInputIsBlocked() async {
        probe.reading = PasteGuardReading(focusedSubrole: nil, secureInputOn: true, secureInputOwnerPID: 555,
                                          focusedPID: 555, focusedCategory: .other)
        await dictate("hunter two")
        XCTAssertEqual(paste.pasted, [])
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }

    func testUnreadableFieldFailsOpen() async {
        probe.reading = PasteGuardReading(focusedSubrole: nil, secureInputOn: false, secureInputOwnerPID: nil)
        await dictate("Hello.")
        XCTAssertEqual(paste.pasted, ["Hello."])
        XCTAssertEqual(probe.reads, 1, "read once, right before routing")
    }

    func testHonyakusOwnTokenFieldIsBlockedNotSaved() async {
        targets.front = TargetApp(bundleID: "com.honyaku.app", pid: 1, name: "Honyaku")
        targets.honyakuIsFrontmost = true
        probe.reading.focusedSubrole = "AXSecureTextField"
        await dictate("Hello.")

        XCTAssertEqual(paste.pasted, [])
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.passwordFieldMessage))
    }

    // MARK: - Formatting and routing

    func testTerminalGetsItsRules() async {
        targets.front = terminal
        await dictate("Run \u{201C}make test\u{201D} in the api folder.")

        XCTAssertEqual(paste.pasted, ["Run \"make test\" in the api folder"])
        XCTAssertEqual(history.entries.first?.cleanedText, "Run \"make test\" in the api folder")
        XCTAssertEqual(history.entries.first?.appBundleID, "com.apple.Terminal")
        XCTAssertEqual(history.entries.first?.pasted, true)
    }

    func testTerminalKeepsAStandaloneFullStop() async {
        targets.front = terminal
        await dictate("git add .")
        await dictate("um git add .")
        XCTAssertEqual(paste.pasted, ["git add .", "git add ."])
    }

    func testChatIsPastedUnchanged() async {
        await dictate("Sounds good, I\u{2019}ll ship it today.")
        XCTAssertEqual(paste.pasted, ["Sounds good, I\u{2019}ll ship it today."])
    }

    func testPasteTimeAppWins() async {
        // Started in Slack, switched to Terminal before the text was ready
        await dictate("Done.", switchingTo: terminal)
        XCTAssertEqual(paste.pasted, ["Done"])
        XCTAssertEqual(history.entries.first?.appBundleID, "com.apple.Terminal")
    }

    func testAppSetToHistoryOnlyIsSavedNotPasted() async {
        profiles.profiles.addApp(bundleID: outlook.bundleID!, displayName: "Microsoft Outlook")
        var rules = profiles.profiles.override(forBundleID: outlook.bundleID!)!.rules
        rules.paste = false
        rules.trailingSpace = true
        profiles.profiles.setRules(rules, forApp: outlook.bundleID!)
        targets.front = outlook
        await dictate("See you Monday.")

        XCTAssertEqual(paste.pasted, [])
        XCTAssertEqual(paste.clears, 0)
        XCTAssertEqual(history.entries.first?.cleanedText, "See you Monday. ", "formatted the same way")
        XCTAssertEqual(history.entries.first?.appBundleID, "com.microsoft.Outlook")
        XCTAssertEqual(history.entries.first?.pasted, false)
        XCTAssertEqual(appState.status, .error("Saved to History. Microsoft Outlook is set not to paste"))
    }

    func testPasswordGuardComesBeforeHistoryOnly() async {
        var chat = profiles.profiles.rules(for: .chat)
        chat.paste = false
        profiles.profiles.setRules(chat, for: .chat)
        probe.reading.focusedSubrole = "AXSecureTextField"
        await dictate("Hello.")
        XCTAssertTrue(history.entries.isEmpty, "blocked text isn't saved even for a History-only app")
    }

    func testHonyakuInFrontIsSavedUnformatted() async {
        var other = profiles.profiles.rules(for: .other)
        other.trailingSpace = true
        profiles.profiles.setRules(other, for: .other)
        targets.front = TargetApp(bundleID: "com.honyaku.app", pid: 1, name: "Honyaku")
        targets.honyakuIsFrontmost = true
        await dictate("Hello.")

        XCTAssertEqual(paste.pasted, [])
        XCTAssertEqual(history.entries.first?.cleanedText, "Hello.")
        XCTAssertEqual(history.entries.first?.pasted, false)
        XCTAssertEqual(appState.status, .error(TranscriptionPipeline.savedWhileInFrontMessage))
    }

    func testRuleChangesApplyToTheNextDictation() async {
        let pipeline = makePipeline()
        cleanup.respond = { _ in "Hello." }
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess()?.value
        var chat = profiles.profiles.rules(for: .chat)
        chat.finalFullStop = .drop
        profiles.profiles.setRules(chat, for: .chat)
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess()?.value

        XCTAssertEqual(paste.pasted, ["Hello.", "Hello"])
    }

    func testVocabularyTermsKeepTheirFirstLetter() async {
        var chat = profiles.profiles.rules(for: .chat)
        chat.firstLetter = .lowercase
        profiles.profiles.setRules(chat, for: .chat)
        let services = PipelineServices(audioCapture: audio, transcription: transcription,
                                        diarization: FakeDiarization(), cleanup: cleanup, paste: paste,
                                        models: FakeModels(), targets: targets)
        // RecordingPreparer puts "Paramount+" in the glossary, as the vocabulary feature will
        let stages = PipelineStages.combined([PipelineStages(preparers: [RecordingPreparer()]),
                                              PerAppStages.make(store: profiles, probe: probe)])
        let pipeline = TranscriptionPipeline(appState: appState, transcriptStore: history, services: services,
                                             stages: stages, defaults: defaults)
        cleanup.respond = { _ in "Paramount+ ships today" }
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess()?.value
        cleanup.respond = { _ in "Ships today" }
        pipeline.startRecording()
        await pipeline.stopRecordingAndProcess()?.value

        XCTAssertEqual(paste.pasted, ["Paramount+ ships today", "ships today"])
    }

    func testOlderHistoryEntriesStillDecode() throws {
        let old = #"[{"id":"6C8C1E0B-6F7A-4A5E-9E8B-3C1E2F1A0B11","rawText":"a","cleanedText":"A.","timestamp":0,"modelTier":"m","durationSeconds":1,"hasSpeakerLabels":false}]"#
        let entries = try JSONDecoder().decode([TranscriptEntry].self, from: Data(old.utf8))
        XCTAssertNil(entries.first?.pasted)
        XCTAssertNil(entries.first?.appBundleID)
    }
}
