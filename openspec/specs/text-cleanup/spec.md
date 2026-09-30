# text-cleanup Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: Raw transcript is processed by a local LLM to produce clean text
The system SHALL pass the raw WhisperKit transcript to a locally-running LLM (via MLXLLM) to remove filler words, false starts, and self-corrections, producing a clean, readable output. The LLM SHALL run entirely on the local device; no transcript text SHALL be sent to any remote service. The LLM SHALL use **temperature 0.0** (greedy decoding) to ensure deterministic, faithful output — the model removes fillers without paraphrasing or introducing new content.

#### Scenario: Cleanup produces clean output
- **WHEN** WhisperKit returns a transcript containing filler words (e.g., "um", "uh", "like", "you know")
- **THEN** the cleanup LLM returns a version of the text with those fillers removed and natural sentence structure preserved

#### Scenario: Cleanup LLM returns unchanged text for already-clean input
- **WHEN** WhisperKit returns a transcript with no filler words or self-corrections
- **THEN** the cleanup LLM returns text that is functionally equivalent to the input

---

### Requirement: Multiple cleanup model tiers are supported
The system SHALL offer the following cleanup models:

| Tier | Model | Size | Default for |
|---|---|---|---|
| Fast | Qwen3-1.7B 4-bit (`mlx-community/Qwen3-1.7B-4bit`), thinking off | ~968 MB | Macs under 16 GB |
| Best | Qwen3-4B-Instruct-2507 4-bit (`mlx-community/Qwen3-4B-Instruct-2507-4bit`) | ~2.3 GB | Macs with 16 GB or more |

The measured latency for each tier on the developer's Mac SHALL be recorded in the design, and shown to users as a relative speed ("faster" or "more accurate"), not as seconds.

#### Scenario: User has the Fast tier selected
- **WHEN** transcription completes and cleanup is triggered
- **THEN** the system cleans the text with Qwen3-1.7B, with thinking turned off

#### Scenario: User has the Best tier selected
- **WHEN** transcription completes and cleanup is triggered
- **THEN** the system cleans the text with Qwen3-4B-Instruct-2507

### Requirement: Cleanup can be disabled
The system SHALL provide a toggle in Settings to disable LLM cleanup, in which case the raw WhisperKit transcript is pasted directly.

#### Scenario: Cleanup is disabled in Settings
- **WHEN** push-to-talk recording completes and cleanup is toggled off
- **THEN** the raw transcript is written to the pasteboard and pasted without any LLM processing step

---

### Requirement: Cleanup prompt is user-customizable
The system SHALL expose the LLM system prompt used for cleanup in Settings, allowing the user to modify cleanup behavior (e.g., change tone, add domain-specific rules, preserve technical terms).

#### Scenario: User edits the cleanup prompt
- **WHEN** the user modifies the cleanup system prompt in Settings and saves
- **THEN** subsequent cleanup passes use the updated prompt

#### Scenario: User resets the cleanup prompt to default
- **WHEN** the user clicks "Reset to Default" for the cleanup prompt
- **THEN** the system restores the factory default prompt

---

### Requirement: Cleaned text is pasted into the active application
The system SHALL write the cleaned (or raw, if cleanup is disabled) transcript to the system pasteboard and simulate a ⌘V keystroke to paste it into the frontmost application. The user's prior pasteboard contents SHALL be restored after the paste.

If Honyaku itself is the frontmost app when the text is ready (for example, the user brought Settings forward while the dictation was being transcribed), the system SHALL NOT send ⌘V. It SHALL save the transcript to history and show "Saved to History — Honyaku was in front", and SHALL leave the clipboard untouched.

#### Scenario: Successful paste after cleanup
- **WHEN** cleanup completes and the user has a text field focused
- **THEN** the cleaned text appears at the cursor position in the active application and the user's prior clipboard content is restored

#### Scenario: No active text field to paste into
- **WHEN** cleanup completes but no editable field is focused
- **THEN** the text is written to the pasteboard and a notification indicates the text is ready to paste manually

