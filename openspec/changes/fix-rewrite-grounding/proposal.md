## Why

A rewrite invented a whole task from two words. With the vocabulary Paramount+, P+ and POPS, the user held Control+Shift in cmux and said "P plus". Honyaku heard it correctly, and Vocabulary corrected it to "P+". The coding-agent prompt template then produced:

> Add P+ to the list of supported platforms. Make sure you verify the P+ integration works with the Paramount+ backend. Check that the POPS dashboard shows real-time data for P+ streams. Ensure the P+ configuration is synchronized with the Paramount+ service

Two causes:
- **The whole vocabulary went into the prompt.** The "Write these terms exactly as listed" rule listed every enabled term (up to 40), not just the ones the user said. With almost nothing to rewrite, the model used the list as material: "Paramount+ backend", "POPS dashboard".
- **No minimum length.** Two words can't become an agent prompt or a ticket, so the model padded them out despite the shared "never invent" rule.

## What Changes

- **Only terms you said:** the keep-these-terms rule lists only the enabled vocabulary terms that occur in the corrected transcript sent to the model, for both cleanup and rewrite. With none present, there's no rule.
- **Minimum length:** a rewrite needs at least 4 words, counting 2 characters of a script written without spaces (Japanese, Chinese, Thai and similar) as one word. A shorter one skips the model and goes through as plain dictation, with the notice "Too short to rewrite: used your words as dictated".
- **Invention check:** if a rewrite's output contains an enabled vocabulary term that the input didn't, the rewrite counts as failed. The words go through as plain dictation, with the notice "Couldn't rewrite without adding things you didn't say: used your words as dictated".

Not in this change: a stricter prompt rule ("return it unchanged if too short"), which the user chose not to add.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `text-cleanup`: adds "The keep-terms rule lists only terms that were said", "Rewrites need at least a few words" and "A rewrite never adds vocabulary terms that weren't said".
- `testing`: adds "Rewrite grounding is covered by tests".

The in-flight `custom-vocabulary` and `rewrite-modes` changes described the rule as "up to 40 enabled terms from the top of the list". Their text is updated to match, so the archived specs don't contradict this change.

## Impact

- `Vocabulary/VocabularyMatcher.swift`: `matchedTerms(in:)`, the terms that occur in a text, using the same matching as the corrections.
- `Vocabulary/VocabularyStageTypes.swift` and `VocabularyStore.swift`: the rule is built after the corrections, from the terms present. The matcher goes into the context for the invention check.
- `Pipeline/DictationContext.swift`: `vocabularyMatcher`.
- `Rewrite/RewriteStep.swift` and `RewriteTemplates.swift`: the minimum length, the invention check and two notices.
- Tests: unit, pipeline and one integration test.
