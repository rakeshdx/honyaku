## ADDED Requirements

### Requirement: Rewrites are covered by tests
Unit tests SHALL cover, without models, microphone or network:
- **the gesture:**
  - Control+Shift in either order
  - Shift released before Control
  - plain Control
  - a quick tap
  - cancel on a key press, a click, Command or Option, with the following Control release swallowed
  - idle key presses ignored
- **template selection:** Automatic by category, a fixed choice, the app at start versus the app at paste
- **prompt assembly:** the shared rules, the template prompt, vocabulary terms, the conditional speaker-label line, delimiters
- **output caps and the stripping of echoed labels**
- **fallbacks:** no model, model error, empty output, timeout
- **the terminal single-line rule**
- **History:** a rewrite entry round-trips, and old entries decode

Integration tests (`TEST_RUNNER_INTEGRATION_TESTS=1`, with downloaded models) SHALL run Qwen3-4B on fixed transcripts for at least the Jira ticket and Chat message templates. They SHALL check that the output has the template's sections and contains no name, number or ID absent from the transcript. A UI test SHALL check that the right-click menu shows "Rewrite as" with Automatic and the seven templates, and that Settings has a Rewrite tab.

#### Scenario: Gesture order test
- **WHEN** a unit test feeds the gesture Shift down, Control down, Shift up, then Control up after 1 second
- **THEN** the gesture ends with a rewrite

#### Scenario: No invented facts
- **WHEN** the integration test rewrites a fixed bug report as a Jira ticket
- **THEN** the output contains Summary and Acceptance criteria, and no ticket ID, link or person's name that isn't in the transcript