#### Scenario: Honyaku is in front when the text is ready
- **GIVEN** the user started a dictation in another app, then clicked the menu bar icon so Settings came to the front
- **WHEN** the transcript is ready
- **THEN** no ⌘V is sent, the transcript is added to history, the status reads "Saved to History — Honyaku was in front", and the clipboard is unchanged

#### Scenario: Paste simulation fails or pipeline is aborted
- **WHEN** the paste simulation fails or the transcription pipeline is cancelled before completion
- **THEN** any transcript text written to the pasteboard is cleared within 5 seconds and the prior clipboard contents are restored, and the error is shown on the menu bar icon and in Settings > General

### Requirement: The default cleanup prompt never drops content
The default cleanup prompt SHALL instruct the model to keep every word the speaker said, in order, apart from the listed filler words and false starts. Its worked examples SHALL only remove what the faithfulness check allows, so that following them never triggers the fallback. It SHALL forbid shortening, summarising or rephrasing. A cleanup prompt the user has customised SHALL NOT be changed automatically.

#### Scenario: Meaningful words are kept
- **WHEN** the transcript is "Are you working or not?"
- **THEN** the cleaned text still contains "or not"

#### Scenario: Fillers are still removed
- **WHEN** the transcript is "um I think we should uh ship it"
- **THEN** the cleaned text is "I think we should ship it." or equivalent, with no content words missing

#### Scenario: Customised prompt is left alone
- **GIVEN** the user has edited the cleanup prompt in Settings
- **WHEN** Honyaku is updated with a new default prompt
- **THEN** the user's prompt is unchanged, and "Reset to Default" gives the new default

---

### Requirement: The transcript is given to the cleanup model as marked-up input
The system SHALL send the transcript to the cleanup model inside clear delimiters, labelled as a transcript to clean, so that a transcript phrased as a question or request is cleaned rather than answered or rewritten. Delimiters echoed back by the model SHALL be removed from the output.

#### Scenario: Transcript phrased as a question
- **WHEN** the transcript is "Are you working or not?"
- **THEN** the cleanup model is given it as marked input to clean, and the output contains no delimiter characters

---

