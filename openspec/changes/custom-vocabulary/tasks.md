## 0. Prerequisite

- [x] 0.1 Rebase onto main after dictation-stages merges; adopt its final type names (DictationContext, TextStage, CleanupRequest) in this design if they differ

## 1. Store

- [x] 1.1 `VocabularyTerm` and `VocabularyFile` (version 1) Codable types
- [x] 1.2 `VocabularyStore` (a `FeatureStore` from `FeatureEnvironment`): load, save (atomic, 0600, excluded from backup), change publishing, corrupt-file rename and recovery
- [x] 1.3 Validation: trim, non-empty, ≤100 chars, unique term, unique heard-as (naming the clashing term)
- [x] 1.4 Import merge (by term ignoring case; union heard-as; append new; never delete; skip clashes) returning a summary; export
- [x] 1.5 Unit tests for 1.1–1.4 in a temporary directory

## 2. Corrections

- [x] 2.1 `VocabularyMatcher`: candidates (heard-as + self), case/apostrophe folding, word boundaries, whitespace runs, punctuation and possessive kept, longest match, list-order ties, single pass, speaker labels skipped
- [x] 2.2 Register it in `VocabularyStages.make` as the `afterTranscription` stage; it reads the store's current list on every dictation
- [x] 2.3 Unit tests for every matcher rule and for the stage through the pipeline with fakes; performance test (500 terms, one-minute transcript, under 5 ms)

## 3. Whisper hint

- [x] 3.1 A `VocabularyStages` preparer sets `speechHints.glossary` (enabled terms, top last) for Whisper with English or Auto; `WhisperHint.promptTokens(glossary:encode:)`: comma-separated, special tokens filtered, as many terms from the top as fit in 111 tokens, never cutting a term
- [x] 3.2 `WhisperKitEngine`: set `promptTokens` (and `usePrefillPrompt`) from the glossary, caching the last result; the preparer never sends a glossary for another language or Parakeet
- [x] 3.3 `WhisperHint.estimatedTermCount` (about 4 characters per token) for the tab's approximate mark
- [x] 3.4 Unit tests for the builder with a fake tokenizer; integration test on a fixture clip (spelling, no echo, latency recorded)
- [x] 3.5 `WhisperPromptBlankFilter`: work around WhisperKit 0.18.0 emitting end-of-text first in every prompted window (found by 3.4)

## 4. Prompt rule

- [x] 4.1 The preparer adds "Write these terms exactly as listed: …" (top 40 enabled terms) to `context.cleanupRules` (→ `CleanupRequest.extraRules`); rewrite prompts get it from the same context
- [x] 4.2 Unit tests: present with terms, absent without, capped at 40; faithfulness passes for a corrected term

## 5. Settings > Vocabulary

- [x] 5.1 Add the Vocabulary tab after Dictation (tab order General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy)
- [x] 5.2 List: on/off, term, heard as, "In speech hint" mark (approximate); search; add and edit in a sheet, delete; drag reorder plus Move up / Move down; keyboard and VoiceOver
- [x] 5.3 Validation messages, empty state, corrupt-file notice, footer copy
- [x] 5.4 Import… / Export… with save and open panels, merge summary, error on an invalid file

## 6. History

- [x] 6.1 "Add to vocabulary…" in the History row context menu and visible actions; the sheet (transcript, Heard as, Write it as); merge into an existing term
- [x] 6.2 UI test: open the Vocabulary tab and add a term (with the test launch argument, never the user's real data). UI-test launches keep History in memory and empty, so adding from History is covered by unit tests of the store's merge instead

## 7. Gates

- [x] 7.1 `xcodegen generate`; clean build with no warnings in project code; unit tests (229 pass; history.json unchanged and no vocabulary.json created); UI tests (5 pass); the Whisper glossary integration test; `openspec validate custom-vocabulary --strict` (every build and test through the shared build lock)
- [ ] 7.2 Developer: dictate with Parakeet and Whisper using a real list; check the Whisper hint doesn't echo terms on short clips; import and export a list

## 8. Review fixes

- [x] 8.1 `context.vocabularyTerms` (every enabled term, any engine or language) and a per-dictation `VocabularySnapshot` used by the correction stage
- [x] 8.2 Matcher: contractions rejected (possessive kept), links/emails/paths/identifiers untouched, script changes and CJK as boundaries; tests
- [x] 8.3 `WhisperPromptBlankFilter` acts only at the first sampled position; engine-level integration test with 30 s of silence after a sentence
- [x] 8.4 `CleanupRequest.protectedTerms`: strict cleanup output losing an exact term occurrence is rejected; tests
- [x] 8.5 Import: 1 MB / 2,000-term limits with a clear error; linear merge; tests (2,000 terms, no wall-clock assertion)
- [x] 8.6 Corrupt file that can't be set aside: different notice, saving stops; save failures logged with `Logger` and shown in the tab
- [x] 8.7 "Add to vocabulary…" shows the raw text
- [x] 8.8 Matcher performance test uses `measure {}`; spec says the hint mark is always an estimate
- [x] 8.9 The last Settings tab is stored in the app's settings suite (`coordinator.features.defaults`), the same change as rewrite-modes, so UI tests never write the user's real settings
- [x] 8.10 Advisories: unused `VocabularyMatcher.isEmpty` removed; the term editor sheet in its own file; tests leave no temporary folders or suites behind
- [x] 8.11 Gates: clean build with no warnings in project code; 246 unit tests (history.json unchanged); 5 UI tests (the real settings file untouched); both vocabulary integration tests (models folder unchanged); `openspec validate --strict`
