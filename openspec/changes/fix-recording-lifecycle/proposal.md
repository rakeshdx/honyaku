## Why

The pre-push `/review` of `fix/single-instance-accessibility` found three bugs in the recording lifecycle. Each one either leaves the microphone live with push-to-talk dead, or crashes the app. All three were already on `main`, and all three break behaviour the base specs already promise:

1. **Quick tap leaves the mic on.** Recording starts on Control key-down. A release under 300 ms is dropped without telling anyone, and `TranscriptionPipeline.cancelRecording()` has no callers. The status stays `.recording` with the mic open, and every later press is ignored as "busy". A related path: the 5-second "stale press" reset can wipe an active long hold, which ends in the same stuck state.
2. **Crash after the mic fails to start.** `AudioCaptureService.startCapture()` installs the input tap before `engine.start()` and never removes it if start throws. The next press installs a second tap on the same bus, and AVAudioEngine raises an exception that crashes the app.
3. **A disconnect mid-recording keeps the mic on, then crashes.** The disconnect observer fires for any AV device, including webcams, and only sets an error. Key-up then bails out without stopping the engine. The next press hits the double-tap crash from bug 2.

4. **Short phrases are silently dropped.** WhisperKit's default `windowClipTime` of 1.0 s means a clip of 1 s or less never reaches the decoder. The capture starts about 0.12–0.15 s after Control goes down, so any press shorter than about 1.15 s produces no text and no error. Found while verifying the fixes above: a 1.13 s press was never decoded, while 1.22 s presses were.

5. **Silence labels are pasted as text.** Whisper labels silence `[BLANK_AUDIO]`, and the app pastes that label. A 2.1 s silent hold showed this during verification, and it was already on `main` for holds over about 1.15 s. Fix 4 above also decodes shorter silent holds, so it would show up more often.

6. **The first dictation after launch contacts huggingface.co.** `WhisperKit(model:modelRepo:)` defaults to `download: true`, so every model load sends one metadata request per model file (28 for tiny.en), taking about 1.9 s. That's despite the files already being on disk, and it breaks the privacy promise that dictation stays local.

7. **Push-to-talk is dead after launch.** The Control listener is only installed when the popover opens, so after any launch (login, relaunch, or replacing an older copy) Control does nothing until the user clicks the menu bar icon. This hit three times during verification.
8. **The first press loses its opening syllable.** The audio engine's input is created on the first press and released after every recording. The first press after launch lost about 0.15 s, turning "hello" into "Oh.".
9. **Cleanup dropped meaningful words.** "Are you working or not?" became "Are you working?". The default prompt's "Fix run-on sentences into clean prose" rule invites rewording, and nothing tells the model to keep content.

10. **The prompt alone didn't stop word loss.** With the new default prompt in use, qwen-3b still returned "Are you working?" for "Are you working or not?", the same way all three times. The transcript is sent as a bare chat message, which reads as something to reply to, and a 3B model follows "keep every word" loosely.
11. **The first dictation after launch is slow.** Release to paste took 2.0 s on the first press, against 0.8 s later, because the Whisper and cleanup models are loaded on first use.

12. **Pastes into slow readers are lost.** `PasteService` restored the previous clipboard 150 ms after posting ⌘V. A terminal that read the clipboard later received the restored (empty) clipboard, so the first dictation into a terminal after launch pasted nothing. This was already on `main`.

## What Changes

- A Control press that ends without a transcription (too short, or cut short) always stops capture, releases the mic and returns to idle.
- The Control gesture logic moves into a small pure state machine that unit tests can cover. The stale-press reset never discards an active hold.
- Starting capture never leaves a tap behind. A failed start removes it, and any leftover tap is removed before a new one is installed.
- Recordings too short to reach the decoder (under 1.1 s) get a smaller end-of-clip trim, so short phrases are transcribed. Longer recordings keep WhisperKit's defaults.
- Whisper's non-speech annotations are removed before pasting; if nothing is left, the recording is treated as silence.
- If the selected speech model is already on disk, it's loaded from the local folder with downloading turned off; it's fetched only when missing.
- The Control listener is installed at launch when setup and Accessibility are ready; opening the popover still retries it.
- The audio engine's input is prepared at launch and after every recording, without turning the mic on.
- The default cleanup prompt keeps every word apart from fillers and false starts, and forbids rephrasing. A user-customised prompt is not changed.
- The transcript is sent to the cleanup model inside delimiters. A code check rejects cleanup output that loses a content word or adds any word, and falls back to the raw text with only um/umm/uh/hmm removed.
- The speech model, and the cleanup model if enabled, are loaded in the background at launch, but only if already on disk. A dictation during warm-up waits for that load.
- A disconnect while a dictation is being transcribed no longer changes the status, and the event tap is re-enabled if macOS disables it. Both could previously leave the mic on. They were found in the re-review, and the underlying code predates this branch.
- The clipboard is restored 500 ms after the paste instead of 150 ms, and not at all if the user changed the clipboard in the meantime.
- Disconnects of non-audio devices are ignored. If an audio input disconnects while a recording is running, that recording is cancelled (mic released, audio discarded) before the error is shown.

## Capabilities

### New Capabilities
<!-- none -->

### Modified Capabilities
- `text-cleanup`: adds the requirement that the default prompt never drops content. Written as ADDED.
- `privacy`: adds the requirement that a downloaded speech model loads with no network access. Written as ADDED, like the others.
- `push-to-talk`: adds the guarantee that no press can leave recording stuck on. Written as ADDED requirements, because the base spec is still inside the unarchived `honyaku-macos-app` change.
- `speech-transcription`: adds requirements for a failed microphone start, for a disconnect during an active recording, for short utterances, and for non-speech annotations, also as ADDED.

## Impact

- **Code:**
  - `Sources/Honyaku/Services/HotkeyService.swift` (gesture extracted, cancel callback added)
  - new `Sources/Honyaku/Services/PushToTalkGesture.swift`
  - `Sources/Honyaku/Services/Protocols/ServiceProtocols.swift` (`onRecordingCancelled`)
  - `Sources/Honyaku/Services/AudioCaptureService.swift` (tap symmetry, audio-only disconnects)
  - `Sources/Honyaku/Pipeline/TranscriptionPipeline.swift` (cancel on disconnect)
  - `Sources/Honyaku/Services/TranscriptionService.swift` (per-clip decoding options, annotation removal, local-first model loading)
  - `Sources/Honyaku/Services/PasteService.swift` (the ⌘V sender can be injected, so tests don't type into other apps; the restore delay is longer, and the restore is skipped if the clipboard changed)
  - `Sources/Honyaku/App/HonyakuApp.swift` (wires the cancel callback; starts the pipeline at launch)
  - `Sources/Honyaku/Services/CleanupService.swift` (default prompt, framing, faithfulness check and fallback, launch warm-up)
- **Tests:** new `HonyakuTests/PushToTalkGestureTests.swift`, unit tests for the cleanup content check, a cleanup integration test using the downloaded model, plus unit tests for the decoding-option choice and for removing annotations. The AVAudioEngine paths are verified by hand.
- **Out of scope** (flagged in the review, left for later):
  - the `pcmBuffers` cross-thread race
  - partial model downloads
  - SpeakerKit's own model check, and `ModelStore.isDownloaded` reporting every speech model as downloaded
  - network calls at transcription time
