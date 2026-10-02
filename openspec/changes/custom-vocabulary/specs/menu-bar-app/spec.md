## ADDED Requirements

### Requirement: Settings has a Vocabulary tab
The Settings window SHALL have a Vocabulary tab, placed after Dictation, in this tab order: General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy. Rewrite and Apps appear when those features exist.

The tab SHALL list the vocabulary terms in the user's order. Each row SHALL show:
- an on/off checkbox
- the term
- its heard-as spellings
- whether the term is in the Whisper spelling hint

The user SHALL be able to:
- search by term or heard-as spelling
- add, edit and delete terms
- reorder terms by dragging, and with "Move up" / "Move down" from the keyboard

Every control SHALL be reachable from the keyboard and named for VoiceOver.

The tab SHALL refuse:
- an empty term
- a term longer than 100 characters
- a term already in the list (ignoring case), with "Already in your list"
- a heard-as spelling already used by another term, naming that term

The hint mark SHALL always be an estimate, and SHALL be labelled approximate: the exact cut is made with Whisper's tokenizer at each dictation.

When a change to the list can't be saved, the tab SHALL say so, and the change SHALL stay in effect until Honyaku quits.

#### Scenario: User adds a term
- **WHEN** the user adds "Paramount+" heard as "paramount plus"
- **THEN** it appears at the end of the list, switched on, and the next dictation writes "Paramount+"

#### Scenario: User reorders terms
- **GIVEN** Whisper is selected and the list is too long to fit in the hint
- **WHEN** the user drags a term to the top
- **THEN** that term is marked "In speech hint", and the order is kept after relaunch

#### Scenario: Duplicate term
- **GIVEN** the list has "Jira"
- **WHEN** the user adds "jira"
- **THEN** it is refused with "Already in your list"

#### Scenario: Unreadable vocabulary file
- **GIVEN** `vocabulary.json` is corrupt
- **WHEN** Honyaku starts
- **THEN** the file is kept as `vocabulary.corrupt-<date>.json`, the list starts empty, the Vocabulary tab explains what happened, and dictation keeps working

#### Scenario: The damaged file can't be set aside
- **GIVEN** `vocabulary.json` is corrupt and can't be renamed
- **WHEN** Honyaku starts
- **THEN** the tab reads "Couldn't set aside the damaged vocabulary file. Changes won't be saved until it's fixed or removed.", and Honyaku never overwrites that file

---

### Requirement: The vocabulary can be exported and imported
The Vocabulary tab SHALL export the list as a JSON file, and SHALL import such a file by merging it into the list by term, ignoring case:
- **An existing term** gains the imported heard-as spellings, and keeps its position and on/off state.
- **A new term** is added at the end.
- **Nothing is deleted.**
- **Clashes:** a heard-as spelling already used by another term is skipped.

After an import, the tab SHALL summarise how many terms were added, updated and skipped. A file that isn't a valid vocabulary file SHALL leave the list unchanged and show an error. A file larger than 1 MB, or with more than 2,000 terms, SHALL be refused with an error saying so, leaving the list unchanged. Merging SHALL take time proportional to the size of the lists, so an import never freezes the app.

#### Scenario: Colleague's list imported
- **GIVEN** the list has "Jira" heard as "jeera"
- **WHEN** the user imports a file with "Jira" heard as "gira", and "Pluto TV"
- **THEN** "Jira" is heard as "jeera" and "gira", "Pluto TV" is added at the end, and the summary reads "Added 1 term, updated 1"

#### Scenario: Too large a file
- **WHEN** the user imports a file with 5,000 terms
- **THEN** the list is unchanged and the error says a word list can have at most 2,000 terms

#### Scenario: Wrong file
- **WHEN** the user imports a file that isn't a vocabulary file
- **THEN** the list is unchanged and an error explains that the file couldn't be read as a word list

---

### Requirement: A History row can add a term to the vocabulary
Each History row SHALL offer "Add to vocabulary…", in its context menu and among its visible actions. It opens a sheet that shows the transcript as the speech model heard it (the raw text, before corrections, cleanup or a rewrite), with:
- a "Heard as" field, optional
- a "Write it as" field
- Cancel and Add

If "Write it as" matches an existing term (ignoring case), the heard-as spelling SHALL be added to that term. Otherwise a new term SHALL be added. Past transcripts SHALL NOT be changed.

#### Scenario: Fix a misheard name from History
- **GIVEN** a History row reads "Ask sharon about the plutotv rollout"
- **WHEN** the user chooses "Add to vocabulary…", enters "plutotv" as heard and "Pluto TV" as the spelling, and clicks Add
- **THEN** "Pluto TV" heard as "plutotv" is in the vocabulary, the History row is unchanged, and the next dictation of "plutotv" pastes "Pluto TV"
