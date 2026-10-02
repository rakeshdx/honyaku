## ADDED Requirements

### Requirement: Rewrite grounding is covered by tests
Unit tests SHALL cover:
- which terms the keep-terms rule lists: present terms only, case and word boundaries, a heard-as spelling, none present
- the minimum rewrite length: 3 words, 4 words, short and long text in a script without spaces, speaker labels
- the invention check: an output with an added term fails, and an output repeating only input terms is accepted
- the notices

A pipeline test SHALL reproduce the reported case ("P plus" with the vocabulary P+, Paramount+ and POPS, and a model that invents) and show "P+" pasted as a dictation with the short-input notice. A second pipeline test SHALL show the invention fallback for a longer dictation. An integration test on the installed cleanup model, with a temporary vocabulary, SHALL show that an agent-prompt rewrite of a short sentence containing "P+" never introduces "POPS" or "Paramount+". Tests SHALL NOT read or write the user's real vocabulary, history or settings.

#### Scenario: The reported case is a regression test
- **WHEN** the unit tests run
- **THEN** the "P plus" rewrite with an inventing fake model ends as "P+" pasted, with the too-short notice
