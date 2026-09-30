## MODIFIED Requirements

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
- **THEN** Parakeet starts downloading in the background, and Settings > General and the Parakeet row in Settings > Models show "Downloading Parakeet TDT 0.6B v2" with its progress

#### Scenario: Dictating while the migrated speech model downloads
- **WHEN** the user dictates while Parakeet is still downloading
- **THEN** the dictation returns at once with "Downloading Parakeet TDT 0.6B v2, N%", Control keeps working, and no second download starts

#### Scenario: Dictating while the migrated cleanup model downloads
- **WHEN** the user dictates while the new cleanup model is still downloading
- **THEN** the transcript is pasted without cleanup (English fillers removed)

---

## ADDED Requirements

### Requirement: First run recommends a model set for the Mac
The Models step of first run SHALL preselect one recommended speech model and one cleanup model based on the Mac's physical memory. It SHALL show their names, total download size and one plain-language line each on what they do. "Choose models myself" SHALL reveal every available model, with its size, languages and relative speed. A model that needs 16 GB of memory SHALL say so wherever it's offered, in first run and in Settings.

#### Scenario: Mac with 8 GB of memory
- **WHEN** first run reaches the Models step on an 8 GB Mac
- **THEN** the recommended set is the registry's default for Macs under 16 GB, and its total download size is shown

#### Scenario: A model that needs more memory
- **WHEN** the user opens "Choose models myself" or Settings > Models
- **THEN** the larger cleanup model reads "Most accurate, needs 16 GB of memory"

#### Scenario: User chooses models manually
- **WHEN** the user clicks "Choose models myself" and picks a different cleanup model
- **THEN** the pick replaces the recommendation, and the total size updates

---

### Requirement: Model and dictation settings apply without relaunch
Changes in Settings to the active speech model, the active cleanup model, cleanup on/off, speaker labels on/off, or the cleanup prompt SHALL take effect for the next dictation, without relaunching Honyaku.

#### Scenario: User switches the cleanup model
- **WHEN** the user chooses "Use" on a different downloaded cleanup model and then dictates
- **THEN** that dictation is cleaned up by the newly chosen model

#### Scenario: User turns cleanup off
- **WHEN** the user turns cleanup off in Settings and then dictates
- **THEN** the raw transcript is pasted without cleanup

---

### Requirement: Files from retired models can be removed
The Settings Models tab SHALL list model files left by earlier versions of Honyaku that the current registry no longer offers (the Whisper tiny.en, small.en and small models, and the Qwen 2.5 models), with their size on disk and a "Move to Trash" button. Only these known folders SHALL be listed. Files SHALL go to the Trash, not be deleted outright, so a mistake can be undone. If moving to the Trash fails, the row SHALL say so. The section's footer SHALL say that another app using WhisperKit may use the same Whisper files, because WhisperKit's download folder is shared.

#### Scenario: Old Qwen 2.5 files are present
- **GIVEN** `qwen-3b-mlx` from an earlier version is still in the cleanup models folder
- **WHEN** the user opens Settings > Models
- **THEN** "Qwen 2.5 3B" is listed under "Older models" with its size, and "Move to Trash" moves the folder to the Trash

#### Scenario: Moving to the Trash fails
- **WHEN** "Move to Trash" can't move a folder (for example, it's locked)
- **THEN** the row stays listed and shows that it couldn't be moved

#### Scenario: Nothing retired on disk
- **WHEN** no retired model folders exist
- **THEN** the "Older models" section isn't shown
