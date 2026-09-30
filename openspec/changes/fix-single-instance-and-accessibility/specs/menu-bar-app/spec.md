## ADDED Requirements

### Requirement: Only one instance of the app runs at a time
The system SHALL ensure that at most one Honyaku process (bundle identifier `com.honyaku.app`) runs per user session. When a new instance launches while older instances are running, the new instance SHALL request graceful termination of every older instance ("newest wins"). The new instance SHALL NOT install its push-to-talk event tap until no older instance remains.

#### Scenario: Build and run while an older instance is running
- **WHEN** an instance of Honyaku is running and the developer builds and runs a new instance from Xcode
- **THEN** the older instance terminates, the new instance keeps running, and exactly one Honyaku process remains

#### Scenario: Older instance performs its normal quit cleanup
- **WHEN** a new instance terminates an older instance
- **THEN** the older instance terminates through the normal application termination path, so its quit cleanup (pasteboard clearing, temp-file removal) runs

#### Scenario: Older instance does not exit in time
- **WHEN** an older instance has not exited within 3 seconds of the graceful termination request
- **THEN** the new instance force-terminates the older instance

#### Scenario: Only one hotkey listener is active
- **WHEN** a new instance has replaced an older instance
- **THEN** a single press-and-hold of the Control key starts exactly one recording and produces at most one paste

#### Scenario: No other instance is running
- **WHEN** Honyaku launches and no other instance is running
- **THEN** startup proceeds normally without delay

---

### Requirement: Quit & Relaunch starts exactly one fresh instance
When the user chooses "Quit & Relaunch" from the permission onboarding, the system SHALL terminate the current process and then launch a new instance of the same app bundle only after the current process has exited. The new instance SHALL read permission state fresh at launch.

#### Scenario: User relaunches after granting Accessibility
- **WHEN** the user grants Accessibility in System Settings and clicks "Quit & Relaunch"
- **THEN** the current process exits, a new process for the same app bundle starts, and exactly one Honyaku process is running afterwards

#### Scenario: Relaunched instance reflects the current grant
- **WHEN** the relaunched instance starts and Accessibility is granted for its code signature
- **THEN** the onboarding shows Accessibility as granted and the push-to-talk event tap is installed
