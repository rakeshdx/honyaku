## Context

The vocabulary preparer ran before transcription and added "Write these terms exactly as listed: <up to 40 enabled terms>" to `context.cleanupRules`. Both word-for-word cleanup and rewrites use those rules. For cleanup, the word-for-word check stops the model adding anything, so a long list only costs prompt tokens. Rewrites have no such check (`faithfulness: .none`), and on a two-word dictation the model used the listed terms as content.

## Decisions

### 1. The rule lists only the terms that occur in the transcript

The correction stage runs after transcription and the speaker-label merge. It now:
1. applies the matcher, as before;
2. finds which enabled terms occur in the corrected text, with `VocabularyMatcher.matchedTerms(in:)`;
3. adds the rule for those terms only, in list order, still capped at `VocabularyStore.promptRuleLimit` (40).

The preparer no longer adds the rule. With no term present, there's no rule, and the prompt (and its cache key) is the same as with an empty vocabulary.

`matchedTerms(in:)` reuses the corrections' scan: same folding, boundaries, contractions, links and code, and speaker labels. A term counts as present when any of its spellings matches. After the corrections that means the term as written, but checking every spelling also makes the function right for the invention check, where the model may write a heard-as spelling.

**Why after the corrections:** the rule protects spellings the model receives, which is the corrected text. The terms present before correction would miss heard-as spellings that are already fixed.

### 2. Rewrites need at least 4 words

`RewritePrompt.isTooShort(_:)` counts:
- words: whitespace-separated runs that contain a letter or digit, with speaker labels removed first;
- plus one word for every 2 characters of a script written without spaces (the same ranges `estimatedTokens` uses).

Under 4 is too short. So "P+" (1), "fix the bug" (3) and 「確認して」 (5 characters, 2 words) are too short, while "rename the build script" (4) and 「ログイン画面を確認して」 (11 characters, 5 words) are rewritten.

**Too short:** the pipeline's model step (`llmStage`) checks before the rewrite branch, so no rewrite model call is made. The dictation switches to plain dictation and goes through the dictation path, including word-for-word cleanup when it's on. The other fallbacks skip cleanup because a model has already failed; here none has run. Then English fillers and per-app rules, and it's saved to History as a dictation. The notice is "Too short to rewrite: used your words as dictated".

The user's History showed the same failure twice: "P plus" in cmux, and "Google.com" in Safari, which became a whole invented Jira ticket. Both are under 4 words.

**Why 4:** every template needs at least a verb and an object. Three-word asks ("fix the bug") are better pasted as said than padded. The threshold is a constant, `RewritePrompt.minimumWords`.

### 3. The invention check

After the echo stripping, the cut-short trim and the empty check, `RewriteStep` compares `matchedTerms(in: output)` with `matchedTerms(in: input)`, using the context's `vocabularyMatcher`, the one from the dictation's snapshot. If the output has any term the input doesn't, the rewrite fails: it falls back to plain dictation with "Couldn't rewrite without adding things you didn't say: used your words as dictated".

- **Only vocabulary terms are checked.** They are what the model was tempted with, and matching them is exact and cheap. Detecting invented content in general would need another model call or fuzzy heuristics, which the user didn't ask for.
- **With no vocabulary,** there's no matcher and the check is skipped.
- **Notices:** the fallback adds its notice like the others. The routing rules still apply: a blocked or History-only outcome shows only its own notice.

### 4. Changes to in-flight specs

`custom-vocabulary`'s "The cleanup prompt asks the model to keep vocabulary terms exactly" said "up to 40 enabled terms, from the top of the list". Its testing requirement said the rule is "capped at 40". `rewrite-modes` said the rewrite prompt gets "the vocabulary terms, when there are any". Those texts now say the rule lists the enabled terms that occur in the transcript (still at most 40). This avoids the archived specs contradicting this change. The new requirements live in this change, archived after `rewrite-modes`.

## Risks / Trade-offs

- **A term the model should have kept but that wasn't said** can't be in the rule. That's the point: it wasn't said.
- **A short real request** ("fix the bug") is no longer rewritten. The user gets the words as dictated plus a notice explaining why.
- **The invention check misses invented content that isn't in the vocabulary.** It targets the failure seen; the shared "never invent" rule still applies.
