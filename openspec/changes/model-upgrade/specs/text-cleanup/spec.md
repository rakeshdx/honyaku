## MODIFIED Requirements

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

## ADDED Requirements

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
After cleanup, and also when cleanup is off or falls back, the system SHALL remove "um", "umm", "uh" and "hmm" (as whole words, not inside words like "uh-huh") from the text before pasting, whatever the model returned.

#### Scenario: Model leaves a filler in
- **WHEN** the model returns "I think we should uh ship it"
- **THEN** "I think we should ship it" is pasted

---

### Requirement: The speaker-label rule is only given when labels are present
The cleanup prompt SHALL include the instruction to keep `[Speaker N]` labels only when the transcript contains such labels.

#### Scenario: Ordinary dictation
- **WHEN** a transcript without speaker labels is cleaned
- **THEN** the prompt sent to the model contains no speaker-label rule, and the output contains no `[Speaker N]` label
