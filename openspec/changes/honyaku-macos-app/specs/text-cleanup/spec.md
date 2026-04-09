## ADDED Requirements

### Requirement: Raw transcript is processed by a local LLM to produce clean text
The system SHALL pass the raw WhisperKit transcript to a locally-running LLM (via LLM.swift) to remove filler words, false starts, and self-corrections, producing a clean, readable output. The LLM SHALL run entirely on the local device; no transcript text SHALL be sent to any remote service.

#### Scenario: Cleanup produces clean output
- **WHEN** WhisperKit returns a transcript containing filler words (e.g., "um", "uh", "like", "you know")
- **THEN** the cleanup LLM returns a version of the text with those fillers removed and natural sentence structure preserved

#### Scenario: Cleanup LLM returns unchanged text for already-clean input
- **WHEN** WhisperKit returns a transcript with no filler words or self-corrections
- **THEN** the cleanup LLM returns text that is functionally equivalent to the input

---

### Requirement: Multiple cleanup model tiers are supported
The system SHALL support at minimum the following cleanup model tiers selectable by the user:

| Tier | Model | Size | Speed |
|---|---|---|---|
| Fast | Qwen 3.5 0.8B (GGUF int8) | ~535 MB | ~1–2s |
| Balanced | Qwen 3.5 2B (GGUF) | ~1.3 GB | ~4–5s |
| Quality | Qwen 3.5 4B (GGUF) | ~2.8 GB | ~5–7s |

#### Scenario: User has selected the Fast tier
- **WHEN** transcription completes and cleanup is triggered
- **THEN** the system uses the Qwen 3.5 0.8B model for cleanup and returns a result in under 3 seconds on M1 hardware

---

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

#### Scenario: Successful paste after cleanup
- **WHEN** cleanup completes and the user has a text field focused
- **THEN** the cleaned text appears at the cursor position in the active application and the user's prior clipboard content is restored

#### Scenario: No active text field to paste into
- **WHEN** cleanup completes but no editable field is focused
- **THEN** the text is written to the pasteboard and a notification indicates the text is ready to paste manually

#### Scenario: Paste simulation fails or pipeline is aborted
- **WHEN** the paste simulation fails or the transcription pipeline is cancelled before completion
- **THEN** any transcript text written to the pasteboard is cleared within 5 seconds and the prior clipboard contents are restored, and a notification is shown in the menu bar popover
