## ADDED Requirements

### Requirement: A cleanup model is installed only with its chat template
A cleanup (MLX) model SHALL count as installed only when, in addition to its configuration, tokenizer and every weight file, it has a chat template. The template SHALL be either a `chat_template` entry in `tokenizer_config.json` or a `chat_template.jinja` or `chat_template.json` file.

The installer SHALL download a repo's chat template files along with its other files. MLX downloads SHALL fetch only the files that are not already in the model's folder.

At launch, if the selected cleanup model is missing only its chat template, the system SHALL fetch just that file in the background and show its progress the same way as other background model downloads. It SHALL NOT download the weights again.

The system SHALL NOT run cleanup or rewrites with a model that has no chat template. Until the template is present, cleanup SHALL be skipped and the speaker's words pasted (with English fillers removed), as for a cleanup model that is still downloading.

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
