## MODIFIED Requirements

### Requirement: Cleanup model can be changed after setup
The system SHALL allow the user to switch their active cleanup model in Settings at any time, with the same download flow as speech model switching.

#### Scenario: User switches to the Best cleanup tier
- **WHEN** the user selects Qwen3-4B-Instruct-2507 in Settings
- **THEN** the system downloads the model (showing its 2.3 GB size) and uses it for cleanup once the download completes

## ADDED Requirements

### Requirement: Old model selections move to the nearest new model
When a saved speech or cleanup selection refers to a model that is no longer offered, the system SHALL switch it at launch to the nearest current model:
- Whisper tiny.en and small.en → Parakeet
- Whisper small (multilingual) → Whisper large-v3-turbo
- Qwen 2.5 1.5B → Qwen3-1.7B
- Qwen 2.5 3B and 7B → Qwen3-4B-Instruct-2507

The new model is fetched on first use if it's not on disk. Old model files SHALL stay on disk until the user deletes them.

#### Scenario: Upgrading with Qwen 2.5 3B selected
- **GIVEN** the saved cleanup selection is Qwen 2.5 3B
- **WHEN** the updated Honyaku launches
- **THEN** the selection becomes Qwen3-4B-Instruct-2507, and the Qwen 2.5 files are untouched

---

### Requirement: The registry recommends models by memory
The model registry SHALL provide a recommended speech model and cleanup model for a given amount of physical memory:
- **Under 16 GB:** Parakeet and Qwen3-1.7B.
- **16 GB or more:** Parakeet and Qwen3-4B-Instruct-2507.

New installs SHALL default to the recommendation for the Mac they run on.

#### Scenario: 8 GB Mac
- **WHEN** the recommendation is requested for 8 GB
- **THEN** it returns Parakeet and Qwen3-1.7B

#### Scenario: 36 GB Mac
- **WHEN** the recommendation is requested for 36 GB
- **THEN** it returns Parakeet and Qwen3-4B-Instruct-2507

---

### Requirement: Model licences are credited
The system SHALL include the licence and attribution each model requires, including NVIDIA's CC-BY-4.0 attribution for Parakeet, in a licences notice bundled with the app and in the README.

#### Scenario: Parakeet attribution
- **WHEN** a user reads the app's licences notice
- **THEN** it credits NVIDIA for Parakeet TDT 0.6B v2 under CC-BY-4.0, with a link to the licence
