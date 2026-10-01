## ADDED Requirements

### Requirement: Vocabulary corrections are applied to every transcript
After transcription and the speaker-label merge, and before cleanup runs, the system SHALL replace every match of a vocabulary term's "heard as" spellings, and of the term's own spelling in any letter case, with the term exactly as written in the vocabulary.
- **Matching:**
  - It SHALL ignore letter case and SHALL treat curly and straight apostrophes as the same.
  - It SHALL match whole words or phrases only: no letter or digit directly before or after.
  - It SHALL let a space in a spelling match any run of whitespace.
- **What's kept:** punctuation next to a match, and a possessive "'s" directly after it, SHALL be kept.
- **Overlaps:** where matches overlap, the longest SHALL win. On a tie, the term higher in the list SHALL win.
- **One pass:** replaced text SHALL NOT be matched again.
- **Never altered:** speaker labels such as `[Speaker 1]` SHALL never be altered.
- **Scope:** corrections SHALL apply with either speech engine and with cleanup on or off.
- **Timing:** they SHALL apply from the next dictation after the list changes, without relaunching.
- **Disabled terms:** these SHALL be ignored.

#### Scenario: Misheard product name
- **GIVEN** the vocabulary has the term "Paramount+" heard as "paramount plus"
- **WHEN** the speech model returns "I'm testing paramount plus today."
- **THEN** "I'm testing Paramount+ today." is passed on to cleanup and pasted

#### Scenario: Case fixed with no heard-as spelling
- **GIVEN** the vocabulary has the term "Jira" with no heard-as spellings
- **WHEN** the speech model returns "file a jira, then ping me"
- **THEN** the text becomes "file a Jira, then ping me"

#### Scenario: Part of a longer word
- **GIVEN** the vocabulary has the term "Jira"
- **WHEN** the speech model returns "jiras are piling up"
- **THEN** "jiras" is left unchanged

#### Scenario: Possessive
- **GIVEN** the vocabulary has the term "Pluto TV" heard as "pluto tv"
- **WHEN** the speech model returns "pluto tv's guide"
- **THEN** the text becomes "Pluto TV's guide"

#### Scenario: Longest match wins
- **GIVEN** the vocabulary has "Paramount" and "Paramount+" heard as "paramount plus"
- **WHEN** the speech model returns "paramount plus launched"
- **THEN** the text becomes "Paramount+ launched", not "Paramount plus launched"

#### Scenario: Speaker labels untouched
- **GIVEN** the vocabulary has the term "Speaker" and speaker labels are on
- **WHEN** a two-speaker dictation is transcribed
- **THEN** the `[Speaker 1]` and `[Speaker 2]` labels are unchanged

#### Scenario: Empty vocabulary
- **GIVEN** the vocabulary is empty or every term is off
- **WHEN** the user dictates
- **THEN** the transcript is passed on unchanged

---

### Requirement: Whisper is given the vocabulary as a spelling hint
When the selected speech engine is Whisper and the dictation language is English or Auto-detect, the system SHALL give Whisper the enabled vocabulary terms as a comma-separated glossary before decoding: Whisper's previous-context prompt, set through `promptTokens`.
- **Contents:** the glossary SHALL contain terms only, never heard-as spellings.
- **Selection:** it SHALL include terms from the top of the list down, stopping before the prompt would exceed 111 tokens, without cutting a term.
- **Order:** it SHALL place the highest-listed term last, nearest the audio.
- **No hint:** no hint SHALL be sent:
  - when another dictation language is chosen
  - when Parakeet is selected
  - when no term is enabled
- **No leaks:** the hint text SHALL never appear in the transcript.

#### Scenario: Whisper with English
- **GIVEN** Whisper is selected, the dictation language is English, and the vocabulary lists "Pluto TV" and "Jira"
- **WHEN** the user dictates
- **THEN** Whisper is decoded with a prompt made of those terms, and the pasted text contains no glossary text the user didn't say

#### Scenario: Another language chosen
- **GIVEN** Whisper is selected and the dictation language is Italian
- **WHEN** the user dictates
- **THEN** no vocabulary hint is given to Whisper, and the corrections still apply

#### Scenario: Long list
- **GIVEN** the vocabulary has 200 enabled terms
- **WHEN** the hint is built
- **THEN** it holds as many terms from the top of the list as fit in 111 tokens, each term whole

#### Scenario: Parakeet
- **GIVEN** Parakeet is selected
- **WHEN** the user dictates
- **THEN** no hint is built, and the corrections still apply
