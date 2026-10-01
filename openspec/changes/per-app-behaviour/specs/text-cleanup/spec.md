## MODIFIED Requirements

### Requirement: Cleaned text is pasted into the active application
The system SHALL write the cleaned (or raw, if cleanup is disabled) transcript to the system pasteboard and simulate a ⌘V keystroke to paste it into the frontmost application. The user's prior pasteboard contents SHALL be restored after the paste.

Right before pasting, the system SHALL identify the app that will receive the text (the frontmost app at paste time) and SHALL route the text in this order:
1. The password-field guard (see privacy): if it blocks, nothing is pasted or saved.
2. If Honyaku itself is the frontmost app when the text is ready (for example, the user brought Settings forward while the dictation was being transcribed), the system SHALL NOT send ⌘V. It SHALL save the transcript to history and show "Saved to History — Honyaku was in front", and SHALL leave the clipboard untouched.
3. If the receiving app's rules have paste turned off, the system SHALL NOT send ⌘V. It SHALL save the formatted transcript to history, show "Saved to History. <App> is set not to paste", and leave the clipboard untouched.
4. Otherwise the system SHALL paste the transcript, formatted with the receiving app's rules.

#### Scenario: Successful paste after cleanup
- **WHEN** cleanup completes and the user has a text field focused
- **THEN** the cleaned text, formatted with the receiving app's rules, appears at the cursor position in the active application and the user's prior clipboard content is restored

#### Scenario: No active text field to paste into
- **WHEN** cleanup completes but no editable field is focused
- **THEN** the text is written to the pasteboard and a notification indicates the text is ready to paste manually

#### Scenario: Honyaku is in front when the text is ready
- **GIVEN** the user started a dictation in another app, then clicked the menu bar icon so Settings came to the front
- **WHEN** the transcript is ready
- **THEN** no ⌘V is sent, the transcript is added to history, the status reads "Saved to History — Honyaku was in front", and the clipboard is unchanged

#### Scenario: The receiving app is set to History only
- **GIVEN** the user turned paste off for Microsoft Outlook in Settings > Apps
- **WHEN** a dictation finishes while Outlook is in front
- **THEN** no ⌘V is sent, the transcript is added to history with Outlook as its app, the status reads "Saved to History. Microsoft Outlook is set not to paste", and the clipboard is unchanged

#### Scenario: Paste simulation fails or pipeline is aborted
- **WHEN** the paste simulation fails or the transcription pipeline is cancelled before completion
- **THEN** any transcript text written to the pasteboard is cleared within 5 seconds and the prior clipboard contents are restored, and the error is shown on the menu bar icon and in Settings > General

### Requirement: Unambiguous fillers never reach the paste
When the transcript's language is English, the system SHALL remove "um", "umm", "uh" and "hmm" (as whole words, not inside words like "uh-huh") from the text before pasting, whatever the model returned, including when cleanup is off or falls back. For any other language these are not treated as fillers: they SHALL be kept, and the faithfulness check SHALL treat every word of a non-English transcript as content, because "um" is a real word in German ("um 5 Uhr") and Portuguese ("um carro").

Removing a filler SHALL only tidy the spacing and punctuation where that filler was: the space it leaves, a comma that followed it, and punctuation or space it leaves at the start of the text. Everywhere else the text SHALL keep its exact spacing, so a standalone "." or "," that the speech model or cleanup model wrote stays standalone.

#### Scenario: Model leaves a filler in
- **WHEN** the model returns "I think we should uh ship it" for an English dictation
- **THEN** "I think we should ship it" is pasted

#### Scenario: German dictation
- **WHEN** Whisper transcribes "Ich komme um 5 Uhr" with language German
- **THEN** "um" is kept in the pasted text, and a cleanup output that drops it is rejected

#### Scenario: Portuguese dictation
- **WHEN** Whisper transcribes "Comprei um carro" with language Portuguese
- **THEN** "um" is kept in the pasted text

#### Scenario: A standalone full stop with no fillers
- **WHEN** the text for an English dictation is "git add ."
- **THEN** filler removal leaves it as "git add .", and a terminal receives "git add ."

#### Scenario: A filler removed before a command
- **WHEN** the text for an English dictation is "um git add ."
- **THEN** "git add ." is pasted, with the "." still standalone

#### Scenario: A filler before punctuation
- **WHEN** the text for an English dictation is "Hmm, I like it, uh, a lot" or "Um. So we go"
- **THEN** "I like it, a lot" and "So we go" are pasted, as before


## ADDED Requirements

