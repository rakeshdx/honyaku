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
- **WHEN** the user selects the Qwen 2.5 7B MLX model in Settings
- **THEN** the system downloads the model (showing size warning for 4.3 GB) and begins using it for cleanup after download completes

---

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

