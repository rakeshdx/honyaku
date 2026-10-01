## ADDED Requirements

### Requirement: A rewrite turns the dictation into the chosen format
For a rewrite, the system SHALL send the transcript to the selected cleanup model on the device with:
- the shared rewrite rules
- the chosen template's prompt
- the vocabulary terms, when there are any, as "Write these terms exactly as listed: …"

Generation SHALL use temperature 0, the template's output cap, and a 60-second timeout. The faithfulness check for word-for-word cleanup SHALL NOT be applied to rewrites.

The shared rules SHALL NOT be editable, and SHALL require the model to:
- use only what was said, never inventing names, numbers, dates, links, ticket IDs or facts
- write TBD for anything the format needs that wasn't said
- keep names, products, files, functions and commands exactly as spoken
- write plain text with labels, "- " bullets and blank lines, not Markdown
- output only the rewritten text

The transcript SHALL be sent inside delimiters, and echoed delimiters or labels SHALL be removed. A leading line SHALL be removed as an echo only when it is a heading naming a template ("Jira ticket:", "Here's your chat message:"), the dictation label, or a line of the prompt itself; any other first line, such as "Rewrite the dictation pipeline as stages", SHALL be kept. When the transcript has speaker labels, the model SHALL be told to use them for attribution and leave them out of the output; otherwise no label rule SHALL be given. No transcript text SHALL leave the device.

#### Scenario: Rewrite as a Jira ticket
- **GIVEN** the template is Jira ticket
- **WHEN** the user says "the export button on the reports page does nothing when you click it, it should download a CSV"
- **THEN** the pasted text has Summary, Description and Acceptance criteria sections, has no Steps to reproduce section, and names no person, ticket ID or link

#### Scenario: Missing information
- **GIVEN** the template is PR description
- **WHEN** the dictation never says how the change was tested
- **THEN** the Testing section says TBD

#### Scenario: Vocabulary is kept
- **GIVEN** "Paramount+" is in the vocabulary
- **WHEN** a rewrite mentions it
- **THEN** the output spells it "Paramount+"

#### Scenario: Content that looks like an instruction
- **GIVEN** the template is Commit message
- **WHEN** the model returns "Rewrite the dictation pipeline as stages"
- **THEN** that line is pasted, not removed as an echo

---

### Requirement: Rewrite templates are built in and editable
The system SHALL provide seven rewrite templates: Jira ticket, Chat message, Email, Commit message, PR description, Coding-agent prompt and Standup update. Their default prompts are listed in the design. Each template's prompt SHALL be editable in Settings > Rewrite, with "Reset to default"; editing a prompt SHALL NOT change the shared rules. The output caps SHALL be:

| Template | Cap (tokens) |
|---|---|
| Commit message | 200 |
| Chat message | 300 |
| Standup update | 300 |
| Coding-agent prompt | 400 |
| Jira ticket, PR description, Email | 700 |

Each cap SHALL be reduced for short dictations, to no more than 150 plus three times the estimated input tokens. Input tokens SHALL be estimated as words × 4/3, plus one per character of scripts written without spaces (such as Japanese, Chinese and Thai), so a dictation in those languages isn't counted as a few words.

A prompt the user empties SHALL count as the default prompt.

#### Scenario: User edits a template
- **WHEN** the user edits the Chat message prompt to "Rewrite as one sentence"
- **THEN** the next chat-message rewrite uses that prompt, together with the shared rules

#### Scenario: User resets a template
- **WHEN** the user clicks "Reset to default" for the Chat message template
- **THEN** the default prompt is restored and no edited copy is kept

#### Scenario: User empties a template
- **WHEN** the user deletes all of the Chat message prompt's text
- **THEN** the next chat-message rewrite uses the default prompt

#### Scenario: A Japanese dictation
- **WHEN** the user rewrites a one-minute Japanese dictation as a Jira ticket
- **THEN** the output cap is the template's full 700 tokens, not a cap for a three-word dictation

---

### Requirement: The rewrite template follows the app in front
The template SHALL be the one chosen under "Rewrite as" when the user picked one. That choice SHALL stay in effect until the user sets it back to Automatic. With Automatic, the template SHALL be chosen by the category of the app that was in front when the recording started. The defaults are:

| App category | Template |
|---|---|
| Chat apps (Slack, Teams) | Chat message |
| Terminals and code editors | Coding-agent prompt |
| Email apps (Outlook, Mail) | Email |
| Browsers and everything else | Jira ticket |

The user SHALL be able to change the template for each category in Settings > Rewrite.

