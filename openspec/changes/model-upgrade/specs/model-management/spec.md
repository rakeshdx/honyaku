## MODIFIED Requirements

### Requirement: Cleanup model can be changed after setup
The system SHALL allow the user to switch their active cleanup model in Settings at any time, with the same download flow as speech model switching.

#### Scenario: User switches to the Best cleanup tier
- **WHEN** the user selects Qwen3-4B-Instruct-2507 in Settings
- **THEN** the system downloads the model (showing its 2.3 GB size) and uses it for cleanup once the download completes

## ADDED Requirements

### Requirement: Old model selections move to the nearest new model
When a saved speech or cleanup selection refers to a model that is no longer offered, the system SHALL switch it at launch to the nearest current model, never larger than the memory-based recommendation (see "The registry recommends models by memory"):
- Whisper tiny.en and small.en → Parakeet
- Whisper small (multilingual) → Whisper large-v3-turbo
- Qwen 2.5 1.5B → Qwen3-1.7B
- Qwen 2.5 3B and 7B, and the old 0.8B build → Qwen3-4B-Instruct-2507 at 16 GB or more, otherwise Qwen3-1.7B

If a migrated-to model isn't on disk, the system SHALL start downloading it in the background at launch and show the download's progress. Until it has finished:
- a dictation that needs the speech model SHALL return straight away with a message naming the model and its progress, rather than starting its own download or waiting
- cleanup SHALL be skipped, and the speaker's words pasted (with English fillers removed)

Old model files SHALL stay on disk until the user deletes them.

#### Scenario: Upgrading with Qwen 2.5 3B selected on a 16 GB Mac
- **GIVEN** the saved cleanup selection is Qwen 2.5 3B and the Mac has 16 GB
- **WHEN** the updated Honyaku launches
- **THEN** the selection becomes Qwen3-4B-Instruct-2507, and the Qwen 2.5 files are untouched

#### Scenario: Upgrading with Qwen 2.5 3B selected on an 8 GB Mac
- **GIVEN** the saved cleanup selection is Qwen 2.5 3B and the Mac has 8 GB
- **WHEN** the updated Honyaku launches
- **THEN** the selection becomes Qwen3-1.7B

#### Scenario: Migrated model not yet downloaded
- **GIVEN** the saved speech selection was Whisper small.en and Parakeet isn't on disk
- **WHEN** the updated Honyaku launches
- **THEN** Parakeet starts downloading in the background, and the popover shows "Downloading Parakeet TDT 0.6B v2" with its progress

#### Scenario: Dictating while the migrated speech model downloads
- **WHEN** the user dictates while Parakeet is still downloading
- **THEN** the dictation returns at once with "Downloading Parakeet TDT 0.6B v2, N%", Control keeps working, and no second download starts

#### Scenario: Dictating while the migrated cleanup model downloads
- **WHEN** the user dictates while the new cleanup model is still downloading
- **THEN** the transcript is pasted without cleanup (English fillers removed)

---

### Requirement: Installing the same model twice at once shares one download
When a model is already being installed (for example by the launch download, a dictation or Settings), another request to install it SHALL wait for that install rather than start a second one, and SHALL NOT remove the files it is writing.

#### Scenario: Download clicked during the launch download
- **WHEN** Parakeet is downloading in the background and the user clicks Download for it in Settings
- **THEN** both wait on the same download, which completes once

---

### Requirement: Model deletion stays inside the model folders
Deleting a model SHALL only ever remove that model's own folder. A registry entry with an empty repository or variant, or with a ".." path component, SHALL be refused.

#### Scenario: Malformed registry entry
- **WHEN** a model whose variant is empty is deleted
- **THEN** nothing is removed and an error is returned

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
The system SHALL include the licence and attribution each model and library requires, including NVIDIA's CC-BY-4.0 attribution for Parakeet (with a link to the model page), in a licences notice bundled with the app (present in the built app's resources) and in the README.

#### Scenario: Parakeet attribution
- **WHEN** a user reads the app's licences notice
- **THEN** it credits NVIDIA for Parakeet TDT 0.6B v2 under CC-BY-4.0, with a link to the licence
