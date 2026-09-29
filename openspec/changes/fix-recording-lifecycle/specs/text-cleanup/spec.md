## ADDED Requirements

### Requirement: The default cleanup prompt never drops content
The default cleanup prompt SHALL instruct the model to keep every word the speaker said, in order, apart from the listed filler words and false starts. It SHALL forbid shortening, summarising or rephrasing. A cleanup prompt the user has customised SHALL NOT be changed automatically.

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

### Requirement: Cleanup output that loses words is rejected
After cleanup, the system SHALL check that every word of the raw transcript survives in the cleaned text, apart from the listed filler words and phrases. If any other word is missing, the system SHALL use the raw transcript with only the unambiguous fillers removed ("um", "umm", "uh", "hmm") instead of the model's output.

#### Scenario: Model drops a content word
- **WHEN** the raw transcript is "Are you working or not?" and the model returns "Are you working?"
- **THEN** "Are you working or not?" is pasted

#### Scenario: Model only removes fillers
- **WHEN** the raw transcript is "um I think we should uh ship it" and the model returns "I think we should ship it."
- **THEN** the model's output is pasted

#### Scenario: Fallback still removes unambiguous fillers
- **WHEN** the raw transcript is "um are you working or not" and the model returns "Are you working?"
- **THEN** "are you working or not" is pasted, with "um" removed
