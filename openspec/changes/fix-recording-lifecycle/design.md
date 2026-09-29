## Context

A push-to-talk press flows like this:

1. `HotkeyService.handle` receives Control `flagsChanged` events from a CGEventTap on the main run loop.
2. It calls `onRecordingStarted` on key-down and `onRecordingEnded` on release.
3. `TranscriptionPipeline` (`@MainActor`) turns those calls into `AudioCaptureService.startCapture()` / `stopCaptureAndFlushBoth()`.
4. `AppState.status` gates repeat presses through `isBusy` (`.recording`, `.transcribing`, `.processing`).

`cancelRecording()` exists but has no callers. The review found three ways this flow leaves capture running or crashes; see the proposal for the details.

## Goals / Non-Goals

**Goals:**
- Every started recording ends in either transcription or cancellation.
- `startCapture()` is safe to call again after any failure.
- A mic disconnect during a recording cancels it cleanly, and disconnects of devices without audio are ignored.
- The gesture logic gets unit tests.
- Every recording that passes the 300 ms hold reaches the speech decoder.

**Non-Goals:**
- Re-enabling the event tap after macOS disables it.
- The `pcmBuffers` cross-thread race.
- Following a specific selected mic across device changes.

These are separate findings from the review.

## Decisions

### 1. A pure `PushToTalkGesture` state machine

`HotkeyService.handle` currently mixes event decoding, timing and side effects, which is why the dropped-release path went unnoticed. The timing logic moves into a value type:

```swift
struct PushToTalkGesture {
    enum Action { case start, end, cancel, suppress, passThrough }
    mutating func controlChanged(controlDown: Bool, otherModifiers: Bool,
                                 now: Date, pipelineBusy: Bool) -> Action
}
```

The rules:
- **Bare Control down:**
  - If a press is already in progress and it is fresh (5 s or less), or the pipeline is busy, return `.suppress`. A stale press record is only cleared when the pipeline is idle, i.e. when a key-up was genuinely missed. So an active long hold can never be discarded.
  - Otherwise, if the pipeline is busy, return `.passThrough`.
  - Otherwise, record `now` and return `.start`.
- **Control released while a press is in progress:** clear the record. Return `.end` if the hold lasted at least 0.3 s, otherwise `.cancel`.
- **Anything else:** `.passThrough`. This includes Control combined with Command, Option or Shift, which keeps the existing chord behaviour.

`HotkeyService` maps the actions onto the event tap:
- `.start` calls `onRecordingStarted` and suppresses the event.
- `.end` calls `onRecordingEnded` and suppresses the event.
- `.cancel` calls a new `onRecordingCancelled` and suppresses the event.
- `.suppress` returns nil.
- `.passThrough` returns the event.

The callbacks are still dispatched to main, as today. `onRecordingCancelled` is added to `HotkeyServiceProtocol`, and `HonyakuApp` wires it to `pipeline.cancelRecording()`. `cancelRecording()` acts only when `status == .recording`. When the mic failed to start, a quick tap would otherwise overwrite the error with idle.

*Alternative considered:* calling `onRecordingEnded` for short presses and letting the pipeline check the duration. Rejected: it spreads the timing rule across two types, and the pipeline would transcribe noise-only audio.

### 2. The capture tap is always balanced

`startCapture()`:
1. Calls `input.removeTap(onBus: 0)` before `installTap`. This is a no-op when no tap exists, and it removes one left behind by any earlier failure.
2. Wraps `try engine.start()`. On failure it calls `removeTap` and clears the buffers, then rethrows.

The fix sits in the service, where the tap is owned, so every caller is protected.

### 3. Disconnect handling: audio devices only, and cancel the active recording

- **`AudioCaptureService.handleDeviceChange`:** reads `notification.object as? AVCaptureDevice` and ignores it unless `hasMediaType(.audio)`.
- **`TranscriptionPipeline`:** the disconnect closure captures `[weak self]` and hops to the main actor. If `status == .recording`, it calls `cancelRecording()`, then sets the existing disconnect error. The later key-up finds `status != .recording` and does nothing, which is now correct because capture has already stopped.
- The next press starts a fresh `AVAudioEngine` input session on the current default device (see Decision 2).