### Requirement: Pasted text follows the receiving app's formatting rules
The system SHALL apply the formatting rules of the app that receives the text, as identified at paste time, to every transcript before it is pasted or saved as History only. That includes word-for-word dictation and Rewrite output. The rules SHALL be:
- final full stop: keep, or drop a single trailing "." that ends a word. A standalone "." (as in `git add .`), an ellipsis, a dotted abbreviation ("e.g.", "U.S.") and a common abbreviation ("etc.", "vs.") SHALL keep theirs
- first letter: as spoken, or lowercase
- quotes: as spoken, or straight
- line breaks: keep, or join into one line with no trailing line break. Joining SHALL treat every line separator (CR, LF, CRLF, U+2028, U+2029, U+0085, vertical tab, form feed) as a line break and SHALL remove other control characters except tab
- trailing space: off or on
- paste: on, or off for History only

The rules SHALL only change punctuation, letter case, quote characters and whitespace. They SHALL NOT add, remove or reorder words.

When the first letter is lowercased, the first word SHALL be left alone if it is "I" or a contraction of it, starts with a digit ("3D"), contains another capital letter (an acronym or CamelCase), or is a custom-vocabulary term.

Each app SHALL use its own rules if the user gave it an override, otherwise its category's rules, otherwise the Everything else rules. The categories SHALL be Terminals, Code editors, Chat, Email, Browsers and Everything else. Their defaults SHALL be:
- **Terminals:** drop the final full stop, straight quotes, join line breaks.
- **Code editors:** drop the final full stop, straight quotes, keep line breaks.
- **All other categories:** keep everything as spoken.
- **Every category:** trailing space off, paste on.

#### Scenario: Dictating into a terminal
- **GIVEN** Terminal is in front with default rules
- **WHEN** the transcript is "Run “make test” in the api folder."
- **THEN** the pasted text is `Run "make test" in the api folder`, with no final full stop and straight quotes

#### Scenario: A command ending in a standalone full stop
- **GIVEN** Terminal is in front with default rules
- **WHEN** the transcript is "git add ."
- **THEN** the pasted text is "git add .", with its "." kept

#### Scenario: Abbreviations keep their full stop
- **GIVEN** the receiving app's rules drop the final full stop
- **WHEN** the transcripts end in "e.g.", "U.S.", "etc." or "..."
- **THEN** the final full stop is kept in each, and "Ship it." still becomes "Ship it"

#### Scenario: Multi-line text into a terminal
- **GIVEN** iTerm2 is in front with default rules
- **WHEN** the text to paste spans three lines and ends with a line break
- **THEN** it is pasted as one line, with each line break replaced by a single space and no line break at the end

#### Scenario: Unusual line separators and control characters into a terminal
- **GIVEN** Terminal is in front with default rules
- **WHEN** the text contains a U+2028 line separator, a vertical tab and an escape character
- **THEN** it is pasted as one line, the separators become single spaces and the escape character is removed

#### Scenario: Dictating into a code editor
- **GIVEN** Visual Studio Code is in front with default rules
- **WHEN** the transcript is "Rename the function to fetchUser."
- **THEN** the pasted text is "Rename the function to fetchUser", and line breaks, had there been any, would be kept

#### Scenario: Dictating into a chat app
- **GIVEN** Slack is in front with default rules
- **WHEN** the transcript is "Sounds good, I'll ship it today."
- **THEN** the text is pasted unchanged

#### Scenario: A per-app override beats the category
- **GIVEN** the user added Ghostty with "final full stop: keep" while Terminals drops it
- **WHEN** the user dictates into Ghostty
- **THEN** the final full stop is kept, and other terminals still drop theirs

#### Scenario: The user switches apps while the dictation is transcribing
- **GIVEN** the user started dictating in Slack, then switched to Terminal before the text was ready
- **WHEN** the text is pasted
- **THEN** it lands in Terminal formatted with Terminal's rules

#### Scenario: Lowercasing the first letter keeps "I" and acronyms
- **GIVEN** the receiving app's rules lowercase the first letter
- **WHEN** the transcripts are "I think so", "API keys rotate tonight" and "Deploy it"
- **THEN** the pasted texts are "I think so", "API keys rotate tonight" and "deploy it"

#### Scenario: Lowercasing the first letter keeps a leading number
- **GIVEN** the receiving app's rules lowercase the first letter
- **WHEN** the transcript is "3D printing starts today"
- **THEN** the pasted text is "3D printing starts today"

#### Scenario: Rules never change the words
- **WHEN** any combination of rules is applied to any transcript
- **THEN** the words in the result, ignoring case and punctuation, are exactly the words of the input in the same order

#### Scenario: Changing a rule applies to the next dictation
- **WHEN** the user changes a rule in Settings > Apps and then dictates
- **THEN** the new rule is applied without relaunching Honyaku
