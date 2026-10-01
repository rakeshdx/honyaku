## ADDED Requirements

### Requirement: A failed dictation never interrupts the next recording
When a dictation fails, the system SHALL show its error and settle the status before any delayed clean-up, such as clearing the transcript from the clipboard after 5 seconds. Nothing the failed dictation does later SHALL change the status. A recording started after the failure, even within those 5 seconds, SHALL keep recording until the user releases Control.

A failed paste SHALL be reported at once, and the transcript SHALL be cleared from the clipboard once.

#### Scenario: Control pressed right after a failure
- **GIVEN** a dictation just failed and its error is showing
- **WHEN** the user holds Control again within 5 seconds
- **THEN** the new recording starts, keeps recording while the earlier dictation's clipboard clear completes, and is transcribed when Control is released

#### Scenario: The paste fails
- **WHEN** posting ⌘V fails
- **THEN** the error shows straight away, nothing is saved to history, and the clipboard is cleared once, 5 seconds later
