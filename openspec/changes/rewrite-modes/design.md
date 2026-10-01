## Context

Plain dictation is word for word: the cleanup model may only delete fillers, and `CleanupService.isFaithful` rejects anything else (new words, reordering, line breaks, shell metacharacters). Rewrite is a second, explicitly chosen mode where the model *is* allowed to restructure what was said into a format.

This change builds on `dictation-stages` (merged in PR #7). It plugs into:
- `DictationMode` (in `Pipeline/DictationContext.swift`), which gains `.rewrite`
- `HotkeyServiceProtocol.onRecordingStarted(DictationMode)` and `onRecordingEnded(DictationMode)`, and `TranscriptionPipeline.stopRecordingAndProcess(mode:)`, where the mode at release wins
- `DictationContext`: `appAtStart`, `appAtPaste`, `cleanupRules` (vocabulary's terms), `notices`, `englishFillers`
- `CleanupRequest(systemPrompt:extraRules:faithfulness:maxTokens:englishFillers:)` and the pipeline's `llmStage`
- `Pipeline/Stages/RewriteStages.swift`, the feature's own slot for a preparer and a final stage
- `FeatureEnvironment.store(_:)` for the feature's settings
- `TranscriptEntry.mode`

`custom-vocabulary` and `per-app-behaviour` are built in parallel with this change, in their own worktrees, and may merge in either order around it. Rewrite therefore depends on neither: it reads vocabulary terms only through `DictationContext.cleanupRules`, and it carries its own terminal line join (Decision 6).

Facts this design relies on:
- **The event tap** listens only to `flagsChanged`, as a `.defaultTap` created under Accessibility (`HotkeyService.start`). An active tap under Accessibility may also receive `keyDown` and mouse-down events, so no new permission is needed. This is verified in task 2.1.
- **Recording starts at Control key-down** (`PushToTalkGesture.controlChanged` → `.start`). Today, Control with any other modifier returns `.passThrough`: Shift pressed before Control never starts a recording, and Shift pressed after Control leaves a plain recording running.
- **Measured on an M3 Max** (mlx, 4-bit, temperature 0): Qwen3-1.7B ~153 tok/s, Qwen3-4B-2507 ~73 tok/s; prompt processing 160–400 tok/s. A 75-word dictation rewritten as a Jira ticket came to about 250 tokens. With a generous cap, the 4B model kept generating up to the cap, so caps matter.
- **mlx-swift-lm has no grammar or constrained decoding.** Streaming is available but isn't needed: the paste is a single block.

## Goals / Non-Goals

**Goals**
- Control+Shift, pressed in either order, rewrites with the template chosen for the app; plain Control is unchanged.
- Holding Control for a shortcut never turns into a transcription.
- Rewrites never invent facts, and a failure never loses the user's words.
- Rewrites into terminals can't run anything by themselves.

**Non-Goals**
- Custom templates, a separate rewrite model, preview before paste, per-app (not per-category) template mapping, browser-site detection, Markdown by default.

## Decisions

### 1. Gesture state machine

`PushToTalkGesture` keeps its timing rules (300 ms minimum hold, 5 s stale reset, busy guard) and gains a mode and two cancel paths. It stays a pure struct, fed by `HotkeyService` with just the information below:

- `flagsChanged(control:shift:commandOrOption:now:busy:)`
- `keyDown(now:)`
- `mouseDown(now:)`

| State | Event | Action |
|---|---|---|
| idle | Control goes down, with no Command or Option held (Shift may or may not be held) | `.start`, swallow the event. `sawShift = shift` |
| idle | Control goes down with Command or Option held | `.passThrough` (unchanged) |
| idle, pipeline busy | Control goes down | `.passThrough` (unchanged) |
| holding | Shift goes down or up | `sawShift = true` on down. Event passes through with Control cleared from its flags (Decision 9). Recording continues |
| holding | Command or Option goes down | `.cancel(.chord)`. Event passes through. The Control release that follows passes through too |
| holding | `keyDown` (any non-modifier key) | `.cancel(.key)`. Event passes through unchanged. The Control release passes through |
| holding | left, right or other mouse-down | `.cancel(.click)`. Event passes through. The Control release passes through |
| holding | Control goes up, held ≥ 300 ms | `.end(mode: sawShift ? .rewrite : .dictate)`, swallow |
| holding | Control goes up, held < 300 ms | `.cancel(.tooShort)`, swallow (unchanged) |
| cancelled hold | Control goes up | `.passThrough`, back to idle (Decision 9) |

Rules that follow from the table:
- The mode is the union of what was seen during the hold. Shift before Control, Shift after Control, and Shift released before Control all give a rewrite. Nothing is decided at key-down, so a plain-Control dictation starts exactly as fast as today.
- Command and Option still mean "this is a shortcut". They used to let the recording carry on; they now cancel it, which matches the new key-press rule. Control+Option stays free for VoiceOver and window managers.
- Every cancel stops capture and releases the microphone (`onRecordingCancelled`), with no transcription and no error. A cancel is silent.
- `keyDown` and mouse-down events arriving while idle return straight away with no state change. The callback reads only the event *type*, never `keyboardEventKeycode`, characters or the mouse location, and never delays or alters the event.
- Recovery after macOS disables the tap is unchanged: it replays `flagsState`. A key press that happened while the tap was disabled isn't seen, so that hold ends normally.
- The 5 s stale rule and the busy guard apply in both modes.

`HotkeyService`'s event mask gains `keyDown`, `leftMouseDown`, `rightMouseDown` and `otherMouseDown`. If macOS refuses a tap with that mask, the service falls back to the flags-only mask, so push-to-talk keeps working without the key and click cancel.

Callbacks:
- `onRecordingStarted(mode)`: `.rewrite` when Shift is already down at Control-down, otherwise `.dictate`. The mode can still change before release.
- `onRewriteHint()`: Shift seen for the first time during a hold that started as dictation. It updates the capsule's label.
- `onRecordingEnded(mode)`: the final mode, from the union of what was seen. The pipeline uses it (`stopRecordingAndProcess(mode:)`).
- `onRecordingCancelled()`: every cancel.

*Alternatives considered:* deciding the mode at key-down, which forces an order and adds a wait; tap-then-hold Control, which is slower and conflicts with macOS's "Press Control twice" Dictation shortcut; Right Option, which MacBook keyboards make awkward and which is a separate key to learn. A long-hold exemption from the key-press cancel was rejected (Q16): it would bring back long shortcut holds being transcribed.

### 2. Template selection

`RewriteTemplateID`: `jiraTicket`, `chatMessage`, `email`, `commitMessage`, `prDescription`, `agentPrompt`, `standupUpdate`.

The template is resolved when the recording **ends**, from the app that was in front when it **started** (`DictationContext.appAtStart.category`). A preparer in `RewriteStages` does this: for a `.rewrite` dictation it puts a `RewritePlan` (the template and its prompt) on `DictationContext.rewrite`, which `llmStage` then runs:
1. If the user picked a fixed template under "Rewrite as" (the right-click menu or the Rewrite tab), use it. It sticks until set back to Automatic.
2. Otherwise, use the template mapped to the category. Defaults:

| Category (from `AppCategory`) | Template |
|---|---|
| chat (Slack, Teams) | Chat message |
| terminal, codeEditor | Coding-agent prompt |
| email (Outlook, Mail) | Email |
| browser, other | Jira ticket |

The mapping is per category (editable in the Rewrite tab), not per app. When the app at start is unknown (no frontmost app), use `other`.

The capsule shows the resolved template as soon as Shift is seen, resolved against the app at start. A template chosen under "Rewrite as" applies to the next hold, never to one already in progress.

### 3. The seven templates

Each rewrite is sent as a system prompt and a user message:
- **System prompt:** the shared rules followed by the template's prompt.
- **User message:** the dictation inside delimiters, like cleanup's frame: `Dictation to rewrite:\n"""\n…\n"""`.

Delimiters and a `Rewrite:` label echoed back by the model are stripped. The template prompt is what the user edits; the shared rules are not editable, so editing a template can't remove the no-invention rule.

**Shared rules (prepended to every template, not editable):**
```
You turn dictated speech into a written format. Follow these rules:
- Use only what the speaker said. Never invent names, numbers, dates, links, ticket IDs or facts.
- If the format needs something the speaker didn't say, write TBD.
- Keep every name, product, file, function and command exactly as spoken.
- Write plain text. Use labels followed by a colon, "- " for bullets, and blank lines between sections. No Markdown headings, bold or code fences.
- Output only the rewritten text, with no introduction or comment.
```
Conditional lines are added when they apply:
- Vocabulary (`CleanupRequest.extraRules`): "Write these terms exactly as listed: …"
- When the dictation contains `[Speaker N]` labels: "The dictation has speaker labels. Use them to know who said what, but don't include the labels in the output." Following the cleanup lesson (an unconditional label rule made Qwen3-4B answer "[Speaker 1]"), this line is added only when labels are present.

**Template prompts (defaults, editable):**

Jira ticket:
```
Rewrite the dictation as a Jira ticket in exactly this layout, starting each section with its label:

Summary: one line

Description: what the problem or request is, in a few sentences

Acceptance criteria:
- what must be true when this is done, one bullet each

Only if the speaker described steps to reproduce, add "Steps to reproduce:" with numbered steps after the description. Every acceptance criterion must come from what the speaker said; add none of your own.
```

Chat message:
```
Rewrite the dictation as a chat message to a colleague: one to three short sentences, plain and friendly. No greeting or sign-off unless the speaker said one.
```

Email:
```
Rewrite the dictation as an email body: a short greeting, then short paragraphs, then a sign-off such as "Thanks," with no name after it. No subject line.
```

Commit message:
```
Rewrite the dictation as a git commit message: a subject line in the imperative mood, under 72 characters, with no full stop. If the speaker described more than the subject covers, add a blank line and a short body.
```

PR description:
```
Rewrite the dictation as a pull request description in exactly this layout, starting each section with its label:

Summary: one or two sentences

Changes:
- one bullet per change the speaker described

Testing: how the speaker said it was tested, or TBD
```

Coding-agent prompt:
```
Rewrite the dictation as one clear paragraph of instructions for a coding agent, written in the second person ("Add…", "Make sure you…"). Keep every file, function, command and error message the speaker named, exactly as spoken.
```

Standup update:
```
Rewrite the dictation as a standup update in exactly this layout, starting each section with its label:

Yesterday:
- one bullet per thing done

Today:
- one bullet per thing planned

Blockers:
- one bullet per blocker, or "None" if the speaker mentioned none
```

The three sectioned templates spell out their layout. With the plainer wording first drafted ("with these sections: Summary: one line…"), Qwen3-4B dropped the labels and invented steps and acceptance criteria in the integration test; with the layout it keeps the labels and adds none.

Edited prompts are stored only when they differ from the default ("Reset to default" removes the stored copy), the same pattern as `cleanupPrompt`.

### 4. Generation

- **Model:** the selected cleanup model (`selectedCleanupModelID`), loaded through `CleanupService` with the same single-flight load and thinking off for Qwen3-1.7B. There is no separate rewrite model.
- **Request:** `CleanupRequest(systemPrompt: shared + template, extraRules: DictationContext.cleanupRules, faithfulness: .none, maxTokens: cap)`, temperature 0, through the pipeline's `llmStage`. Two request fields make the call a rewrite rather than a cleanup: `transcriptLabel` ("Dictation to rewrite:", where cleanup uses "Transcript to clean:") and `speakerLabelRule` (Decision 3's line, where cleanup keeps the labels). With `faithfulness: .none`, empty output comes back empty rather than as the transcript, so the pipeline can treat it as a failure.
- **Output cap:** `min(templateCap, 150 + 3 × estimated input tokens)`, with input tokens estimated as words × 4/3 plus one per character of a script written without spaces (Han, kana, Thai, Lao, Khmer, Myanmar). See Decision 9.

| Template | Cap (tokens) |
|---|---|
| Commit message | 200 |
| Chat message | 300 |
| Standup update | 300 |
| Coding-agent prompt | 400 |
| Jira ticket | 700 |
| PR description | 700 |
| Email | 700 |

- **Timeout:** 60 s, the same task-group race as cleanup. A timeout invalidates the prompt cache.
- **Prompt cache:** keyed by model and full system prompt, holding up to three prompts (dictation plus the two most recent templates), so switching between dictation and a rewrite doesn't reprocess the system prompt each time. See Decision 9.
- **Output:** trimmed, with echoed delimiters or labels stripped: a leading heading line naming a template ("Rewritten chat message:", "Jira ticket:", "Here is your Jira ticket:"), a line copied from the prompt itself, the dictation label, a "Rewritten:" label, and spaces at the ends of lines. Generic first lines are kept (Decision 9). An empty result counts as a failure, and so does reasoning cut off by the cap (an unclosed `<think>`).
- **Filler removal:** the pipeline's English um/uh pass runs only on dictation and on the fallback text, never on rewrite output: it collapses runs of whitespace, which would join the sections.
- **Faithfulness:** the `isFaithful` check is not run for rewrites; the newline, control-character and metacharacter rule is not applied either. The output paths that need protection are covered by Decision 6.
- **Cleanup toggle:** affects only `.dictate`. A rewrite always uses the model, even with cleanup off.
- **Diarization:** runs as configured, before the LLM stage. Labels are handled as in Decision 3.

### 5. Fallbacks

The fallback text is the dictation as it would have been without any model: the transcript after vocabulary replacements and unambiguous-filler removal (um, umm, uh, hmm; English only). A failed rewrite does not trigger a second model call for word-for-word cleanup: the model just failed, and a second call doubles the wait.

| Situation | Pasted | Status message |
|---|---|---|
| No cleanup model downloaded | the fallback text | "To use Rewrite, download a cleanup model in Settings > Models" (no download is started: the user may have chosen not to use one) |
| Model error, empty output, cut-off reasoning or 60 s timeout | the fallback text | "Couldn't rewrite: used your words as dictated" |
| Output cut off at the cap | the rewrite, trimmed to its last complete line or sentence | "The rewrite was cut short" |

Both messages use the "notice" style introduced for "Saved to History — Honyaku was in front": they show on the capsule, the icon and the General tab, and clear at the next dictation. The History entry is saved with `mode: .dictate`, so it reads as what it is.

### 6. Terminals and per-app formatting

Per-app formatting rules (from `per-app-behaviour`) are applied to rewrite output exactly as to dictation, using the app in front **at paste time** (Q14, Q28).

For the Terminals category that means joining the lines:
- every run of line breaks and surrounding whitespace becomes a single space
- leading and trailing whitespace is trimmed, so there's never a trailing line break
- dropping the final full stop and straight quotes follow the category's rules

Nothing else is stripped: backticks, `$` and the like stay, because a single line runs nothing until the user presses Return (Q23).

Because the three features are built in parallel, Rewrite carries a minimal `TerminalOneLine` stage in `RewriteStages.final`. It is active only for a `.rewrite` dictation whose app at paste time is a terminal. `PipelineStages.live` runs Rewrite's final stages before Per-app's, so once `per-app-behaviour` is merged its terminal rules run on the joined line, and that change may delete `TerminalOneLine` when its own join covers rewrites. The text-cleanup scenario is satisfied either way.

### 7. UI

- **Capsule:**
  - While recording, once Shift is seen: "Rewriting as Jira ticket", next to the level meter and timer.
  - While processing: "Rewriting as Jira ticket…" in place of "Transcribing…".
  - No middle-dot separators. Template display names are used in sentence case ("Rewriting as chat message", "Rewriting as coding-agent prompt").
- **Menu bar icon:** the processing symbol is unchanged. VoiceOver reads "Honyaku, Rewriting" while a rewrite is generating.
- **Where the label comes from:** `AppState.rewriteTemplate` holds the template of the hold or run in progress. `AppCoordinator` sets it when a hold becomes a rewrite, resolving it against the app the recording started with (`TranscriptionPipeline.recordingAppAtStart`) and the same settings the preparer uses. It clears it when the status is no longer busy. The capsule and the status item read it.
- **Right-click menu:**
  - The order is "Settings…", "Rewrite as" ▸, a separator, then "Quit Honyaku".
  - "Rewrite as" contains Automatic (by app), a separator, then the seven templates.
  - The current choice is checkmarked.
- **Settings > Rewrite tab** (its own view file; tab order General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy):
  - An intro line: "Hold Control+Shift to rewrite what you say in a format for where it's going."
  - **Rewrite as:** Automatic (by app) or a template. This is the same setting as the menu.
  - **Templates by app:** one picker per category, for Chat apps, Email, Terminals, Code editors, Browsers and Everything else.
  - **Templates:** the seven templates, each with a one-line description and an Advanced disclosure holding the editable prompt and "Reset to default".
  - **Model note:**
    - If Qwen3-1.7B is selected: "Qwen3-1.7B is fast but writes weaker rewrites. Qwen3-4B is better for this." with a button to the Models tab (the Settings window selects a tab on the `showSettingsTab` notification).
    - If no cleanup model is downloaded: "Rewrite needs a cleanup model." with the same button.
- **General tab:** under "Hold Control to talk", the line "Hold Control+Shift to rewrite as a Jira ticket, chat message, email and more."
- **History:**
  - A rewrite row shows the rewritten text, a "Rewritten as Jira ticket" caption, and a "Your words" disclosure with the spoken transcript.
  - Copy copies the rewrite.
  - Search matches both texts (`TranscriptStore.filter` also matches `rawText` for rewrite entries).
  - `TranscriptEntry` gains an optional `rewriteTemplateID`. `mode` comes from the groundwork, and old entries decode as dictation.
- **First run:** unchanged.
- **Last tab:** the Settings window now remembers its last tab in the app's settings store (`FeatureEnvironment.defaults`) rather than `UserDefaults.standard`. In the app they're the same; in UI-test launches it's the separate test suite, so the Rewrite tab UI test never changes the user's saved tab.

### 8. Settings storage

`RewriteSettings` is the feature's `FeatureStore`, shared through `FeatureEnvironment.store(RewriteSettings.self)` by the preparer, the coordinator, the right-click menu and the Rewrite tab. It keeps its values in the environment's `UserDefaults` (a private suite in tests):
- `rewriteTemplateChoice` (`"automatic"` or a template ID)
- `rewriteCategoryTemplates` (a category → template ID dictionary, stored only when it differs from the defaults)
- `rewritePrompt.<templateID>` (only when edited)

Settings views bind to the store, not to `AppState`, per the groundwork's rule that each feature keeps its own settings.

### 9. Review fixes

Found by the review of the three feature branches; all are in this change.

- **The event tap has its own thread.** `HotkeyService` creates its one `.defaultTap` (Accessibility only, no Input Monitoring) and adds it to the run loop of a dedicated thread, `HotkeyTapThread`, which does nothing else. The callback stays O(1). The gesture state is only touched on that thread; the resulting actions (start, hint, end, cancel) are sent to the main actor with `DispatchQueue.main.async`. So nothing Honyaku does on the main thread (saving History, the password check waiting on a hung app, a large import) can delay a key press, a click or Honyaku's own ⌘V, and a slow main thread can no longer make macOS disable the tap. `tapDisabledByTimeout` and `tapDisabledByUserInput` are handled on the tap thread, which re-enables the tap and replays the live modifier state. The pipeline's busy state, which the gesture reads, is a lock-protected flag that the coordinator sets whenever the status changes, so the tap never reads main-actor state. `stop()` disables the tap, removes its source, stops the run loop and waits for the thread to finish. Key-downs that Honyaku posts itself (its paste) are recognised by the event's source process ID and passed straight through, so they can never cancel a hold.
- **No stuck Control.** Control's own press is swallowed, so while a hold is in progress every modifier event passed through (Shift's, typically) has Control cleared from its flags: the app never sees Control down, and doesn't need to see it released. A hold cancelled by a key, a click or Command/Option is different: the cancelling event reaches the app *with* Control in its flags, because the user meant the shortcut. So the Control release after a cancel is passed through, not swallowed, and the app sees Control go up. The alternative of swallowing Shift's events too was rejected: it would hide Shift from apps during every rewrite hold.
- **Notices match the outcome.** The fallback notice says "used your words as dictated", not "pasted". When the outcome is `.blocked`, only the block notice is shown; when it is `.saveOnly` with a notice, only that notice is shown. Other notices from the run would claim something that didn't happen.
- **Echo stripping keeps content.** A first line is stripped only when it is a heading that names a template, the dictation label, or a line of the prompt itself (the shared rules or the template prompt in use). A first line such as "Rewrite the dictation pipeline as stages" is content.
- **Cut short at the cap.** `CleanupService.generate` reports whether generation stopped at `maxTokens` (`GenerateStopReason.length`). A rewrite that did is trimmed back to its last complete line or, for one line, its last complete sentence, and the notice "The rewrite was cut short" is added. If nothing complete is left, the rewrite failed.
- **Cut-off reasoning.** `CleanupService.stripDelimiters` drops everything from a `<think>` that never closes. For a rewrite, output that had one counts as a failure, so reasoning never reaches the paste. Word-for-word cleanup gets empty output and keeps the transcript.
- **Caps for scripts without spaces.** Input tokens are estimated as words × 4/3 for spaced text plus one per character of a script written without spaces, so a minute of Japanese isn't capped like three words.
- **Flags-only fallback is visible.** When macOS refuses the tap with key and mouse events and the flags-only tap is used, the coordinator shows "Pressing a key during a hold won't cancel it. Honyaku couldn't watch key presses." once (remembered in the feature settings), and the General tab shows the same line while it lasts.
- **Smaller fixes.** The Rewrite tab's model note uses `ModelRegistry.smallCleanupModelID`. An emptied template prompt counts as the default (the editor keeps the empty text while editing; the rewrite uses the default). The prompt cache keeps up to three prompts; each holds the KV cache of one system prompt (about 25–60 MB for Qwen3-4B), so the worst case is under 200 MB. `TerminalOneLine` joins every kind of line break (`\R`: CRLF, U+2028, U+0085, VT, FF) and removes control characters other than tab. Tests remove their temporary folders.
- **Spec.** This change MODIFIES "Settings is a single window" to the final eight tabs and History row, since it is the last of the three features to archive.

