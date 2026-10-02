## Context

`CleanupService` builds each prompt with `UserInput(chat: [.system(prompt), .user(transcript)])` and `context.processor.prepare(input:)`.

- **Where the template comes from:** swift-transformers (`Hub.swift`, `LanguageModelConfigurationFromHub`) merges `chat_template.jinja`, or failing that `chat_template.json`, into the tokenizer config.
- **What happens without one:** `applyChatTemplate` throws `missingChatTemplate`. `LLMModelFactory` catches it and falls back to joining the message contents with `"\n\n"`. No `<|im_start|>` markup is produced and no assistant turn is opened.

## Decisions

### 1. Download the template file; no other loading changes

The library already prefers `chat_template.jinja`, so the fix is to download it.

- `ModelDownloader.mlxFiles(in:)` becomes a pure, tested function.
- It adds the `jinja` extension to the allowed set.
- It still skips `README.md`, `.gitattributes` and other files the app doesn't need.

### 2. "Installed" requires a chat template for MLX models

`ModelInstaller.isMLXComplete(at:)` now also requires `hasChatTemplate(at:)`. That is either:
- a non-empty `chat_template` string in `tokenizer_config.json`, or
- a `chat_template.jinja` / `chat_template.json` file.

Every MLX model Honyaku offers is a chat model used for cleanup or rewrites, so the rule applies to all of them.

`CleanupService.loadModel()` keeps using `isMLXComplete`. This matters: a model loaded without a template stays cached in memory. If warm-up loaded the 4B before the repair finished, cleanups would keep using the template-less tokenizer until the next launch. Refusing to load until the template is there avoids that.

### 3. Fetch only what's missing

`ModelDownloader` downloads each file to a temporary location and moves it into place only when it's complete. So a file that's already in the model folder is a finished download.

- The downloader skips files that already exist and aren't empty.
- The disk-space check counts only what's left to fetch.

The result:
- A repair fetches the 4 KB template, not 2.3 GB.
- "Resume download" for an interrupted MLX download continues from the files it has, as the base spec's "resumes" wording already expects.

`download(model:to:progress:)` takes a target folder, defaulting to `ModelStore`'s folder for the model, so tests never write to the real models folder.

### 4. Repair at launch, shown like a migration download

- `warmUp()` calls `models.repairChatTemplateIfNeeded(selectedCleanupModel)`.
- `ModelDownloads` checks `ModelInstaller.needsChatTemplateOnly(at:)`: the weights, config and tokenizer are present and only the template is missing. If so, it starts the same visible background download used for migrations, with progress on `AppState.modelDownloads`, and Settings > General and the model row show it.
- `ModelAvailability` gets the requirement with a default no-op extension, so existing fakes and other branches' fakes are unaffected.
- Only the selected cleanup model is repaired at launch.
- An installed but unselected 4B shows "Resume download" in Settings > Models, which now fetches just the template.

### 5. Until the template arrives: cleanup is skipped, never degraded

Because `isInstalled` is false until the template is there, the existing pipeline path applies. Cleanup is skipped, the words are pasted with English fillers removed, and the download is started or joined. This is the same as the base spec's "Dictating while the migrated cleanup model downloads".

Offline, each dictation pastes the uncleaned words and the download error is shown, until the template can be fetched.

**Alternative considered:** keep cleaning up with the plain-text fallback until the repair finishes. Rejected, because a degraded prompt would quietly lower quality, and rewrites in particular would suffer.

### 6. Tests use temporary model folders

`ModelDownloaderTests` called `download(model:)`, whose destination is the user's real models folder, so every unit-test run left `cleanup/*_test_*` folders in `~/Library/Application Support/Honyaku/Models` (150 on the developer's Mac). Each test now downloads into its own temporary folder through the existing `download(model:to:)`, created in `setUp` and removed in `tearDown`. The network is always the mock `URLProtocol`. This follows the requirement "Tests never touch the user's real data" (change `dictation-stages`); no production code changes. The leftover folders already on disk aren't deleted by this change.

### 7. Review fixes

- **Only 2xx responses are saved.** `downloadFile` requires an `HTTPURLResponse` with a status in 200..<300 before moving the body into place; anything else throws `.downloadFailed(URLError(.badServerResponse))` and URLSession deletes the temporary file. Decision 3's "a file on disk is a finished download" depends on this: without it, a 404 page saved as `chat_template.jinja` would count as a template and never be fetched again. The repo listing request checks its status the same way.
- **Safe file names.** Every name, from the repo listing or the registry, goes through `ModelInstaller.isSafePathPart` (relative, no empty, `.` or `..` component) before it's downloaded; others are skipped. `jinja` also matches files like `additional_chat_templates/*.jinja`, so the listing can hold nested names.
- **A repo without a template.** After an MLX download, weights present but no template throws `ModelDownloadError.noChatTemplate(model)`, whose message says what to do. `ModelDownloads` shows that message (not the "check your connection" wrapper), logs it, and remembers the model for the rest of the launch so neither the pipeline nor Settings retries it. A relaunch tries again, in case the repo gained a template.
- **Saying why cleanup was skipped.** When `llmStage` skips cleanup because its model isn't installed, it adds a notice: "Cleanup is off until <Model> finishes downloading." (or the no-template message for a model that has none). This applies to any cleanup model still downloading, not only a template repair, because the user sees the same thing either way: words pasted without cleanup.
- **Warm-up after a repair.** `repairChatTemplateIfNeeded(_:onRepaired:)` runs a closure on the main actor when the repair succeeds; `warmUp()` passes one that prepares the cleanup model when cleanup is on.
- **Testability.** `ModelDownloads` takes the model folder and the installed check as parameters (defaulting to `ModelStore` and `ModelInstaller`), so its repair is unit-tested against a temporary folder with a fake install step.

## Risks / Trade-offs

- **A file on disk that's present but corrupt is never fetched again.** This was already the case for MLX, which has no checksums and never had a forced path. Deleting the model in Settings and downloading it again recovers.
- **An install that's offline at launch** dictates without cleanup until it's back online. That is accepted, and is the same as any cleanup model that's still downloading.