### 4. Shrink the end-of-clip trim only for clips too short to decode

In WhisperKit's `TranscribeTask`, the decode loop runs `while seek < seekClipEnd - windowPadding`, where `windowPadding = windowClipTime × 16 kHz` (default 1.0 s). A clip of 1 s or less therefore never reaches the decoder.

After each pass, `SegmentSeeker` advances `seek` only to the last complete timestamp (`seek += lastTimestampSamples`). So even a clip under 30 s can take more than one pass. The trim is what stops a trailing sliver from being decoded on its own, which is where Whisper tends to invent words ("Thank you."). An earlier version of this design set `windowClipTime: 0` for every clip under 30 s. The re-review showed that exposed exactly that sliver, so it was narrowed.

`decodeOptions(forDurationSeconds:)` now works like this:
- **Clips under 1.1 s:** returns `DecodingOptions(windowClipTime: max(0, duration − 0.1))`. The first pass always runs (0 < 0.1 s), and a second pass would need more than `duration − 0.1` s left after the first timestamp, which can't realistically happen.
- **Clips of 1.1 s or more:** returns nil, i.e. WhisperKit's defaults, unchanged from before this change.

`TranscriptionService` reads the duration from the WAV (`AVAudioFile.length / sampleRate`).

*Alternatives considered:*
- **Pad short clips with trailing silence.** This needs a rewritten WAV, and the silence invites the same invented words.
- **`windowClipTime: 0` for all clips under 30 s.** Rejected by the re-review, as above.

### 5. Remove non-speech annotations in `TranscriptionService`

A new `static func stripNonSpeech(_:)` removes every `\[[^\]]*\]` span, then clears the text if what's left is only a parenthesised span such as `(silence)`, then collapses whitespace. It is applied after `stripTokens` to each timed segment. `rawText` is then assembled from the cleaned segments (`assembleText(_:)`), so a segment that is only `(clears throat)` disappears even in the middle of a longer transcript. When WhisperKit returns no timed segments, the window text is cleaned the same way instead. An empty result already follows the pipeline's existing silent-discard path (`TranscriptionPipeline.run`).

Whisper doesn't put dictated words in square brackets, so removing every bracketed span is safe. Parentheses can appear in real speech, so they're only dropped when they make up the whole segment.

*Alternative considered:* filtering by WhisperKit's per-segment `noSpeechProb`. Rejected: the threshold would need tuning per model, and a clear `[BLANK_AUDIO]` label is simpler to rely on.

### 6. Load the speech model from the local folder when it's there

`WhisperKit.download` in the setup wizard stores models where the Hugging Face library puts them by default: `~/Documents/huggingface/models/<hfRepoPath>/<whisperVariant>`. The HubApi default `downloadBase` is `Documents/huggingface`, and `localRepoLocation` is `models/<repo id>`.

`TranscriptionService.loadWhisperKit`:
1. Builds that path, using a small static helper that the tests can cover.
2. Treats the model as downloaded when `AudioEncoder.mlmodelc`, `TextDecoder.mlmodelc` and `MelSpectrogram.mlmodelc` each contain a `coremldata.bin`. An interrupted download fails this check.
3. If it's downloaded, creates `WhisperKit(WhisperKitConfig(model:, modelRepo:, modelFolder: <path>, download: false))`. With `modelFolder` set, WhisperKit skips `download()` entirely. The tokenizer already loads local-first from `~/Documents/huggingface/models/openai/<name>/tokenizer.json`, which setup downloaded.
4. If it isn't downloaded, or the local load throws (for example a corrupt file), falls back to today's call, `WhisperKit(model:modelRepo:)`, which fetches the missing files. A local load failure is logged with its error type only (`com.honyaku.app` / `transcription`).

*Alternative considered:* recording the download folder when setup finishes. Rejected: models downloaded by earlier builds wouldn't have that record, and the Hub layout already determines the path.

**Test side-fix:** `PasteService` takes its ⌘V sender as an injected closure, which defaults to the real `CGEvent` post. The hosted unit tests now run with Accessibility granted, so `PasteServiceTests` was typing "transcribed text" into whatever app was in front. The tests now inject a recorder.