## Risks / Trade-offs

- **The model invents details despite the rule.** Mitigation: temperature 0; the shared rules can't be edited; TBD placeholders; integration tests on fixed transcripts check that no name, number or ID absent from the transcript appears in the output.
- **Qwen3-1.7B writes weaker rewrites.** Mitigation: the note in the Rewrite tab; the 4B model is already recommended on ≥16 GB Macs.
- **Cancel-on-key throws away a long dictation after a stray key press.** This was accepted (Q16): a shortcut being transcribed is worse. The cancel is silent, so nothing is pasted.
- **The tap now sees every key-down.** Mitigation: only the type is read, the callback returns at once while idle, and events are never modified. The privacy requirement is updated to say exactly this.
- **Stuck Control** (found in review): with Control's press and release swallowed, a Shift event passed through mid-hold carried Control in its flags, so an app tracking modifiers from modifier events (VMs, remote desktop, games) was left believing Control was held. Fixed in Decision 9.
- **Rewrite latency** (1.5–4 s on an M3 Max, slower on base chips): the capsule label makes clear why it takes longer than dictation.
- **Qwen3-4B's chat template isn't installed** (found while testing this change; not fixed here). The installed `qwen3-4b-2507` folder has no `chat_template` in `tokenizer_config.json` and no `chat_template.jinja`, so swift-transformers logs "No chat template was included or provided" and sends the system prompt and dictation as plain text. That affects cleanup as well as rewrites, and is a model-installer issue to fix separately. The integration tests pass even so, and the echo stripping above covers the copied-instruction lines it causes.

## Migration Plan

- No data migration. Old history entries decode without `rewriteTemplateID`.
- Defaults register at launch with the other settings.

## Open Questions

None. The decisions came out of the grilling session (Q2–Q7, Q16–Q23, Q28–Q31).
