## ADDED Requirements

### Requirement: Vocabulary behaviour is covered by unit tests
Unit tests SHALL cover:
- **Matching:** whole words, phrases across whitespace, case, punctuation next to a match, possessives, longest match, ties by list order, one pass, disabled terms, speaker labels left alone.
- **The Whisper hint builder:** term order, the 111-token cap without cutting terms, terms only, no hint for other languages or Parakeet.
- **The prompt rule:** present only with enabled terms that occur in the transcript, capped at 40.
- **The store:** round trip, file permissions 600, backup exclusion, corrupt-file recovery, validation, import merge and its summary.

Tests SHALL use a temporary directory, and SHALL NOT read or write the user's real vocabulary, history or settings.

An integration test SHALL run Whisper on a fixture clip with a glossary. It SHALL check:
- the listed term is spelled as listed
- no glossary text the clip doesn't contain is added
- the latency with and without the hint, which is recorded

#### Scenario: Unit tests run
- **WHEN** `xcodebuild test -scheme HonyakuTests` runs
- **THEN** the vocabulary tests pass with no models downloaded, and `~/Library/Application Support/Honyaku/vocabulary.json` is not created or changed

#### Scenario: Whisper glossary integration test
- **WHEN** the integration tests run with Whisper downloaded
- **THEN** a fixture clip containing a listed term is transcribed with that term spelled as listed, and the transcript contains no glossary words the clip doesn't say