### 7. Start the pipeline from the menu bar label

`MenuBarExtra("Honyaku", systemImage:)` becomes the `content:label:` form, and the label (the menu bar icon) gets `.task { startPipelineIfReady() }`. The label is rendered at launch, while the popover content only appears when clicked, so this runs `startPipelineIfReady()` once at launch. The popover's existing `.onAppear` stays as the retry for a late Accessibility grant, and `.onChange(of: setupComplete)` stays too. `startPipelineIfReady()` is already safe to call more than once: it creates the pipeline once, and `hotkeyService.start()` returns early if the listener is running.

*Alternative considered:* an `NSApplicationDelegateAdaptor` with `applicationDidFinishLaunching`. Rejected: the pipeline, `AppState` and hotkey service live in the SwiftUI `App` struct, so the delegate couldn't reach them without restructuring.

### 8. Prepare the audio engine without starting it

`AudioCaptureService.prepare()`:
- does nothing unless microphone access is authorised
- otherwise touches `engine.inputNode`, which creates the input device aggregate (the `agg device` log lines on the first press), and calls `engine.prepare()`

The pipeline calls it when it is created, which now happens at launch (Decision 7). The stop and cancel paths call it again after `engine.stop()`, because `stop()` releases prepared resources. `prepare()` allocates resources but starts no audio input, so the mic indicator stays off.

**How it's measured:** captured-audio length compared with how long the engine ran. On the first press this was 0.38 s of audio from a 0.53 s run, a loss of about 0.15 s. Later presses lost about 0.10 s. The target is for the first press to match later presses. Hardware warm-up of about 0.1 s stays: removing it would need the mic always on, which the privacy spec rules out.

### 9. Cleanup prompt: keep every word

The new `CleanupService.defaultPrompt`:
- drops "Fix run-on sentences into clean prose"
- adds an explicit rule to keep every word in order apart from listed fillers and false starts, and never to drop, shorten, summarise or rephrase, with "or not" as the example
- limits other edits to punctuation and capitalisation
- says a filler word is removed only when it's used as filler, since "like" in "I like it" is content

Saved user prompts in `UserDefaults["cleanupPrompt"]` are not touched. "Reset to Default" already uses `CleanupService.defaultPrompt`.

*Alternative considered:* relying on the prompt alone. Rejected after testing, see Decision 10.

### 10. Frame the transcript, then check the result in code

- **Framing:** `CleanupService.clean` sends `Transcript to clean:\n"""\n<raw>\n"""` as the user message. The default prompt gains one rule: the transcript is not addressed to the model, and it must never answer it. `stripDelimiters(_:)` removes any echoed `"""` or wrapping quotes from the reply.
- **Faithfulness check:** `isFaithful(raw:cleaned:)` checks both directions.
  - `required` = the words of the raw text after removing always-removable fillers (um/umm/uh/hmm) and set-off ambiguous fillers. An ambiguous filler (like, so, right, basically, literally, you know, sort of, kind of) is set off when followed by a comma and preceded by a comma or a sentence start.
  - Every required word must appear in the cleaned text, at least as many times.
  - Every cleaned word must appear in the full raw text, at least as many times, so the model can't add words.
  - Tokens are lowercased runs of letters, digits and apostrophes, with ’ normalised to '. `[Speaker N]` labels are ordinary tokens.
- **Fallback:** `removeUnambiguousFillers(_:)` strips `um|umm|uh|hmm` as whole words, but not inside hyphenated words like "uh-huh". It then tidies spacing and any leading punctuation left behind.
- **Delimiters:** `stripDelimiters(_:)` also removes a leading `Cleaned:` label echoed from the examples. Wrapping quotes are removed only when there are no other quotes inside, so a dictated quotation survives.
- **Worked examples:** the default prompt ends with two before/after examples. With rules alone, qwen-3b still returned "Are you working?" and "We should ship it." (dropping "I think"), so every case fell back to the raw text. With the examples, the fallback stopped firing. The integration tests now check the model's own output (`modelOutput(for:prompt:)`) against `isFaithful` directly, on held-out sentences that share no words with the examples, so a fallback can't mask a failure.

