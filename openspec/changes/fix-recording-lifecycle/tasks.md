## 1. Push-to-talk gesture (B1)

- [x] 1.1 Add `Sources/Honyaku/Services/PushToTalkGesture.swift` implementing the state machine from design Decision 1
- [x] 1.2 Add `onRecordingCancelled` to `HotkeyServiceProtocol` and `HotkeyService`; make `HotkeyService.handle` delegate to `PushToTalkGesture` and map the actions to callbacks and event pass-through/suppression
- [x] 1.3 Wire `hotkeyService.onRecordingCancelled` to `pipeline.cancelRecording()` in `HonyakuApp.startPipelineIfReady()`
- [x] 1.4 Add `HonyakuTests/PushToTalkGestureTests.swift`: quick tap → cancel; hold ≥ 300 ms → end; repeat down → suppress; busy → pass through; stale record cleared only when idle; long hold with an extra Control-only event keeps the recording; Control+Shift chord passes through

## 2. Capture tap symmetry (B2)

- [x] 2.1 In `AudioCaptureService.startCapture()`, remove any existing tap before installing, and on `engine.start()` failure remove the tap and clear buffers before rethrowing

## 3. Disconnect handling (B3)

- [x] 3.1 In `AudioCaptureService.handleDeviceChange`, ignore devices without `.audio` media
- [x] 3.2 In `TranscriptionPipeline.init`, capture `[weak self]`, hop to the main actor, cancel an active recording, then set the disconnect error

## 4. Verification

- [x] 4.1 Regenerate the project with `xcodegen generate`; run `xcodebuild test -scheme HonyakuTests`; all tests pass
- [x] 4.2 Developer: quick-tap Control, then hold Control and speak; the second press transcribes normally and the mic indicator turns off after the tap
- [ ] 4.3 Developer: with a USB or Bluetooth mic, unplug it mid-dictation; the error shows, the mic indicator turns off, and the next press records on the default mic without crashing
- [ ] 4.4 Developer: disconnect a non-audio device (or skip if none is available) while dictating; the recording continues

## 5. Short utterances

- [x] 5.1 In `TranscriptionService`, add `decodeOptions(forDurationSeconds:)` (superseded by 13.1: under 1.1 s → trim just under the clip length), read the clip duration from the WAV, and pass the options to `kit.transcribe(audioPath:decodeOptions:)`
- [x] 5.2 Unit-test `decodeOptions(forDurationSeconds:)` (updated in 13.1)
- [x] 5.3 Developer: hold Control for about 1 s and say one word, three times, and each should paste; hold about 1 s silently, and nothing should paste (the one-word part passed on 2026-09-29; the silent part is now covered by 6.3)

## 6. Non-speech annotations

- [x] 6.1 Add `TranscriptionService.stripNonSpeech(_:)` and apply it after `stripTokens` to the full text and to each timed segment
- [x] 6.2 Unit-test `stripNonSpeech`: `[BLANK_AUDIO]` → empty; `[MUSIC] send the report` → `send the report`; `(silence)` → empty; `call me (maybe) later` unchanged
- [x] 6.3 Developer: hold Control silently for about 1 s and about 3 s; nothing is pasted and no error shows

## 7. Local-first speech model loading

- [x] 7.1 Add `TranscriptionService.localModelFolder(repo:variant:)` and `isModelDownloaded(at:)` (all three `.mlmodelc` folders contain `coremldata.bin`)
- [x] 7.2 In `loadWhisperKit`, load with `WhisperKitConfig(modelFolder:, download: false)` when downloaded; otherwise, or if the local load throws, fall back to `WhisperKit(model:modelRepo:)`
- [x] 7.3 Unit-test the path helper and `isModelDownloaded` against a temp folder: complete, missing one model, missing `coremldata.bin`
- [x] 7.4 `PasteService` takes an injectable ⌘V sender; `PasteServiceTests` injects a recorder and asserts exactly one paste
- [x] 7.5 Developer: relaunch, then dictate a first word; it pastes about as fast as later words, and the logs show no huggingface.co requests
- [x] 7.6 Developer: turn Wi-Fi off, relaunch, and dictate; it transcribes normally

## 8. Push-to-talk from launch

- [x] 8.1 Switch `MenuBarExtra` to the `content:label:` form and add `.task { startPipelineIfReady() }` on the label; keep the popover `.onAppear` retry
- [x] 8.2 Verify straight after `open -n`, without opening the popover, that the event-tap list shows an enabled tap for the new PID

## 9. Faster first mic start