#### Scenario: Automatic in a terminal
- **GIVEN** "Rewrite as" is Automatic and Terminal is in front when the recording starts
- **WHEN** the user rewrites "add a retry to the upload function in uploader dot swift"
- **THEN** the Coding-agent prompt template is used

#### Scenario: Fixed template
- **GIVEN** the user chose "Commit message" under "Rewrite as"
- **WHEN** the user rewrites in Slack
- **THEN** the Commit message template is used, and it stays in use for later rewrites until the user picks Automatic

#### Scenario: App switched during the rewrite
- **GIVEN** Slack is in front when the recording starts
- **WHEN** the user switches to Terminal before the text is pasted
- **THEN** the Chat message template is used, and the result is pasted into Terminal formatted for a terminal

---

### Requirement: A rewrite that can't run still pastes the user's words
When a rewrite can't produce output, the system SHALL paste the dictation as it would be without any model: the transcript after vocabulary replacements and with "um", "umm", "uh" and "hmm" removed (English only). The system SHALL NOT make a second model call for cleanup. It SHALL show a notice that clears at the next dictation, and SHALL save the History entry as dictation.
- **When no cleanup model is downloaded,** the notice SHALL be "To use Rewrite, download a cleanup model in Settings > Models".
- **When the model fails, returns nothing, returns reasoning that was cut off (an unclosed `<think>`), or exceeds 60 seconds,** the notice SHALL be "Couldn't rewrite: used your words as dictated".

When the text isn't pasted (a password field is focused, Honyaku is in front, or the app is set not to paste), only that outcome's notice SHALL be shown, so no notice claims the text was pasted.

#### Scenario: No cleanup model
- **GIVEN** no cleanup model is downloaded
- **WHEN** the user rewrites "um ship the release today"
- **THEN** "ship the release today" is pasted and the notice tells the user to download a cleanup model

#### Scenario: Timeout
- **WHEN** a rewrite is still generating after 60 seconds
- **THEN** generation stops, the dictation is pasted, and "Couldn't rewrite: used your words as dictated" is shown

#### Scenario: Reasoning cut off
- **WHEN** the model's output starts a `<think>` block that never closes
- **THEN** none of it is pasted; the dictation is used with the "Couldn't rewrite" notice

#### Scenario: A rewrite that falls back into a password field
- **GIVEN** a password field is focused at paste time
- **WHEN** a rewrite fails
- **THEN** nothing is pasted or saved, and only "Not pasted: a password field is focused" is shown

---

### Requirement: A rewrite into a terminal is a single line
When the app in front at paste time is a terminal, the rewrite SHALL be pasted as a single line:
- every line break (including CRLF, U+2028, U+0085, vertical tab and form feed), and the whitespace around it, SHALL become one space
- control characters other than tab SHALL be removed
- leading and trailing whitespace SHALL be removed, so there is no trailing line break
- no other characters SHALL be removed or changed beyond the terminal's formatting rules

The app category's formatting rules SHALL apply to rewrites as they do to dictation.

#### Scenario: Jira ticket into a terminal
- **GIVEN** "Rewrite as" is Jira ticket and Terminal is in front at paste time
- **WHEN** the rewrite has several sections
- **THEN** one line is pasted, nothing runs in the shell, and no line break follows it

#### Scenario: Code names are kept
- **WHEN** a coding-agent prompt for a terminal contains `` `make test` `` and `$PATH`
- **THEN** the backticks and the dollar sign are pasted unchanged

### Requirement: A rewrite cut short is trimmed and flagged
When generation stops because it reached the template's output cap, the system SHALL trim the rewrite back to its last complete line or sentence, paste that, and add the notice "The rewrite was cut short". If nothing complete remains, the rewrite SHALL count as failed.

#### Scenario: A long Jira dictation
- **WHEN** a rewrite reaches the 700-token cap in the middle of a sentence
- **THEN** the pasted text ends at the last complete line or sentence, and "The rewrite was cut short" is shown

---

## MODIFIED Requirements

### Requirement: Cleanup can be disabled
The system SHALL provide a toggle in Settings to disable LLM cleanup, in which case the raw WhisperKit transcript is pasted directly. The toggle SHALL apply only to word-for-word dictation; rewrites SHALL always use the cleanup model.

#### Scenario: Cleanup is disabled in Settings
- **WHEN** push-to-talk recording completes and cleanup is toggled off
- **THEN** the raw transcript is written to the pasteboard and pasted without any LLM processing step

#### Scenario: Rewrite with cleanup disabled
- **GIVEN** cleanup is toggled off and a cleanup model is downloaded
- **WHEN** the user rewrites with Control+Shift
- **THEN** the model rewrites the dictation as usual