### Requirement: Cleanup output that changes the speaker's words is rejected
After cleanup, the system SHALL check the model's output against the raw transcript in both directions:
- Every raw word SHALL survive, except removable fillers. "um", "umm", "uh" and "hmm" are always removable. "like", "so", "right", "basically", "literally", "you know", "sort of" and "kind of" are removable only when set off: followed by a comma, and preceded by a comma or at the start of a sentence.
- The output SHALL contain no word that isn't in the raw transcript, and SHALL keep the raw words in their original order. Only deletions are allowed.
- The output SHALL NOT introduce a line break, a control character, or a character from `` ` | & ; $ < > \ { } `` unless the raw transcript already contains it.

If either check fails, the system SHALL use the raw transcript with only "um", "umm", "uh" and "hmm" removed. A `Cleaned:` label echoed from the prompt's examples SHALL be stripped before checking.

#### Scenario: Model drops a content word
- **WHEN** the raw transcript is "Are you working or not?" and the model returns "Are you working?"
- **THEN** "Are you working or not?" is pasted

#### Scenario: Model only removes fillers
- **WHEN** the raw transcript is "um I think we should uh ship it" and the model returns "I think we should ship it."
- **THEN** the model's output is pasted

#### Scenario: Model drops a word that only looks like a filler
- **WHEN** the raw transcript is "I like it" and the model returns "I it."
- **THEN** "I like it" is pasted

#### Scenario: Model removes a set-off filler
- **WHEN** the raw transcript is "I was, like, going home" and the model returns "I was going home."
- **THEN** the model's output is pasted

#### Scenario: Model adds words
- **WHEN** the raw transcript is "Are you working or not?" and the model returns "Are you working or not? Yes, I am."
- **THEN** "Are you working or not?" is pasted

#### Scenario: Model reorders words
- **WHEN** the raw transcript is "I did not say it was done" and the model returns "I did say it was not done."
- **THEN** "I did not say it was done" is pasted

#### Scenario: Model inserts a line break
- **WHEN** the model's output contains a line break the raw transcript didn't have
- **THEN** the raw transcript (minus um/umm/uh/hmm) is pasted

#### Scenario: Consecutive set-off fillers
- **WHEN** the raw transcript is "Right, so, we ship it" and the model returns "We ship it."
- **THEN** the model's output is pasted

#### Scenario: Echoed example label
- **WHEN** the model returns "Cleaned: I think we should ship it." for "um I think we should uh ship it"
- **THEN** "I think we should ship it." is pasted

#### Scenario: Fallback still removes unambiguous fillers
- **WHEN** the raw transcript is "um are you working or not" and the model returns "Are you working?"
- **THEN** "are you working or not" is pasted, with "um" removed

---

### Requirement: The paste has time to land before the clipboard is restored
After posting ⌘V, the system SHALL wait at least 500 ms before restoring the user's previous clipboard contents, so that apps which read the clipboard slowly (terminals, Electron apps) receive the transcript. The wait SHALL happen in the background: the app SHALL be ready for the next dictation as soon as ⌘V is posted. If another dictation pastes before a pending restore runs, the pending restore SHALL be superseded, and the user's original clipboard SHALL still be what is restored at the end. If the clipboard changed for any other reason after the transcript was written (for example the user copied something), the system SHALL NOT restore, so the user's newer contents are kept.

#### Scenario: Pasting into a terminal
- **WHEN** the user dictates into a terminal window
- **THEN** the transcript appears in the terminal, and the previous clipboard contents are restored afterwards

#### Scenario: User copies during the wait
- **WHEN** the clipboard changes between the transcript being written and the restore
- **THEN** the previous clipboard contents are not restored and the newer contents stay

#### Scenario: Dictating in quick succession
- **WHEN** the user presses Control again right after a paste, before the clipboard restore has run
- **THEN** the new press is recorded and pasted, and after the last paste the user's original clipboard (not an earlier transcript) is restored

### Requirement: Cleanup adds little latency
The system SHALL keep cleanup fast by:
- reusing the processed system prompt between dictations for the same model and prompt
- capping generated output at a token limit derived from the input length
- turning off any model "thinking" mode through the chat template

On the developer's Mac, the median time spent in cleanup for a one-sentence dictation SHALL be recorded for each tier, and SHALL be under 0.5 s for the Fast tier.

#### Scenario: Repeated dictations
- **WHEN** the user dictates several times in a row with the same model and prompt
- **THEN** the system prompt is processed once, not on every dictation

#### Scenario: Model starts to ramble
- **WHEN** the model would produce much more text than was dictated
- **THEN** generation stops at the token cap, and the faithfulness check falls back to the raw words

#### Scenario: Thinking-capable model
- **WHEN** the selected model supports a thinking mode
- **THEN** the chat template is given `enable_thinking: false`, and no reasoning text is produced or pasted

---

### Requirement: Unambiguous fillers never reach the paste
When the transcript's language is English, the system SHALL remove "um", "umm", "uh" and "hmm" (as whole words, not inside words like "uh-huh") from the text before pasting, whatever the model returned, including when cleanup is off or falls back. For any other language these are not treated as fillers: they SHALL be kept, and the faithfulness check SHALL treat every word of a non-English transcript as content, because "um" is a real word in German ("um 5 Uhr") and Portuguese ("um carro").

#### Scenario: Model leaves a filler in
- **WHEN** the model returns "I think we should uh ship it" for an English dictation
- **THEN** "I think we should ship it" is pasted

#### Scenario: German dictation
- **WHEN** Whisper transcribes "Ich komme um 5 Uhr" with language German
- **THEN** "um" is kept in the pasted text, and a cleanup output that drops it is rejected

#### Scenario: Portuguese dictation
- **WHEN** Whisper transcribes "Comprei um carro" with language Portuguese
- **THEN** "um" is kept in the pasted text

---

### Requirement: The speaker-label rule is only given when labels are present
The cleanup prompt SHALL include the instruction to keep `[Speaker N]` labels only when the transcript contains such labels.

#### Scenario: Ordinary dictation
- **WHEN** a transcript without speaker labels is cleaned
- **THEN** the prompt sent to the model contains no speaker-label rule, and the output contains no `[Speaker N]` label