- [x] 9.1 Add `AudioCaptureService.prepare()` (only when mic access is authorised: touch `inputNode`, `engine.prepare()`); call it when the pipeline is created, and after `engine.stop()` in the stop and cancel paths
- [x] 9.2 Verify from the logs that the first press after launch loses no more than about 0.1 s (engine run time minus captured audio), and that no mic indicator shows while idle

## 10. Cleanup prompt

- [x] 10.1 Rewrite `CleanupService.defaultPrompt` per design Decision 9; leave saved user prompts alone
- [x] 10.2 Developer: with the new prompt in use, say "Are you working or not?", and "or not" is kept; say "um I think we should uh ship it", and the fillers are removed

## 11. Cleanup framing and content check

- [x] 11.1 Add `CleanupService.keepsContent(raw:cleaned:)` (superseded by `isFaithful`, 13.2 and 14.3), `removeUnambiguousFillers(_:)`, `stripDelimiters(_:)`; frame the user message; add the "not addressed to you" rule to the default prompt; fall back when the check fails
- [x] 11.2 Unit-test the three helpers, including the spec scenarios and `[Speaker N]` labels
- [x] 11.3 Add `CleanupIntegrationTests` ("Are you working or not?" keeps "or not"; "um I think we should uh ship it" loses the fillers); run with `INTEGRATION_TESTS=1`

## 12. Warm-up at launch

- [x] 12.1 Add `prepare` to `TranscriptionService` and `CleanupService` with in-flight load de-duplication; add `TranscriptionPipeline.warmUp()` and call it when the pipeline is created
- [x] 12.2 Verify from the logs that both models load at launch, and that the first dictation's release-to-paste time is close to later ones

## 13. Re-review fixes

- [x] 13.1 `decodeOptions`: under 1.1 s → `windowClipTime = max(0, duration − 0.1)`, otherwise nil; update its tests
- [x] 13.2 `isFaithful(raw:cleaned:)` (two-way, set-off fillers, curly apostrophes); `stripDelimiters` strips `Cleaned:`, keeps quotes that aren't just wrapping; fallback leaves hyphenated words and tidies leading punctuation; unit tests for every spec scenario
- [x] 13.3 `CleanupService.modelOutput(for:prompt:)`; integration tests assert `isFaithful` on the raw model output for held-out sentences with no overlap with the examples
- [x] 13.4 Warm-up uses `transcription.prepareIfDownloaded(modelID:)`
- [x] 13.5 Log local speech-model load failures (error type only)
- [x] 13.6 Assemble `rawText` from cleaned segments (`assembleText`); unit-test the `(clears throat)` case
- [x] 13.7 `PasteService` default sender as a closure (clears the Sendable warning)
- [x] 13.8 Disconnect handler acts on status per design Decision 12
- [x] 13.9 Re-enable the event tap and reconcile the press per design Decision 13
- [x] 13.10 Clean build with no warnings in project sources; unit and cleanup integration tests pass
- [x] 13.11 Developer: quick checks — short word, "Are you working or not?", "I like it", silent hold, first press after relaunch

## 14. Third-review fixes

- [x] 14.1 Rewrite the prompt's worked examples so they only remove what `isFaithful` allows; unit-test that each example pair passes
- [x] 14.2 Launch warm-up: local-only load (no fetch fallback), and only when the tokenizer is on disk too; a dictation that finds a failed local-only load retries with fetch allowed
- [x] 14.3 `isFaithful`: in-order check (deletions only), lookahead for chained set-off fillers, reject new line breaks/control/shell characters; unit tests
- [x] 14.4 `assembleText(windowTexts:segmentTexts:)`: keep WhisperKit's window text and cut out annotation-only segments; unit-test Japanese spacing and `(clears throat)`
- [x] 14.5 Integration tests: a bare "so" case and a set-off "like" case; held-out cases assert um/uh removed
- [x] 14.6 Clean build with no warnings; unit and cleanup integration tests pass; developer quick check

## 15. Paste timing

- [x] 15.1 `PasteService`: injectable `restoreDelay` (default 500 ms); restore only if `changeCount` is unchanged since the transcript was written
- [x] 15.2 Unit tests: previous contents restored after the delay; not restored when the clipboard changed during the wait
- [x] 15.3 Developer: the first dictation into this terminal after relaunch appears
- [x] 15.4 Restore in the background: `paste` returns after ⌘V; a pending restore is superseded by the next paste, which keeps the original clipboard; `waitForPendingRestore()` for tests
- [x] 15.5 Unit test: two pastes in quick succession restore the original clipboard, not the first transcript
- [x] 15.6 Developer: numbered test phrases dictated at a quick pace all appear
