## Why

Qwen3-4B-Instruct-2507 was installed without its chat template, so every cleanup and every rewrite with it runs on a plain-text prompt instead of the chat format the model was trained on.

- **The repo:** `mlx-community/Qwen3-4B-Instruct-2507-4bit` keeps its template in a separate `chat_template.jinja`. Qwen3-1.7B keeps it inside `tokenizer_config.json`.
- **The installer:** `ModelDownloader` only fetches files ending in `safetensors`, `json`, `txt`, `model` or `tiktoken`, so `chat_template.jinja` was never downloaded.
- **The library:** swift-transformers reads `chat_template.jinja` when it's there. When no template is found, mlx-swift-lm prints "No chat template was included or provided…" and joins the system prompt and the transcript with a blank line. The model gets no system/user/assistant markup and no generation prompt.
- **Why nobody noticed:** the "installed" check never looked for a template, so the model counted as installed.

The faithfulness check hid most of the damage for word-for-word cleanup, but rewrites (`rewrite-modes`) depend on the model following instructions. This fix lands before Rewrite.

## What Changes

- The MLX file list includes chat templates (`chat_template.jinja`, `chat_template.json`).
- An MLX cleanup model counts as installed only when it has a chat template, either inside `tokenizer_config.json` or as a separate file.
- MLX downloads fetch only the files that aren't already on disk. A repair or a resumed download no longer downloads every file again.
- At launch, if the selected cleanup model is missing only its chat template, Honyaku fetches that file in the background and shows it the same way as the migration downloads.
- Until the template arrives (for example while offline), cleanup is skipped and the speaker's words are pasted, as for any cleanup model that's still downloading. It is never run without its template.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `model-management`: adds "A cleanup model is installed only with its chat template".

## Impact

- `Services/ModelDownloader.swift`: the file filter, skipping files already on disk, and a target-folder parameter so tests and the integration test never write to the real models folder.
- `Services/ModelInstaller.swift`: the chat-template check, plus `needsChatTemplateOnly(at:)`.
- `Services/ModelDownloads.swift`: `repairChatTemplateIfNeeded(_:)`.
- `Pipeline/TranscriptionPipeline.swift`: `warmUp()` calls the repair for the selected cleanup model.
- `Services/Protocols`: `ModelAvailability` gains the repair call, with a default that does nothing.
- `Services/CleanupService.swift`: `chatPromptText(modelDirectory:system:user:)`, which builds the prompt text with the tokenizer only. The integration test uses it, because the test bundle can't link swift-transformers' `Hub` directly.
- Tests: unit tests use temporary folders and a mock session. The integration test copies the installed model into a temporary folder and fetches only the template there.

## Out of scope

- Re-checking existing files against checksums. MLX models have no published checksums in the registry, as before.
- `ModelDownloaderTests` still create `*_test_*` folders in the real models folder. This predates the change and is logged as a follow-up.
