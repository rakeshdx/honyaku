# model-management Specification

## Purpose
TBD - created by archiving change honyaku-macos-app. Update Purpose after archive.
## Requirements
### Requirement: First-run setup wizard guides model selection
The system SHALL present a setup wizard on first launch that allows the user to select their preferred speech model and cleanup LLM before the main app UI is accessible. The wizard SHALL display model name, size, language support, and estimated speed for each option.

#### Scenario: User completes first-run setup
- **WHEN** the user selects a speech model and a cleanup model and clicks "Download & Start"
- **THEN** the system begins downloading the selected models, shows download progress, and transitions to the main app UI upon completion

#### Scenario: User launches the app after initial setup is complete
- **WHEN** the app launches and setup has already been completed
- **THEN** the system skips the wizard and opens directly to the menu bar state

---

### Requirement: Models are downloaded from Hugging Face and cached locally
The system SHALL download model files from the official Hugging Face repositories using `URLSession` and store them at `~/Library/Application Support/Honyaku/Models/<type>/<model-id>/`. Downloads SHALL be resumable and SHALL show progress.

#### Scenario: Network is available and model is not cached
- **WHEN** the user selects a model that has not been downloaded
- **THEN** the system downloads the model files with a progress indicator and resumes from the last byte if the download is interrupted

#### Scenario: Model is already cached
- **WHEN** the app starts and the selected model files are present in local storage
- **THEN** the system loads from cache without making any network request

---

### Requirement: Speech model can be changed after setup
The system SHALL allow the user to switch their active speech model in Settings at any time. Switching to a model not yet downloaded SHALL trigger a download prompt.

#### Scenario: User switches to a larger speech model
- **WHEN** the user selects a higher-quality speech model in Settings
- **THEN** the system prompts to download the new model (showing its size), and switches to it after download completes

---

### Requirement: Cleanup model can be changed after setup
The system SHALL allow the user to switch their active cleanup model in Settings at any time, with the same download flow as speech model switching.

#### Scenario: User switches to the Best cleanup tier
- **WHEN** the user selects Qwen3-4B-Instruct-2507 in Settings
- **THEN** the system downloads the model (showing its 2.3 GB size) and uses it for cleanup once the download completes

### Requirement: Downloaded models can be deleted to reclaim storage
The system SHALL provide a way to delete individual cached models from Settings, with a size indicator so users can make informed storage decisions.

#### Scenario: User deletes an unused model
- **WHEN** the user selects a cached model in Settings and clicks "Delete"
- **THEN** the system removes the model files from local storage and updates the available storage display

---

### Requirement: Model files are integrity-verified after download
The system SHALL verify the SHA-256 checksum of each downloaded model file against a checksum published in the model registry. If verification fails, the download SHALL be rejected, the partial file deleted, and the user prompted to retry.

#### Scenario: Downloaded model file passes integrity check
- **WHEN** a model download completes and the SHA-256 checksum matches the registry entry
- **THEN** the model is marked as available and the app activates it

#### Scenario: Downloaded model file fails integrity check
- **WHEN** a model download completes but the SHA-256 checksum does not match
- **THEN** the downloaded file is deleted, an error is shown ("Download corrupted, please retry"), and the download may be restarted

---

### Requirement: Download failures are handled gracefully
The system SHALL handle network errors, disk-full conditions, and interrupted downloads with clear user-facing messages and recovery options.

#### Scenario: Network error occurs mid-download
- **WHEN** a model download is interrupted by a network error
- **THEN** the system retains any downloaded bytes (for resumption), shows an error message with a "Retry" button, and does not mark the model as available

#### Scenario: Disk is full during download
- **WHEN** the system detects insufficient disk space to complete a download
- **THEN** the download is stopped, the partial file is deleted, and the user is shown a message indicating how much space is needed

---

### Requirement: Setup wizard cancellation is handled
The system SHALL handle the case where a user closes or cancels the first-run setup wizard before completing model selection. In this case, push-to-talk SHALL remain disabled and the wizard SHALL be re-presented on the next launch.

#### Scenario: User dismisses the setup wizard before selecting models
- **WHEN** the user closes the setup wizard window without completing model selection and download
- **THEN** the app enters a "setup incomplete" state, push-to-talk is disabled, and the wizard is shown again on the next launch

#### Scenario: User quits the app during model download in the wizard
- **WHEN** the app is force-quit while a first-run model download is in progress
- **THEN** on relaunch the wizard resumes showing the incomplete download state with a resume option

---

### Requirement: First-run setup requires network connectivity
The system SHALL check for network availability before presenting the model download step in the setup wizard. If no network is available, the system SHALL inform the user and provide a "Retry when connected" option.

#### Scenario: No internet connection during first-run wizard
- **WHEN** the device has no network connection when the user reaches the download step
- **THEN** the system shows an error: "An internet connection is required to download models. Connect and try again." and disables the "Download & Start" button until connectivity is detected

---

### Requirement: Hugging Face access token for diarization models is stored securely
SpeakerKit's CoreML models originate from Hugging Face repositories that may require an access token. If required, the user SHALL be prompted to provide a Hugging Face access token during first-run setup or when enabling diarization. The token SHALL be stored exclusively in the macOS Keychain and SHALL be used only for model file downloads. It SHALL never be used during runtime inference.

#### Scenario: User provides a valid HF access token
- **WHEN** the user enters a Hugging Face access token in the setup wizard or Settings
- **THEN** the token is stored in the macOS Keychain (not UserDefaults or any plaintext file) and used only for the model download request

#### Scenario: User revokes or deletes the HF access token
- **WHEN** the user clicks "Remove Token" in Settings
- **THEN** the token is deleted from the Keychain and any future model downloads requiring a token prompt the user again

#### Scenario: Runtime inference with no token
- **WHEN** the app performs speech transcription, cleanup, or diarization after setup
- **THEN** no Hugging Face token is read from the Keychain or used in any network call

---

### Requirement: Custom model paths are out of scope for v1
Loading user-supplied or third-party model files from arbitrary paths is explicitly NOT supported in v1. The system SHALL only load cleanup LLM models from the curated model registry (MLX-format safetensors from mlx-community). This constraint MAY be relaxed in a future version with appropriate format validation and security review.

#### Scenario: User attempts to load a custom model file
- **WHEN** a user asks to load a model file from outside the managed model storage
- **THEN** the app does not provide this capability in v1; only registry-managed models are available

---

### Requirement: No network access occurs during normal runtime operation
The system SHALL make no network requests during transcription, cleanup, or diarization. All model inference SHALL use locally cached files only.

#### Scenario: App is used with no internet connection after setup
- **WHEN** the device has no network access and push-to-talk is triggered
- **THEN** the system transcribes and cleans up text using cached models without any network error

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

