## ADDED Requirements

### Requirement: A cleanup model is installed only with its chat template
A cleanup (MLX) model SHALL count as installed only when, in addition to its configuration, tokenizer and every weight file, it has a chat template. The template SHALL be either a `chat_template` entry in `tokenizer_config.json` or a `chat_template.jinja` or `chat_template.json` file.

The installer SHALL download a repo's chat template files along with its other files. MLX downloads SHALL fetch only the files that are not already in the model's folder.

At launch, if the selected cleanup model is missing only its chat template, the system SHALL fetch just that file in the background and show its progress the same way as other background model downloads. It SHALL NOT download the weights again.

The system SHALL NOT run cleanup or rewrites with a model that has no chat template. Until the template is present, cleanup SHALL be skipped and the speaker's words pasted (with English fillers removed), as for a cleanup model that is still downloading. A dictation whose cleanup is skipped because its model is still downloading SHALL say so: "Cleanup is off until <Model> finishes downloading."

A model file SHALL be saved only from a successful (2xx) HTTP response. An error response (for example 404, 429 or 5xx) SHALL fail that download and leave no file behind, so a later attempt fetches it again. The installer SHALL download only files whose names are relative paths inside the model's folder: a name that is absolute or contains an empty, `.` or `..` component SHALL be skipped.

If a cleanup model's repo provides no chat template at all, the system SHALL tell the user once per launch: "<Model> has no chat template, so Honyaku can't use it for cleanup. Choose another model in Settings > Models." It SHALL NOT retry the download for that model again during the same launch.

After a launch repair succeeds, the system SHALL load the cleanup model in the background (when cleanup is on), as the launch warm-up does, so the next dictation doesn't pay the load time.

#### Scenario: Fresh install of Qwen3-4B
- **GIVEN** the repo keeps its chat template in `chat_template.jinja`
- **WHEN** the user downloads Qwen3-4B-Instruct-2507
- **THEN** `chat_template.jinja` is downloaded with the other files, and the model counts as installed

#### Scenario: An existing install is missing the template
- **GIVEN** Qwen3-4B-Instruct-2507 is the selected cleanup model and its folder has the weights but no chat template
- **WHEN** Honyaku launches with network access
- **THEN** only `chat_template.jinja` is downloaded, in the background with its progress shown, the weights are not downloaded again, and the next dictation is cleaned up using the chat template

#### Scenario: Offline with the template missing
- **GIVEN** the selected cleanup model is missing only its chat template and the Mac is offline
- **WHEN** the user dictates
- **THEN** the words are pasted without cleanup (English fillers removed), the model is not run without its template, and the template is fetched once the network is back (on the next launch or dictation)

#### Scenario: Resuming an interrupted download
- **GIVEN** a cleanup model download stopped after some weight files finished
- **WHEN** the user chooses "Resume download"
- **THEN** only the files that are missing are downloaded

#### Scenario: Qwen3-1.7B keeps its template in the tokenizer config
- **GIVEN** Qwen3-1.7B's `tokenizer_config.json` contains a `chat_template` entry and there is no separate template file
- **WHEN** the app checks whether the model is installed
- **THEN** it counts as installed

#### Scenario: The server returns an error page for the template
- **GIVEN** Hugging Face answers `chat_template.jinja` with 404, 429 or 500
- **WHEN** the template download runs
- **THEN** the download fails with no file saved, the model still doesn't count as installed, and the next attempt downloads the template again

#### Scenario: A repo lists an unsafe file name
- **GIVEN** a repo listing contains `../x.json` or `a/../../b.jinja`
- **WHEN** the model is downloaded
- **THEN** those names are skipped and nothing is written outside the model's folder

#### Scenario: A repo has no chat template
- **GIVEN** the selected cleanup model's repo has no template file and its `tokenizer_config.json` has no `chat_template`
- **WHEN** Honyaku launches and repairs the model
- **THEN** the user sees "<Model> has no chat template, so Honyaku can't use it for cleanup. Choose another model in Settings > Models." once, and Honyaku doesn't try to download it again until the next launch

#### Scenario: Dictating while the template repair runs
- **GIVEN** the launch repair of the selected cleanup model's template is still running
- **WHEN** the user dictates
- **THEN** the words are pasted without cleanup and the status says "Cleanup is off until Qwen3 4B finishes downloading."

#### Scenario: The model is ready right after the repair
- **GIVEN** cleanup is on and the launch repair has just fetched the template
- **WHEN** the repair finishes
- **THEN** the cleanup model is loaded in the background, and the next dictation is cleaned up without a model-load delay

