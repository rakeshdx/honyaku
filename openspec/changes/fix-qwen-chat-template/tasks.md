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

## 6. Tests use temporary model folders

- [x] 6.1 `ModelDownloaderTests` download into a per-test temporary folder (`download(model:to:)`), never the user's models folder; the success test also checks the downloaded file
- [x] 6.2 Audit: no other unit or UI test writes to the models folder (installer tests inject the install step; the others already use temporary folders); integration tests only read it
- [x] 6.3 Gates: clean build with no warnings in project sources; 198 unit tests with the models folder's `_test_` count (150) and `history.json` unchanged before and after; 4 UI tests; `openspec validate --strict`

## 7. Review fixes

- [x] 7.1 Spec: scenarios for error responses, unsafe names, a repo without a template, the skipped-cleanup notice and the warm-up after a repair; design Decision 7
- [x] 7.2 `downloadFile` and the repo listing require a 2xx `HTTPURLResponse`; mock tests: 404 and 500 leave no file, and a later attempt fetches it
- [x] 7.3 File names filtered through `ModelInstaller.isSafePathPart`; tests with `../x.json` and `a/../../b.jinja`
- [x] 7.4 `ModelDownloadError.noChatTemplate`; `ModelDownloads` shows its message once per launch and doesn't retry; test
- [x] 7.5 `llmStage` adds "Cleanup is off until <Model> finishes downloading." when cleanup is skipped for a missing model; test
- [x] 7.6 `repairChatTemplateIfNeeded(_:onRepaired:)`; `warmUp()` prepares cleanup after a repair; tests: `warmUp` asks for the repair (fake), `ModelDownloads` repairs a temporary folder and calls back
- [x] 7.7 Integration test's "real folder unchanged" check compares inode and modification date as well as size
- [x] 7.8 Gates: clean build with no warnings in project sources; 206 unit tests with `history.json` and the `_test_` count (165) unchanged; the chat-template integration test (the real 4B folder unchanged); `openspec validate --strict`; 4 UI tests pass (rerun after quitting the user's running Honyaku, which freed a menu bar slot)

