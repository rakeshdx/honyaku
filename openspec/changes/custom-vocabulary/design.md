## Context

The decisions behind this design were settled on 2026-10-01 (Q8–Q10, Q24, Q25, Q29, Q30). It builds on the merged `dictation-stages` groundwork (PR #7), and plugs in only through its own slot:
- `Pipeline/Stages/VocabularyStages.swift`: `VocabularyStages.make(_ environment:)` returns a preparer and an `afterTranscription` stage. No other pipeline file changes.
- `FeatureEnvironment.store(VocabularyStore.self)`: the one shared store, used by the stages and the Settings tab. Its folder is `environment.directory` (Application Support/Honyaku in the app, a temporary folder in tests and UI-test launches).
- `DictationContext.speechHints.glossary`: the Whisper hint, most important term last. `DictationContext.speechModelID` and `speechHints.language` tell the preparer whether Whisper is in use and which language was chosen.
- `DictationContext.cleanupRules`: `llmStage` passes these as `CleanupRequest.extraRules`. Rewrite (`rewrite-modes`) reads the same `context.cleanupRules` for its prompts, so it gets the vocabulary rule with no vocabulary-specific code.

## Goals / Non-Goals

**Goals**
- Listed terms are written exactly as listed, whichever speech engine is used.
- Corrections are deterministic and predictable, and work without the cleanup model.
- The list is easy to grow from real mistakes, and easy to share.
- Nothing leaves the Mac.

**Non-Goals**
- Parakeet decode-time boosting (a follow-up).
- Per-website lists.
- Automatic learning.
- Fuzzy or phonetic matching. Only listed spellings are corrected.

## Decisions

### 1. Store
- **File:** `vocabulary.json` in `FeatureEnvironment.directory` (`~/Library/Application Support/Honyaku/` in the app). `VocabularyStore` is a `FeatureStore`, created from the environment, so tests and UI-test launches use a temporary folder and never the user's real data.
- **Format:**
  ```json
  { "version": 1,
    "terms": [ { "id": "…uuid…", "term": "Paramount+", "heardAs": ["paramount plus"], "enabled": true } ] }
  ```
  Array order is the user's order: the top of the list is the most important.
- **Writes:** atomic, mode 0600, excluded from backup, the same as `history.json`.
- **Corrupt file:**
  - It is renamed to `vocabulary.corrupt-<ISO date>.json`, and the app starts with an empty list.
  - If the rename fails, the store keeps the damaged file and stops saving (edits apply until quit), and the tab reads "Couldn't set aside the damaged vocabulary file. Changes won't be saved until it's fixed or removed." The damaged file is never overwritten.
- **Save failures:** logged with `Logger` (metadata only, never terms) and shown in the tab: "Couldn't save your word list: <reason>. Your changes apply until you quit Honyaku."
  - The Vocabulary tab shows "Your word list couldn't be read. It was saved as vocabulary.corrupt-….json, and Honyaku started a new one." until the user dismisses it.
  - Dictation is never blocked by a bad file.
- **Validation on edit:**
  - A term is trimmed, non-empty and at most 100 characters.
  - Terms are unique ignoring case; a duplicate is refused with "Already in your list".
  - A heard-as spelling is trimmed, non-empty, and unique across the list ignoring case. A heard-as spelling that's already used by another term is refused, naming that term.
- **Change notification:** the store is `@Observable`, so the tab updates as it changes. The stages hold the store, not a copy, so edits apply to the next dictation without relaunching. The matcher and rule are rebuilt only when the list changes.
- **One list per dictation (review fix):** the preparer takes a snapshot when the dictation starts: the matcher (into a `VocabularySnapshot` shared by the preparer and the correction stage) and `context.vocabularyTerms`. The correction stage uses that snapshot, so an edit in Settings during a dictation applies to the next one. Dictations never overlap (the pipeline's busy guard), so one shared snapshot box is enough.
- **`context.vocabularyTerms` (review fix):** every enabled term, for every engine and language. Other features read it: Per-app's first-letter rule protects these terms, and cleanup protects them in the word-for-word check (Decision 4). `speechHints.glossary` stays Whisper-only.

### 2. Matching (`VocabularyMatcher`)
- **Candidates:** for every enabled term, each of its heard-as spellings plus the term itself all map to the term as written. That's how "jira" → "Jira" works with no heard-as entry.
- **Case:** case-insensitive and diacritic-sensitive, with curly and straight apostrophes treated as the same.
- **Whole words or phrases:**
  - A match must not have a letter or digit immediately before it or after it.
  - Spaces inside a multi-word spelling match any run of whitespace in the transcript.
  - Punctuation next to a match is kept: "jira," → "Jira,".
  - A possessive "'s" or "’s" straight after a match is kept: "jira's" → "Jira's".
  - **Contractions (review fix):** a match followed by an apostrophe and a letter is rejected, unless it's a possessive "'s" followed by a non-word character. So the term "Don" leaves "don't" alone, and "Won" leaves "won't".
  - **Scripts (review fix):** a change of script counts as a boundary, and a Han, Hiragana, Katakana or Hangul character next to a match counts as a non-word character, since those scripts don't put spaces between words: "githubを使う" → "GitHubを使う".
  - **Links and code (review fix):** a whitespace-delimited token containing "://", "@", "/", "_" or a "." between two letters (a domain) is never changed: "github.com/acme", "a@jira.com" and "jira_client" stay as they are.
- **Longest match first:** scanning left to right, at each position the longest candidate (by characters) wins. On a tie, the term higher in the list wins. Text that's been replaced is not scanned again (one pass), so a term's output can't trigger another rule.
- **Speaker labels:** `[Speaker N]` labels are never altered.
- **Speed:** the matcher is built once per list change. A one-minute transcript with 500 terms is corrected in under 5 ms on M1 in a release build. The unit test uses `measure {}` rather than a wall-clock assertion, which was flaky in Debug builds on a busy machine.
- **Placement:** this is `VocabularyStages`' `afterTranscription` stage, the first one, since Vocabulary's slot comes first in `PipelineStages.live` (groundwork `dictation-stages`, Decision 3). It runs after speaker labels are merged in, because the merge rebuilds the text, and before cleanup. As a result:
  - The faithfulness check compares against the corrected text, so cleanup output keeping "Paramount+" passes.
  - History's raw text keeps the speech model's original output (groundwork Decision 3). That's what makes "Add to vocabulary…" useful: the row shows how a word was misheard. The cleaned text has the corrected spellings.
  - Rewrites (`rewrite-modes`) start from corrected text.

### 3. Whisper hint
- **When:** only when the selected speech engine is Whisper and the dictation language is English or Auto-detect (Q9). With any other language chosen, or with Parakeet, no hint is sent.
- **Who does what:**
  - The preparer decides whether to send a hint (`context.speechModelID`'s engine is WhisperKit; `speechHints.language` is nil or English) and sets `speechHints.glossary` to every enabled term, the top of the list last.
  - `WhisperKitEngine` turns the glossary into prompt tokens with `WhisperHint.promptTokens(glossary:encode:)`, a pure function: it takes terms from the end of the glossary (the top of the list) while the whole prompt fits in 111 tokens. It's the only change to the engine.
- **Contents:** enabled terms only (never heard-as spellings), as a comma-separated glossary: `" Paramount+, Pluto TV, Jira"`. It's a list, not an instruction, so Whisper treats it as earlier speech rather than something to echo.
- **Token limit:** WhisperKit 0.18.0 keeps only the last 111 prompt tokens (`TextDecoder.swift:339-340` trims with `.suffix`).
  - The builder adds terms from the top of the list down and stops before a term would push the total past 111. Terms are never cut mid-word.
  - It writes the chosen terms in reverse, so the top term is last, nearest the audio, and the last thing WhisperKit would trim.
- **Tokens:**
  - Built with the loaded model's tokenizer: `tokenizer.encode(text:)`, keeping only tokens below `specialTokens.specialTokenBegin`.
  - Set as `DecodingOptions.promptTokens`, with `usePrefillPrompt = true` (already the default).
  - The engine caches the tokens for the last glossary, so an unchanged list isn't re-encoded on every dictation.
- **WhisperKit 0.18.0 bug, worked around:** with any prompt, WhisperKit applies its blank filter (which stops end-of-text being the first token) at the prefill-cache index, which is 0 whenever prompt tokens are used, instead of at the first sampled token. Found by the integration test: every prompted dictation, even a one-token prompt, came back empty. `WhisperPromptBlankFilter` (a custom `LogitsFiltering`, installed on the decoder the first time a hint is built) suppresses end-of-text and a blank first token in windows that start with `<|startofprev|>`, and only at the first sampled position: right after the prefill, which ends with the timestamp (or no-timestamps) token. That's exactly what WhisperKit's own filter does without a prompt, and what OpenAI's reference does. Windows without a prompt are untouched. Drop it once WhisperKit fixes the index.
  - **Review fix:** the first version kept suppressing end-of-text until a word was sampled. That forced Whisper to produce a word in a window with no speech (the trailing window of a dictation over 30 s), often a glossary term. An engine-level integration test now runs a sentence followed by 30 s of silence with a glossary and checks no glossary word is added.
- **Side effects:**
  - The prompt disables WhisperKit's prefill KV cache, a small latency cost: about 70 ms on a 3 s clip on an M3 Max (0.80 s → 0.87 s), measured in the integration test.
  - Prompt text never appears in the transcript, because segment text starts at SOT.
  - Language detection with `detectLanguage` looks only at SOT, so detection is unaffected.
- **"In speech hint" mark in the tab:**
  - The tokenizer lives inside the speech engine, which the Settings tab can't reach, so the tab always uses an estimate: `WhisperHint.estimatedTermCount(_:)`, about one token per 4 characters, plus one for each separator. The spec says so too (review fix).
  - The tab says the mark is approximate. The exact cut is made with the real tokenizer at each dictation.

### 4. Prompt rule
- **When:** the list has at least one enabled term.
- **Content:** the preparer appends "Write these terms exactly as listed: Paramount+, Pluto TV, Jira." to `context.cleanupRules`, which becomes `CleanupRequest.extraRules`. That's the top 40 enabled terms in list order.
- **Prompt cache:** the rule changes the prompt, so the cleanup prefix cache is rebuilt when the list changes. That's fine, because edits are rare.
- **Rewrites:** the rule is in `context.cleanupRules` for every dictation, so `rewrite-modes` adds it to every rewrite prompt by passing `context.cleanupRules` on (Q29). `VocabularyStore.promptRule` exposes the same text.
- **Faithfulness:** the rule never relaxes the faithfulness check. It only steers the model towards the spellings already in the text.
- **Protected terms (review fix):** the word comparison ignores letter case and characters like "+", so "Paramount+" → "Paramount" used to pass. `CleanupRequest.protectedTerms` (from `context.vocabularyTerms`) makes `CleanupService.accept` reject strict output with fewer exact occurrences of a term than its input. It applies only to `.strict`; rewrites, with faithfulness off, aren't checked.

### 5. Settings > Vocabulary tab
- **Tab order (Q30):** General, Models, Dictation, **Vocabulary**, Rewrite, Apps, History, Privacy. Rewrite and Apps arrive in their own changes. Each change adds its own tab case, and the one-line conflict is resolved at merge.
- **Contents:**
  - **Search:** a search field filters by term or heard-as.
  - **Table:**
    - Columns are On (checkbox), Term, Heard as (comma-separated), and an "In speech hint" mark.
    - Rows reorder by drag, and by "Move up" / "Move down" in the context menu for keyboard and VoiceOver users.
  - **Editing:**
    - Add (+) opens a small sheet: Term, then Heard as (comma-separated), with the validation message under the fields. A sheet is used rather than an inline row because it keeps keyboard focus, Return and Escape simple and VoiceOver-friendly.
    - Edit uses the same sheet: the row's edit button, the context menu, or a double-click. Delete uses the row's button, the context menu or ⌫, and needs no confirmation for a single term.
  - **Footer:**
    - The footer reads: "Honyaku writes these terms exactly as listed. With Whisper, the terms marked 'In speech hint' are also suggested to the speech model."
    - Import… and Export… buttons sit here.
- **Export:** writes the same JSON format via a save panel, by default `Honyaku Vocabulary.json`.
- **Import:**
  - Refuses files over 1 MB or with more than 2,000 terms, with "A word list can have at most 2,000 terms and be at most 1 MB. Your list is unchanged." (review fix: an unbounded file froze the app, and with it the Control listener).
  - Merges in one pass using dictionaries keyed by folded spelling (term → index, spelling → owner), so the time is linear in the size of both lists.
  - Reads the JSON format, and merges by term, ignoring case:
    - An existing term gets the union of heard-as spellings, and its position and on/off state are kept.
    - A new term is appended at the end.
  - Nothing is ever deleted.
  - A heard-as spelling that clashes with another term is skipped and reported.
  - A summary follows: "Added 12 terms, updated 3, skipped 1 (already used by "Jira")."
  - An invalid file shows an error, and nothing changes.
- **Empty state:** "Add names, products and acronyms Honyaku should always spell your way." with an Add button.

### 6. "Add to vocabulary…" on History rows
- **Where:** a History row's context menu, and its visible action buttons, get "Add to vocabulary…".
- **Sheet contents:**
  - the transcript as the speech model heard it (`rawText`, review fix: it was the cleaned text, which already has the corrections and, for a rewrite, isn't the user's words at all), selectable
  - "Heard as", which can be left empty if only the case is wrong
  - "Write it as"
  - Cancel and Add
- **Merge:** if "Write it as" matches an existing term (ignoring case), the heard-as spelling is added to that term.
- **Past transcripts:** saving doesn't change them; the correction applies from the next dictation.

## Risks / Trade-offs

- **Whisper echoes glossary terms into near-silent clips.**
  - Mitigations:
    - The silence gate discards silent recordings before Whisper runs.
    - The hint is a plain list.
    - The 111-token cap.
  - The integration test checks that a short fixture clip with a glossary contains no glossary words that weren't spoken.
- **An English glossary nudging multilingual output toward English.** Mitigated by sending the hint only for English and Auto-detect.
- **A term that's also an ordinary word** (e.g. "Pluto") gets capitalised everywhere. This is accepted and documented in the footer copy: users control it by not listing such words.
- **Over-eager heard-as spellings** (e.g. "jeera" → "Jira" in a cooking note). Accepted: the user chose the spelling, and can delete it.

## Migration

None. With no `vocabulary.json`, the list is empty, and dictation behaves exactly as before.
