## ADDED Requirements

### Requirement: Holding Control and Shift rewrites instead of dictating
The system SHALL treat a hold of Control during which Shift was down at any moment as a rewrite. The mode SHALL be decided when Control is released, from every modifier seen during the hold:
- Shift pressed before Control, after Control, or released before Control all SHALL give a rewrite.
- A hold with no Shift SHALL be plain dictation, exactly as before.
- Recording SHALL start at Control key-down in both modes, with no added delay.
- The 300 ms minimum hold, the busy guard and the stale-press rule SHALL apply to rewrites as they do to dictation.

Shift's own events SHALL pass through to the active application.

#### Scenario: Shift then Control
- **GIVEN** Honyaku is idle
- **WHEN** the user holds Shift, then holds Control, speaks for two seconds, and releases both
- **THEN** the recording is processed as a rewrite

#### Scenario: Control then Shift
- **WHEN** the user holds Control, presses Shift a second later while still holding Control, speaks, and releases both
- **THEN** the recording is processed as a rewrite

#### Scenario: Shift released before Control
- **WHEN** the user holds Control and Shift, releases Shift, keeps speaking, and then releases Control
- **THEN** the recording is processed as a rewrite

#### Scenario: Plain Control is unchanged
- **WHEN** the user holds only Control for two seconds and releases it
- **THEN** the recording is processed as word-for-word dictation

#### Scenario: Quick Control+Shift tap
- **WHEN** the user taps Control+Shift for under 300 ms
- **THEN** the audio is discarded, the microphone is released, and nothing is transcribed

---

### Requirement: The capsule names the rewrite template
As soon as Shift is seen during a hold, the recording capsule SHALL show "Rewriting as <template>", using the template that will be used: the "Rewrite as" choice, or the template for the category of the app that was in front when the recording started. While the rewrite is being generated, the capsule SHALL show "Rewriting as <template>…" in place of "Transcribing…". Template names SHALL be shown in sentence case, without separators such as middle dots.

#### Scenario: Rewrite in Slack
- **GIVEN** "Rewrite as" is Automatic and Slack is in front
- **WHEN** the user holds Control+Shift
- **THEN** the capsule shows "Rewriting as chat message" next to the level meter

#### Scenario: Generating
- **WHEN** the user releases Control after a rewrite hold
- **THEN** the capsule shows "Rewriting as chat message…" until the text is pasted

## MODIFIED Requirements

### Requirement: Global Control key activates recording
The system SHALL register a global CGEventTap that monitors modifier changes for the Control key, capturing audio from the selected microphone for the duration the key is held, regardless of which application has focus. A hold that also involved Shift is a rewrite (see "Holding Control and Shift rewrites instead of dictating"); otherwise it is plain dictation.

#### Scenario: User holds Control to start recording
- **WHEN** the user presses and holds the Control key while Honyaku is running
- **THEN** the system begins capturing audio from the active microphone and displays a recording indicator in the menu bar icon

#### Scenario: User releases Control to stop recording
- **WHEN** the user releases the Control key after holding it
- **THEN** the system stops audio capture and immediately triggers the transcription pipeline with the captured audio

#### Scenario: Control key press is shorter than minimum duration
- **WHEN** the user taps the Control key for less than 300ms
- **THEN** the system discards the audio buffer and does not trigger transcription

---

### Requirement: Recording does not interfere with system Control key usage
The system SHALL pass through all Control key combinations (e.g., Ctrl+C, Ctrl+Z) to the active application and SHALL NOT transcribe a hold that became a shortcut:
- Pressing any non-modifier key while Control is held SHALL cancel the recording.
- Clicking any mouse button while Control is held SHALL cancel the recording (a Control-click is a secondary click in most apps).
- Pressing Command or Option while Control is held SHALL cancel the recording.
- Control pressed while Command or Option is already held SHALL NOT start a recording.

A cancelled hold SHALL stop capture, release the microphone and discard the audio, with no transcription, no paste and no error. The key, click or modifier that cancelled it SHALL reach the active application unchanged. The Control release that follows SHALL be consumed without effect. Cancelling SHALL apply however long Control has been held.

#### Scenario: User presses Control+C while Honyaku is running
- **WHEN** the user presses Ctrl+C in any application
- **THEN** the system forwards the event to the active application and does not transcribe anything

#### Scenario: Long Control shortcut hold
- **WHEN** the user holds Control for one second, then presses C, then releases both
- **THEN** the terminal receives Ctrl+C, the microphone is released, and nothing is transcribed or pasted

#### Scenario: Control-click
- **WHEN** the user holds Control and clicks in a Finder window
- **THEN** Finder receives the Control-click, and the recording is cancelled without transcription

#### Scenario: Control+Shift shortcut
- **WHEN** the user holds Control+Shift and presses Tab
- **THEN** the app receives Ctrl+Shift+Tab, and no rewrite runs

#### Scenario: Option during the hold
- **WHEN** the user holds Control and then presses Option
- **THEN** the recording is cancelled without transcription, and the Option event reaches the app

---

### Requirement: CGEventTap does not retain non-trigger key event data
The event tap SHALL observe modifier changes, key-down events and mouse-down events, and nothing else. For key-down and mouse-down events, the system SHALL read only the event's type, never its key code, characters, location or any other payload, and SHALL use it only to cancel a hold in progress. While no hold is in progress, such events SHALL be passed through immediately with no state change. The system SHALL NOT log, buffer, store, modify or delay any event, and SHALL NOT retain any data from key events beyond whether Control and Shift are held.

#### Scenario: User types while Honyaku is running
- **WHEN** the user types characters in any application while the CGEventTap is active
- **THEN** each keystroke is forwarded immediately to the active application and no character data is retained by Honyaku

#### Scenario: User presses a non-Control system shortcut
- **WHEN** the user presses any key combination not involving bare Control (e.g., ⌘S, Option+F4)
- **THEN** the event is passed through without any data being recorded by the CGEventTap handler

#### Scenario: Key press during a hold
- **WHEN** the user presses a letter key while holding Control
- **THEN** Honyaku learns only that a key went down, cancels the hold, and passes the event through unchanged

---

### Requirement: A press never leaves recording active
Every Control press that starts a recording SHALL end with capture either handed to the transcription pipeline or cancelled. When a press ends without transcription (a quick tap, or a hold cancelled by a key, a click, Command or Option), the system SHALL stop audio capture, release the microphone, discard the captured audio, and return to idle. Resetting a stale press record SHALL NOT discard a hold whose recording is still active.

#### Scenario: Quick tap is discarded and the mic is released
- **WHEN** the user presses and releases the Control key within 300 ms
- **THEN** audio capture stops, the microphone is released, the audio is discarded, no transcription runs, and the status returns to idle

#### Scenario: Push-to-talk keeps working after a quick tap
- **GIVEN** the user has just made a quick tap under 300 ms
- **WHEN** the user holds Control for at least 300 ms and releases it
- **THEN** a new recording starts and is transcribed on release

#### Scenario: Long hold survives other Control-only modifier events
- **WHEN** the user has held Control for more than 5 seconds and another Control-only modifier event arrives (for example the second Control key or Fn)
- **THEN** the recording continues, and releasing Control ends it and triggers transcription

#### Scenario: Push-to-talk keeps working after a cancelled hold
- **GIVEN** the user's last hold was cancelled by pressing a key
- **WHEN** the user holds Control for two seconds and releases it
- **THEN** a new recording starts and is transcribed on release
