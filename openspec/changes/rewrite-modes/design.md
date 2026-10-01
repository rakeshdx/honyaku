## Context

Plain dictation is word for word: the cleanup model may only delete fillers, and `CleanupService.isFaithful` rejects anything else (new words, reordering, line breaks, shell metacharacters). Rewrite is a second, explicitly chosen mode where the model *is* allowed to restructure what was said into a format.

This change builds on `dictation-stages`, which lands first. That change adds:
- `DictationMode`
- hotkey callbacks that carry the mode
- `DictationContext`, which captures the app in front at recording start and at paste time
- `AppCategory`
- `CleanupRequest` (`systemPrompt`, `extraRules`, `faithfulness: .strict | .none`, `maxTokens`)
- the pipeline's LLM stage
- optional `TranscriptEntry.mode`

The type names below follow the groundwork plan; where `dictation-stages` merged different names, this change uses the merged ones. `custom-vocabulary` and `per-app-behaviour` merge before this change (merge order: vocabulary, per-app, rewrite).

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
| holding | Shift goes down or up | `sawShift = true` on down. Event passes through. Recording continues |
| holding | Command or Option goes down | `.cancel(.chord)`. Event passes through. The Control release that follows is swallowed |
| holding | `keyDown` (any non-modifier key) | `.cancel(.key)`. Event passes through unchanged. The Control release is swallowed |
| holding | left, right or other mouse-down | `.cancel(.click)`. Event passes through. The Control release is swallowed |
| holding | Control goes up, held ≥ 300 ms | `.end(mode: sawShift ? .rewrite : .dictate)`, swallow |
| holding | Control goes up, held < 300 ms | `.cancel(.tooShort)`, swallow (unchanged) |
| cancelled hold | Control goes up | `.suppress` (swallow), back to idle |

Rules that follow from the table:
- The mode is the union of what was seen during the hold. Shift before Control, Shift after Control, and Shift released before Control all give a rewrite. Nothing is decided at key-down, so a plain-Control dictation starts exactly as fast as today.
- Command and Option still mean "this is a shortcut". They used to let the recording carry on; they now cancel it, which matches the new key-press rule. Control+Option stays free for VoiceOver and window managers.
- Every cancel stops capture and releases the microphone (`onRecordingCancelled`), with no transcription and no error. A cancel is silent.
- `keyDown` and mouse-down events arriving while idle return straight away with no state change. The callback reads only the event *type*, never `keyboardEventKeycode`, characters or the mouse location, and never delays or alters the event.
- Recovery after macOS disables the tap is unchanged: it replays `flagsState`. A key press that happened while the tap was disabled isn't seen, so that hold ends normally.
- The 5 s stale rule and the busy guard apply in both modes.

`HotkeyService`'s event mask gains `keyDown`, `leftMouseDown`, `rightMouseDown` and `otherMouseDown`. `onRecordingEnded` carries the mode (the groundwork's mode-carrying callback); `onRecordingStarted` stays mode-less, because the mode isn't known yet. The capsule's label is updated by a separate `onModeHint(.rewrite)` callback as soon as Shift is seen.

*Alternatives considered:* deciding the mode at key-down, which forces an order and adds a wait; tap-then-hold Control, which is slower and conflicts with macOS's "Press Control twice" Dictation shortcut; Right Option, which MacBook keyboards make awkward and which is a separate key to learn. A long-hold exemption from the key-press cancel was rejected (Q16): it would bring back long shortcut holds being transcribed.

### 2. Template selection

`RewriteTemplateID`: `jiraTicket`, `chatMessage`, `email`, `commitMessage`, `prDescription`, `agentPrompt`, `standupUpdate`.

