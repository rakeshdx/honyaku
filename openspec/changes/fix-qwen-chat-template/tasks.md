## 1. Spec

- [x] 1.1 Facts: the repo files (HF API), the downloader's extension filter, swift-transformers reading `chat_template.jinja`, mlx-swift-lm's plain-text fallback
- [x] 1.2 Proposal, design and the model-management delta; `openspec validate fix-qwen-chat-template --strict`

## 2. Installer

- [x] 2.1 `ModelDownloader.mlxFiles(in:)` (pure) includes `jinja`
- [x] 2.2 `download(model:to:progress:)` skips files already on disk; the disk-space check counts only what's left
- [x] 2.3 `ModelInstaller.hasChatTemplate(at:)`; `isMLXComplete` requires it; `needsChatTemplateOnly(at:)`

## 3. Repair at launch

- [x] 3.1 `ModelAvailability.repairChatTemplateIfNeeded(_:)` with a default no-op; `ModelDownloads` implements it through the visible background download
- [x] 3.2 `warmUp()` repairs the selected cleanup model

## 4. Tests

- [x] 4.1 Unit: the file filter; skipping existing files (mock session, temp folder); chat-template detection (tokenizer config entry, `.jinja`, `.json`, missing, empty); `needsChatTemplateOnly`
- [x] 4.2 Integration (`INTEGRATION_TESTS=1`): hard-link the installed 4B into a temp folder, confirm no chat prompt can be built, fetch only the template with the real downloader, then check the prompt has the chat markup (via `CleanupService.chatPromptText`, the same tokenizer loader cleanup uses). The real models folder is only read.
- [x] 4.3 Gates: clean build with no warnings in project sources; 198 unit tests with `history.json` unchanged; 4 UI tests; the integration test; `openspec validate --strict`

## 5. By hand

- [ ] 5.1 Relaunch Honyaku with Qwen3-4B selected: a short "Downloading Qwen3 4B" appears, `chat_template.jinja` lands in the model folder, and a dictation is cleaned up as before or better
