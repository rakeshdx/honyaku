## MODIFIED Requirements

### Requirement: UI interactions are covered by XCUITests
The following UI flows SHALL be covered by `XCUITest`, in the `HonyakuUITests` scheme:
- The menu bar icon exists; a test SHALL fail, not skip, when it can't be found
- Clicking the icon opens Settings
- Clicking the icon twice leaves exactly one Settings window
- Right-clicking the icon shows "Settings…" and "Quit Honyaku"
- "Delete all history…" asks for confirmation before deleting
- Launch at Login toggle state persists across re-opens of Settings
- First run shows when Accessibility permission is missing (mocked permission state)

UI tests SHALL set up the state they need through a launch argument that only Debug builds honour, held in memory for that launch. They SHALL NOT depend on, or change, the user's saved settings, history or models, and SHALL NOT start the Control listener or load models.

#### Scenario: Menu bar icon opens Settings
- **WHEN** an XCUITest launches Honyaku with setup marked complete for the test and clicks the menu bar icon
- **THEN** the Settings window appears with its toolbar tabs

#### Scenario: One Settings window
- **WHEN** an XCUITest clicks the menu bar icon twice
- **THEN** exactly one Settings window exists

#### Scenario: The icon is missing
- **WHEN** an XCUITest can't find the Honyaku menu bar icon
- **THEN** the test fails

#### Scenario: Delete all history confirmation
- **WHEN** an XCUITest clicks "Delete all history…" in Settings > History
- **THEN** a confirmation dialog appears; confirming empties the history list
