## 0. Prerequisite

- [ ] 0.1 Rebase onto main after dictation-stages merges; adopt its final type names (DictationContext, TextStage, CleanupRequest) in this design if they differ

## 1. Store

- [ ] 1.1 `VocabularyTerm` and `VocabularyFile` (version 1) Codable types
- [ ] 1.2 `VocabularyStore(directory:)`: load, save (atomic, 0600, excluded from backup), change publishing, corrupt-file rename and recovery
- [ ] 1.3 Validation: trim, non-empty, ≤100 chars, unique term, unique heard-as (naming the clashing term)
- [ ] 1.4 Import merge (by term ignoring case; union heard-as; append new; never delete; skip clashes) returning a summary; export
- [ ] 1.5 Unit tests for 1.1–1.4 in a temporary directory

## 2. Corrections

- [ ] 2.1 `VocabularyMatcher`: candidates (heard-as + self), case/apostrophe folding, word boundaries, whitespace runs, punctuation and possessive kept, longest match, list-order ties, single pass, speaker labels skipped
- [ ] 2.2 Register it as the first post-transcription stage; the pipeline reads the current list at the start of each dictation
- [ ] 2.3 Unit tests for every matcher rule and for the stage through the pipeline with fakes; performance test (500 terms, one-minute transcript, under 5 ms)

## 3. Whisper hint

- [ ] 3.1 `WhisperHintBuilder`: enabled terms from the top, reverse order, comma-separated, encode with the tokenizer, filter special tokens, stop before 111 tokens without cutting a term; cached per vocabulary version
- [ ] 3.2 `WhisperKitEngine`: set `promptTokens` (and `usePrefillPrompt`) only for English or Auto-detect; never for another language or Parakeet
- [ ] 3.3 An estimate mode (4 characters per token) for the tab when the tokenizer isn't loaded
- [ ] 3.4 Unit tests for the builder with a fake tokenizer; integration test on a fixture clip (spelling, no echo, latency recorded)

## 4. Prompt rule

- [ ] 4.1 Add "Write these terms exactly as listed: …" (top 40 enabled terms) to `CleanupRequest.extraRules`; expose it for rewrite prompts
- [ ] 4.2 Unit tests: present with terms, absent without, capped at 40; faithfulness passes for a corrected term

## 5. Settings > Vocabulary

- [ ] 5.1 Add the Vocabulary tab after Dictation (tab order General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy)
- [ ] 5.2 Table: on/off, term, heard as, "In speech hint" mark (approximate when estimated); search; add, inline edit, delete; drag reorder plus Move up / Move down; keyboard and VoiceOver
- [ ] 5.3 Validation messages, empty state, corrupt-file notice, footer copy
- [ ] 5.4 Import… / Export… with save and open panels, merge summary, error on an invalid file

## 6. History

- [ ] 6.1 "Add to vocabulary…" in the History row context menu and visible actions; the sheet (transcript, Heard as, Write it as); merge into an existing term
- [ ] 6.2 UI test: add a term from History, then see it in the Vocabulary tab (with the test launch argument, never the user's real data)

## 7. Gates

- [ ] 7.1 `xcodegen generate`; clean build with no warnings in project code; unit tests; UI tests; `openspec validate custom-vocabulary --strict` (every build and test through the shared build lock)
- [ ] 7.2 Developer: dictate with Parakeet and Whisper using a real list; check the Whisper hint doesn't echo terms on short clips; import and export a list
