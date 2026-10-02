## ADDED Requirements

### Requirement: Per-app rules and the password guard are covered by unit tests
Unit tests SHALL cover:
- each formatting rule and their combinations;
- the property that rules never add, remove or reorder words;
- the first-letter exceptions;
- category lookup by bundle ID and override precedence;
- every row of the password-guard decision, including the terminal exception and fail-open;
- the paste-time routing order, through the pipeline with a fake guard probe and fake paste service;
- the rules store round-trip and damaged-file handling.

The tests SHALL use a temporary directory and SHALL NOT read or write the user's real Application Support files or settings. A UI test SHALL open Settings > Apps.

#### Scenario: Guard decision table
- **WHEN** the guard tests run
- **THEN** every combination of field subrole (secure, other, unreadable), secure-input owner (off, the front app, another app, unknown) and front-app category (terminal, other) produces the decision in the design's table

#### Scenario: Blocked text is never saved
- **GIVEN** a pipeline with a fake probe reporting a secure field
- **WHEN** a dictation finishes
- **THEN** the fake paste service receives nothing and the transcript store is unchanged

#### Scenario: Tests leave the user's files alone
- **WHEN** the unit tests run
- **THEN** `~/Library/Application Support/Honyaku/app-profiles.json` is neither created nor changed
