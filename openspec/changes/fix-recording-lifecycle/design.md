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

### 4. No end-of-clip trim for clips under one decoding window

In WhisperKit's `TranscribeTask`, the decode loop runs `while seek < seekClipEnd - windowPadding`, where `windowPadding = windowClipTime × 16 kHz` (default 1.0 s).
- **Clips shorter than one 30-second window:** the first and only pass decodes the whole clip. So the trim's only effect is to skip clips of 1 s or less entirely.
- **Longer clips:** it stops a final sliver of a window from being decoded into invented text.

`TranscriptionService` reads the clip's duration from the WAV file (`AVAudioFile.length / sampleRate`). A small pure helper, `decodeOptions(forDurationSeconds:)`, returns `DecodingOptions(windowClipTime: 0)` for clips under 30 s and the default options otherwise. `transcribe(audioPath:decodeOptions:)` is called with that result.

*Alternatives considered:*
- **Pad short clips with trailing silence.** This needs a rewritten WAV, and the extra silence invites Whisper's typical invented endings ("Thank you.").
- **Set `windowClipTime: 0` for every clip.** This would change decoding of recordings over 30 s, which isn't needed to fix this bug.

### 5. Remove non-speech annotations in `TranscriptionService`

A new `static func stripNonSpeech(_:)` removes every `\[[^\]]*\]` span, then clears the text if what's left is only a parenthesised span such as `(silence)`, then collapses whitespace. It is applied after `stripTokens` to both `rawText` and each timed segment, so diarisation merging never sees the labels. An empty result already follows the pipeline's existing silent-discard path (`TranscriptionPipeline.run`).

Whisper doesn't put dictated words in square brackets, so removing every bracketed span is safe. Parentheses can appear in real speech, so they're only dropped when they make up the whole segment.

*Alternative considered:* filtering by WhisperKit's per-segment `noSpeechProb`. Rejected: the threshold would need tuning per model, and a clear `[BLANK_AUDIO]` label is simpler to rely on.

### 6. Load the speech model from the local folder when it's there

`WhisperKit.download` in the setup wizard stores models where the Hugging Face library puts them by default: `~/Documents/huggingface/models/<hfRepoPath>/<whisperVariant>`. The HubApi default `downloadBase` is `Documents/huggingface`, and `localRepoLocation` is `models/<repo id>`.

`TranscriptionService.loadWhisperKit`:
1. Builds that path, using a small static helper that the tests can cover.
2. Treats the model as downloaded when `AudioEncoder.mlmodelc`, `TextDecoder.mlmodelc` and `MelSpectrogram.mlmodelc` each contain a `coremldata.bin`. An interrupted download fails this check.
3. If it's downloaded, creates `WhisperKit(WhisperKitConfig(model:, modelRepo:, modelFolder: <path>, download: false))`. With `modelFolder` set, WhisperKit skips `download()` entirely. The tokenizer already loads local-first from `~/Documents/huggingface/models/openai/<name>/tokenizer.json`, which setup downloaded.
4. If it isn't downloaded, or the local load throws (for example a corrupt file), falls back to today's call, `WhisperKit(model:modelRepo:)`, which fetches the missing files.

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

*Alternative considered:* a code check that rejects cleanup output missing non-filler words from the raw text. Deferred: it would also reject legitimate false-start removal ("I was — I mean I went"), so it needs its own design.

### 10. Frame the transcript, then check the result in code

- **Framing:** `CleanupService.clean` sends `Transcript to clean:\n"""\n<raw>\n"""` as the user message. The default prompt gains one rule: the transcript is not addressed to the model, and it must never answer it. `stripDelimiters(_:)` removes any echoed `"""` or wrapping quotes from the reply.
- **Content check:** `keepsContent(raw:cleaned:)` lowercases both texts and removes the filler phrases ("you know", "sort of", "kind of") and single-word fillers (um, umm, uh, hmm, like, basically, literally, right, so) from the raw text. It then tokenises both into words (letters, digits, apostrophes), and requires every raw token to appear in the cleaned text at least as many times. `[Speaker N]` labels are ordinary tokens, so dropping one also fails the check.
- **Fallback:** `removeUnambiguousFillers(_:)` strips `um|umm|uh|hmm` as whole words (with a trailing comma) and tidies the spacing.

- **Worked examples:** the default prompt ends with two before/after examples. With rules alone, qwen-3b still returned "Are you working?" and "We should ship it." (dropping "I think"), so every case fell back to the raw text. With the examples, its own output kept every word on the test sentences and on four held-out sentences that share no phrasing with the examples.

All three are `static` and pure, so they're unit tested. The model itself is exercised by a new `HonyakuIntegrationTests/CleanupIntegrationTests.swift` (including held-out sentences), which runs only with `INTEGRATION_TESTS=1` and the selected cleanup model on disk.

When the fallback is used it logs `Cleanup output dropped content words; using raw transcript` (subsystem `com.honyaku.app`, category `cleanup`). The transcript itself is never logged.

**Trade-off:** a false start the model removes correctly ("I was — I mean I went" → "I went") fails the check, so the raw text is pasted instead. The check errs toward keeping the speaker's words.

### 11. Warm models at launch, and load each model once

`TranscriptionPipeline.warmUp()` runs from `startPipelineIfReady()` right after the pipeline is created, which is now at launch (Decision 7). It starts a background Task that awaits `transcription.prepare(modelID:)`, then `cleanup.prepare()` if cleanup is enabled. Errors are ignored, because a real dictation will surface them.

Both services are actors whose loaders `await` inside, so a warm-up and a dictation could otherwise both start loading. Each loader therefore keeps the in-flight load as a `Task` keyed by model ID. Concurrent callers await the same task, and a failed task is cleared so the next call retries.

**Memory:** qwen-3b (a few GB) now occupies memory from launch instead of from the first dictation. The developer accepted this.

## Risks / Trade-offs

- **[Risk] SwiftUI might not run `.task` on a `MenuBarExtra` label at launch on some macOS versions.** → Verify on the developer's Mac by checking the event-tap list straight after launch. The popover `.onAppear` retry remains as a fallback.
- **[Risk] A small model may still reword despite the prompt.** → Checked by hand with the "or not" example. The deferred code-level check is the stronger guarantee.

- **[Risk] A future WhisperKit or Hub version could store models somewhere else.** → The local check would then just fail, and loading falls back to today's fetch path. That costs speed and privacy, but nothing breaks.

- **[Risk] Very short clips (about 0.2–0.5 s) that are mostly silence could decode to an invented word.** → WhisperKit's `noSpeechThreshold` (0.6) and log-prob thresholds still apply. Check this by hand with short silent holds (task 5.3).

- **[Risk] `removeTap` on a bus with no tap may log a console warning.** → Harmless. The warning is preferable to a crash.
- **[Risk] Mapping a device to "audio" may miss an aggregate or virtual device that doesn't report `.audio`.** → Such a disconnect is simply ignored, which is the same as today but without the crash path. The engine-level failure then surfaces at the next start as a normal, recoverable error.
- **[Trade-off] The AVAudioEngine paths have no automated tests.** → They are covered by the manual verification tasks. The gesture state machine, which holds the logic most likely to regress, is unit tested.
