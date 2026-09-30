## ADDED Requirements

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
The system SHALL support at minimum the following cleanup model tiers selectable by the user:

| Tier | Model | Size | Speed |
|---|---|---|---|
| Fast | Qwen 2.5 1.5B Instruct 4-bit (MLX) | ~950 MB | ~2–3s |
| Balanced | Qwen 2.5 3B Instruct 4-bit (MLX) | ~1.9 GB | ~5–6s |
| Best | Qwen 2.5 7B Instruct 4-bit (MLX) | ~4.3 GB | ~10–15s |

#### Scenario: User has selected the Fast tier
- **WHEN** transcription completes and cleanup is triggered
- **THEN** the system uses the Qwen 2.5 1.5B MLX model for cleanup and returns a result in under 3 seconds on M1 hardware

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