The template is resolved when the recording **ends**, from the app that was in front when it **started** (`DictationContext.appAtStart.category`):
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
Rewrite the dictation as a Jira ticket with these sections:
Summary: one line.
Description: what the problem or request is, in a few sentences.
Steps to reproduce: numbered steps. Include this section only if the speaker described steps.
Acceptance criteria: "- " bullets saying what must be true when this is done.
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
Rewrite the dictation as a pull request description with these sections:
Summary: one or two sentences.
Changes: "- " bullets, one per change.
Testing: how it was tested, or TBD.
```

Coding-agent prompt:
```
Rewrite the dictation as one clear paragraph of instructions for a coding agent, written in the second person ("Add…", "Make sure you…"). Keep every file, function, command and error message the speaker named, exactly as spoken.
```

Standup update:
```
Rewrite the dictation as a standup update with these sections:
Yesterday: "- " bullets.
Today: "- " bullets.
Blockers: "- " bullets, or "None" if the speaker mentioned none.
```

Edited prompts are stored only when they differ from the default ("Reset to default" removes the stored copy), the same pattern as `cleanupPrompt`.

### 4. Generation

- **Model:** the selected cleanup model (`selectedCleanupModelID`), loaded through `CleanupService` with the same single-flight load and thinking off for Qwen3-1.7B. There is no separate rewrite model.
- **Request:** `CleanupRequest(systemPrompt: shared + template, extraRules: vocabulary terms, faithfulness: .none, maxTokens: cap)`, temperature 0, through the pipeline's LLM stage.
- **Output cap:** `min(templateCap, 150 + 3 × estimated input tokens)`, with input tokens estimated as in `outputTokenLimit` (words × 4/3).

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
- **Prompt cache:** keyed by model and full system prompt, as today. Switching templates re-prefills; the cost is acceptable (prompt processing ≥160 tok/s on a ~200-token system prompt).
- **Output:** trimmed, with echoed delimiters or labels stripped. An empty result counts as a failure.
- **Faithfulness:** the `isFaithful` check is not run for rewrites; the newline, control-character and metacharacter rule is not applied either. The output paths that need protection are covered by Decision 6.
- **Cleanup toggle:** affects only `.dictate`. A rewrite always uses the model, even with cleanup off.
- **Diarization:** runs as configured, before the LLM stage. Labels are handled as in Decision 3.

### 5. Fallbacks

The fallback text is the dictation as it would have been without any model: the transcript after vocabulary replacements and unambiguous-filler removal (um, umm, uh, hmm; English only). A failed rewrite does not trigger a second model call for word-for-word cleanup: the model just failed, and a second call doubles the wait.

| Situation | Pasted | Status message |
|---|---|---|
| No cleanup model downloaded | the fallback text | "To use Rewrite, download a cleanup model in Settings > Models" |
| Model error, empty output or 60 s timeout | the fallback text | "Couldn't rewrite: pasted your words as dictated" |

Both messages use the "notice" style introduced for "Saved to History — Honyaku was in front": they show on the capsule, the icon and the General tab, and clear at the next dictation. The History entry is saved with `mode: .dictate`, so it reads as what it is.

### 6. Terminals and per-app formatting

Per-app formatting rules (from `per-app-behaviour`) are applied to rewrite output exactly as to dictation, using the app in front **at paste time** (Q14, Q28).

For the Terminals category that means joining the lines:
- every run of line breaks and surrounding whitespace becomes a single space
- leading and trailing whitespace is trimmed, so there's never a trailing line break
- dropping the final full stop and straight quotes follow the category's rules

Nothing else is stripped: backticks, `$` and the like stay, because a single line runs nothing until the user presses Return (Q23).

`per-app-behaviour` merges before this change, so Rewrite adds no line-joining code of its own: its final stage already runs on rewrite output. If the merge order ever changes and Rewrite lands first, Rewrite carries a minimal `TerminalOneLine` final stage, active only for `.rewrite` with a terminal category at paste time. Per-app's rules then replace it; it is deleted in that change's rebase, and the scenario in the text-cleanup delta stays satisfied either way.

### 7. UI

- **Capsule:**
  - While recording, once Shift is seen: "Rewriting as Jira ticket", next to the level meter and timer.
  - While processing: "Rewriting as Jira ticket…" in place of "Transcribing…".
  - No middle-dot separators. Template display names are used in sentence case ("Rewriting as chat message", "Rewriting as coding-agent prompt").
- **Menu bar icon:** the processing symbol is unchanged. VoiceOver reads "Honyaku, Rewriting" while a rewrite is generating.
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
    - If Qwen3-1.7B is selected: "Qwen3-1.7B is fast but writes weaker rewrites. Qwen3-4B is better for this." with a button to the Models tab.
    - If no cleanup model is downloaded: "Rewrite needs a cleanup model." with the same button.
- **General tab:** under "Hold Control to talk", the line "Hold Control+Shift to rewrite as a Jira ticket, chat message, email and more."
- **History:**
  - A rewrite row shows the rewritten text, a "Rewritten as Jira ticket" caption, and a "Your words" disclosure with the spoken transcript.
  - Copy copies the rewrite.
  - Search matches both texts.
  - `TranscriptEntry` gains an optional `rewriteTemplateID`. `mode` comes from the groundwork, and old entries decode as dictation.
- **First run:** unchanged.

### 8. Settings storage

A small `RewriteSettings` store wraps a `UserDefaults` instance that tests can inject:
- `rewriteTemplateChoice` (`"automatic"` or a template ID)
- `rewriteCategoryTemplates` (a category → template ID dictionary, stored only when it differs from the defaults)
- `rewritePrompt.<templateID>` (only when edited)

Settings views bind to the store, not to `AppState`, per the groundwork's rule that each feature keeps its own settings.

## Risks / Trade-offs

- **The model invents details despite the rule.** Mitigation: temperature 0; the shared rules can't be edited; TBD placeholders; integration tests on fixed transcripts check that no name, number or ID absent from the transcript appears in the output.
- **Qwen3-1.7B writes weaker rewrites.** Mitigation: the note in the Rewrite tab; the 4B model is already recommended on ≥16 GB Macs.
- **Cancel-on-key throws away a long dictation after a stray key press.** This was accepted (Q16): a shortcut being transcribed is worse. The cancel is silent, so nothing is pasted.
- **The tap now sees every key-down.** Mitigation: only the type is read, the callback returns at once while idle, and events are never modified. The privacy requirement is updated to say exactly this.
- **Swallowing a Control release after a cancel** leaves the app having seen neither a Control down nor a Control up from the tap, which matches what it saw for plain dictation. No stuck-modifier risk.
- **Rewrite latency** (1.5–4 s on an M3 Max, slower on base chips): the capsule label makes clear why it takes longer than dictation.

## Migration Plan

- No data migration. Old history entries decode without `rewriteTemplateID`.
- Defaults register at launch with the other settings.

## Open Questions

None. The decisions came out of the grilling session (Q2–Q7, Q16–Q23, Q28–Q31).
