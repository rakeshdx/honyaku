## Why

Honyaku gets ordinary speech right, but names, products and acronyms are where dictation fails most at work: "paramount plus" for Paramount+, "pluto tv" for Pluto TV, "jira" for Jira, colleagues' names spelled phonetically. Fixing these by hand after every dictation defeats the point of dictating. Neither speech model knows a user's vocabulary, and the cleanup model can't fix spellings, because the faithfulness check only lets it delete words.

## What Changes

- **A word list:** the user keeps a list of terms, each written the way it should appear, with optional "heard as" spellings (how the speech model mishears it). It's stored on the Mac in `vocabulary.json`, next to the history.
- **Corrections in code:** after transcription and before cleanup, every "heard as" spelling, and the term's own spelling in any case, is replaced with the term as written. This works the same for Parakeet and Whisper, with cleanup on or off, and for rewrites (`rewrite-modes`). Because it runs before cleanup, the faithfulness check compares against the corrected text.
- **Whisper hint:** with Whisper selected and the dictation language English or Auto-detect, the terms at the top of the list are given to Whisper as a glossary before decoding, so it's more likely to spell them right in the first place.
- **Prompt rule:** when the list has terms, the cleanup prompt (and any rewrite prompt) asks the model to write those terms exactly as listed.
- **Settings > Vocabulary**, a new tab between Dictation and History:
  - a searchable table of terms and their "heard as" spellings
  - add, edit, delete, and drag to reorder
  - a mark on the terms that fit in the Whisper hint
  - JSON import (merges, never deletes) and export, so colleagues can share a list
- **"Add to vocabulary…" on History rows:** a small sheet to record how a word was heard and how it should be written.

## Capabilities

### New Capabilities
None. The changes extend existing capabilities.

### Modified Capabilities
- `speech-transcription`: vocabulary corrections; the Whisper glossary hint.
- `text-cleanup`: the "keep these terms exactly" prompt rule.
- `menu-bar-app`: the Vocabulary tab, import and export, "Add to vocabulary…" in History.
- `privacy`: the vocabulary file stays on the device, with restrictive permissions.
- `testing`: unit tests for matching, the hint and prompt assembly, and the store.

## Out of scope / follow-ups

- **Parakeet vocabulary boosting:** FluidAudio 0.17.4 can rescore Parakeet output with a word list, using CTC keyword spotting. It needs an extra ~98 MB model (`parakeet-ctc-110m-coreml`), and the library expects it in its own folder (`~/Library/Application Support/FluidAudio/Models`). It's a follow-up; until then Parakeet relies on the corrections and the prompt rule.
- **Per-website vocabularies,** e.g. a different list for Jira in a browser. Detecting the website needs URL or title detection, which is a follow-up in `per-app-behaviour`.
- **Learning automatically from edits** the user makes after a paste.

## Impact

- **Depends on `dictation-stages`:** the corrections are a post-transcription stage, and the prompt rule uses `CleanupRequest.extraRules`. This change is rebased onto `main` once that lands; type names follow whatever the groundwork merges with.
- **New code:** a vocabulary store, a matcher, a Whisper hint builder and the Vocabulary tab.
- **Edited code:** `WhisperKitEngine` (prompt tokens), the History tab (row action), the Settings tab list.
- **New file:** `~/Library/Application Support/Honyaku/vocabulary.json`.
