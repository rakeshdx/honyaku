## ADDED Requirements

### Requirement: First run recommends a model set for the Mac
The Models step of first run SHALL preselect one recommended speech model and one cleanup model based on the Mac's physical memory. It SHALL show their names, total download size and one plain-language line each on what they do. "Choose models myself" SHALL reveal every available model, with its size, languages and relative speed.

#### Scenario: Mac with 8 GB of memory
- **WHEN** first run reaches the Models step on an 8 GB Mac
- **THEN** the recommended set is the registry's default for Macs under 16 GB, and its total download size is shown

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
The Settings Models tab SHALL list model files left by earlier versions of Honyaku that the current registry no longer offers (the Whisper tiny.en, small.en and small models, and the Qwen 2.5 models), with their size on disk and a "Move to Trash" button. Only these known folders SHALL be listed. Files SHALL go to the Trash, not be deleted outright, so a mistake can be undone.

#### Scenario: Old Qwen 2.5 files are present
- **GIVEN** `qwen-3b-mlx` from an earlier version is still in the cleanup models folder
- **WHEN** the user opens Settings > Models
- **THEN** "Qwen 2.5 3B" is listed under "Older models" with its size, and "Move to Trash" moves the folder to the Trash

#### Scenario: Nothing retired on disk
- **WHEN** no retired model folders exist
- **THEN** the "Older models" section isn't shown
