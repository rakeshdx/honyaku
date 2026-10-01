## ADDED Requirements

### Requirement: The vocabulary stays on the device
The system SHALL store the vocabulary only in `~/Library/Application Support/Honyaku/vocabulary.json`:
- created with permissions 600
- written atomically
- excluded from backup

The vocabulary SHALL never be sent off the device. Using it, for corrections, the Whisper hint or prompt rules, SHALL make no network request. Exporting writes only the file the user chose.

#### Scenario: Vocabulary file created
- **WHEN** the user adds their first term
- **THEN** `vocabulary.json` is created with permissions 600 and flagged as excluded from backup

#### Scenario: Dictating with a vocabulary
- **GIVEN** the vocabulary has terms
- **WHEN** the user dictates with Whisper or Parakeet
- **THEN** no network request is made
