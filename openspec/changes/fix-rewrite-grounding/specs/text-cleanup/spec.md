## ADDED Requirements

### Requirement: The keep-terms rule lists only terms that were said
The "Write these terms exactly as listed:" rule SHALL list only the enabled vocabulary terms that occur in the transcript sent to the model, after vocabulary corrections, in vocabulary order and at most 40. A term SHALL count as occurring when any of its spellings matches under the same rules as the corrections (case, word boundaries, contractions, links and code, speaker labels). When no enabled term occurs, the prompt SHALL contain no vocabulary rule. This SHALL apply to word-for-word cleanup and to rewrites.

#### Scenario: Only the term that was said
- **GIVEN** the vocabulary lists Paramount+, P+ and POPS
- **WHEN** the transcript after corrections is "Ship P+ today"
- **THEN** the prompt contains "Write these terms exactly as listed: P+." and doesn't mention Paramount+ or POPS

#### Scenario: No listed term said
- **GIVEN** the vocabulary lists Paramount+ and POPS
- **WHEN** the transcript is "Let's meet at noon"
- **THEN** the prompt contains no vocabulary rule

#### Scenario: A heard-as spelling counts once corrected
- **GIVEN** the vocabulary has "Paramount+" heard as "paramount plus"
- **WHEN** the speech model writes "paramount plus is live"
- **THEN** the corrected transcript "Paramount+ is live" is sent with the rule listing Paramount+

### Requirement: Rewrites need at least a few words
A rewrite SHALL need at least 4 words. Words are whitespace-separated runs containing a letter or digit, with speaker labels left out. Every 2 characters of a script written without spaces (Han, kana, Thai and similar) SHALL count as one word. A shorter rewrite SHALL NOT be sent to the model. It SHALL go through as plain dictation (cleanup when it's on, filler removal, per-app rules, saved to History as a dictation) with the notice "Too short to rewrite: used your words as dictated".

#### Scenario: Two words
- **GIVEN** the vocabulary lists P+, Paramount+ and POPS
- **WHEN** the user holds Control+Shift in a terminal and says "P plus"
- **THEN** no model is called, "P+" is pasted, History records a dictation, and the status shows "Too short to rewrite: used your words as dictated"

#### Scenario: Four words
- **WHEN** the user holds Control+Shift and says "rename the build script"
- **THEN** the rewrite runs

#### Scenario: Short Japanese
- **WHEN** the user holds Control+Shift and says 「確認して」
- **THEN** it's too short to rewrite and goes through as plain dictation

### Requirement: A rewrite never adds vocabulary terms that weren't said
After a rewrite, when the output contains an enabled vocabulary term that doesn't occur in the rewrite's input (matched as for the keep-terms rule), the rewrite SHALL count as failed. The words SHALL go through as plain dictation, with the notice "Couldn't rewrite without adding things you didn't say: used your words as dictated". When the outcome is blocked or saved to History only, only that outcome's notice SHALL show. With no enabled vocabulary terms, the check SHALL be skipped.

#### Scenario: The model adds a listed term
- **GIVEN** the vocabulary lists P+ and POPS
- **WHEN** the user rewrites "check the P+ login flow today" and the model returns text mentioning the POPS dashboard
- **THEN** the words are used as dictated, with the invention notice

#### Scenario: The model repeats only terms that were said
- **GIVEN** the vocabulary lists P+ and POPS
- **WHEN** the user rewrites "check the P+ login flow today" and the model returns "Check the P+ login flow today."
- **THEN** the rewrite is pasted