All three are `static` and pure, so they're unit tested. The model itself is exercised by `HonyakuIntegrationTests/CleanupIntegrationTests.swift`, which asserts on the raw model output, which runs only with `INTEGRATION_TESTS=1` and the selected cleanup model on disk.

When the fallback is used it logs `Cleanup output dropped content words; using raw transcript` (subsystem `com.honyaku.app`, category `cleanup`). The transcript itself is never logged.

**Trade-off:** a false start the model removes correctly ("I was — I mean I went" → "I went") fails the check, so the raw text is pasted instead. The check errs toward keeping the speaker's words.

### 11. Warm models at launch, and load each model once

`TranscriptionPipeline.warmUp()` runs from `startPipelineIfReady()` right after the pipeline is created, which is now at launch (Decision 7). It starts a background Task that awaits `transcription.prepareIfDownloaded(modelID:)`, then `cleanup.prepare()` if cleanup is enabled. The speech model is loaded only if it's already on disk, so warm-up never starts a download. The cleanup loader is local-only already. Errors are ignored, because a real dictation will surface them.

Both services are actors whose loaders `await` inside, so a warm-up and a dictation could otherwise both start loading. Each loader therefore keeps the in-flight load as a `Task` keyed by model ID. Concurrent callers await the same task, and a failed task is cleared so the next call retries.

**Memory:** qwen-3b (a few GB) now occupies memory from launch instead of from the first dictation. The developer accepted this.

### 12. Disconnect while a dictation is in flight

The disconnect handler now acts on the status:
- `.recording`: cancel the recording, then show the error.
- `.idle` or `.error`: show the error.
- `.transcribing` or `.processing`: do nothing. The in-flight run owns the status, and overwriting it with `.error` made `isBusy` false, so the next press started a recording that the old run's status writes then clobbered, leaving the mic on.

### 13. Re-enable the event tap and reconcile the press

When `HotkeyService.handle` receives `.tapDisabledByTimeout` or `.tapDisabledByUserInput`, it:
1. Calls `CGEvent.tapEnable(tap:enable: true)`.
2. Reads the live modifier state with `CGEventSource.flagsState(.combinedSessionState)`.
3. Feeds that state through `PushToTalkGesture.controlChanged` as if it were a flags event.

If Control was released while the tap was off, the gesture returns `.end` or `.cancel` by hold duration, and the missed release is handled normally. If Control is still held, it returns `.suppress` and the recording continues.

## Risks / Trade-offs

- **[Risk] The tap-disabled path can't be triggered by hand.** → The reconcile logic reuses the unit-tested gesture state machine; only the wiring is untested.
- **[Trade-off] The strict faithfulness check rejects legitimate rewrites** (contractions, numbers written as digits, a false start removed). → Those cases paste the raw words minus um/uh/hmm, which errs toward keeping what was said.

- **[Risk] SwiftUI might not run `.task` on a `MenuBarExtra` label at launch on some macOS versions.** → Verify on the developer's Mac by checking the event-tap list straight after launch. The popover `.onAppear` retry remains as a fallback.
- **[Risk] A small model may still reword despite the prompt.** → The faithfulness check (Decision 10) catches it and pastes the speaker's words instead.

- **[Risk] A future WhisperKit or Hub version could store models somewhere else.** → The local check would then just fail, and loading falls back to today's fetch path. That costs speed and privacy, but nothing breaks.

- **[Risk] Very short clips (about 0.2–0.5 s) that are mostly silence could decode to an invented word.** → WhisperKit's `noSpeechThreshold` (0.6) and log-prob thresholds still apply. Check this by hand with short silent holds (task 5.3).

- **[Risk] `removeTap` on a bus with no tap may log a console warning.** → Harmless. The warning is preferable to a crash.
- **[Risk] Mapping a device to "audio" may miss an aggregate or virtual device that doesn't report `.audio`.** → Such a disconnect is simply ignored, which is the same as today but without the crash path. The engine-level failure then surfaces at the next start as a normal, recoverable error.
- **[Trade-off] The AVAudioEngine paths have no automated tests.** → They are covered by the manual verification tasks. The gesture state machine, which holds the logic most likely to regress, is unit tested.
