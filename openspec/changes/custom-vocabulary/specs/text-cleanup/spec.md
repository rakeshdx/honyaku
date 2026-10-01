## ADDED Requirements

### Requirement: The cleanup prompt asks the model to keep vocabulary terms exactly
When the vocabulary has at least one enabled term, the cleanup prompt SHALL include the rule "Write these terms exactly as listed:" followed by up to 40 enabled terms, from the top of the list. With no enabled term, the prompt SHALL contain no vocabulary rule. The same rule SHALL be available to any rewrite prompt. The rule SHALL NOT relax the check that rejects cleanup output changing the speaker's words.

#### Scenario: Vocabulary present
- **GIVEN** the vocabulary lists "Paramount+" and "Jira"
- **WHEN** a transcript is cleaned
- **THEN** the prompt sent to the model contains "Write these terms exactly as listed: Paramount+, Jira."

#### Scenario: No vocabulary
- **GIVEN** the vocabulary is empty
- **WHEN** a transcript is cleaned
- **THEN** the prompt contains no vocabulary rule

#### Scenario: Corrected term survives the faithfulness check
- **GIVEN** the vocabulary has "Paramount+" heard as "paramount plus"
- **WHEN** the user says "um paramount plus is live" and the model returns "Paramount+ is live."
- **THEN** "Paramount+ is live." is pasted, because the check compares against the corrected transcript

#### Scenario: Very long list
- **GIVEN** the vocabulary has 120 enabled terms
- **WHEN** a transcript is cleaned
- **THEN** the rule lists only the top 40
