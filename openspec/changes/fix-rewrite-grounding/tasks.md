## 1. Spec

- [x] 1.1 Proposal, design, text-cleanup and testing deltas
- [x] 1.2 Align the in-flight custom-vocabulary and rewrite-modes text with "only terms that were said"; `openspec validate --all --strict`

## 2. Only terms you said

- [x] 2.1 `VocabularyMatcher.matchedTerms(in:)` sharing the corrections' scan
- [x] 2.2 The correction stage adds the rule for the present terms; the preparer no longer adds it; `VocabularyStore.promptRule(for:)`
- [x] 2.3 `DictationContext.vocabularyMatcher` from the snapshot

## 3. Rewrite guards

- [x] 3.1 `RewritePrompt.isTooShort(_:)` and `minimumWords`; the model step switches a too-short rewrite to plain dictation (cleanup included) with the too-short notice
- [x] 3.2 The invention check in `RewriteStep` with its notice

## 4. Tests

- [x] 4.1 Unit: rule selection, minimum length, invention check, notices
- [x] 4.2 Pipeline: the reported "P plus" case; the invention fallback
- [x] 4.3 Integration: a short agent-prompt rewrite with a temporary vocabulary never adds POPS or Paramount+
- [x] 4.4 Gates: clean build with no warnings in project sources; 405 unit tests (history unchanged); 9 UI tests; the 3 rewrite integration tests on Qwen3-4B; `openspec validate --all --strict` (16 of 16)

## 5. By hand

- [ ] 5.1 Control+Shift "P plus" in a terminal pastes "P+" with the too-short notice; a longer rewrite mentioning P+ doesn't add POPS or Paramount+
