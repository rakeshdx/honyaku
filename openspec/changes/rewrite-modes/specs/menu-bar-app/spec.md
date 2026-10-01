## ADDED Requirements

### Requirement: The right-click menu chooses the rewrite template
The menu bar icon's right-click menu SHALL contain, in order:
1. "Settings…"
2. a "Rewrite as" submenu
3. a separator
4. "Quit Honyaku"

The submenu SHALL list "Automatic (by app)", a separator, then the seven templates, with a checkmark on the current choice. Choosing an item SHALL set the same "Rewrite as" setting shown in Settings > Rewrite. The choice SHALL take effect from the next hold, and SHALL persist across relaunches.

#### Scenario: User picks a template from the menu
- **WHEN** the user right-clicks the icon and chooses Rewrite as ▸ Standup update
- **THEN** Standup update is checkmarked, the next rewrite uses it, and Settings > Rewrite shows the same choice

#### Scenario: Back to Automatic
- **WHEN** the user chooses Rewrite as ▸ Automatic (by app)
- **THEN** the next rewrite picks its template by the app in front

---

### Requirement: Settings has a Rewrite tab
The Settings window SHALL have a Rewrite tab, placed after Vocabulary and before Apps (when those tabs exist), containing:
- a line explaining "Hold Control+Shift to rewrite what you say in a format for where it's going"
- the "Rewrite as" choice, Automatic (by app) or a template
- a template picker for each app category: Chat apps, Email, Terminals, Code editors, Browsers, Everything else
- the seven templates, each with a one-line description and, under an Advanced disclosure, its editable prompt and "Reset to default"
- a note that depends on the cleanup model:
  - with Qwen3-1.7B selected: "Qwen3-1.7B is fast but writes weaker rewrites. Qwen3-4B is better for this."
  - with no cleanup model downloaded: "Rewrite needs a cleanup model."

  Either note comes with a button that opens the Models tab.

#### Scenario: Changing a category's template
- **WHEN** the user sets Terminals to Commit message in Settings > Rewrite
- **THEN** with "Rewrite as" on Automatic, the next rewrite started in a terminal uses Commit message

#### Scenario: Weaker model note
- **GIVEN** the selected cleanup model is Qwen3-1.7B
- **WHEN** the user opens Settings > Rewrite
- **THEN** the note recommending Qwen3-4B is shown, with a button that opens the Models tab

---

### Requirement: The General tab mentions Rewrite
Below "Hold Control to talk" in the General tab's status, the system SHALL show "Hold Control+Shift to rewrite as a Jira ticket, chat message, email and more." First run SHALL NOT change.

#### Scenario: User opens Settings
- **WHEN** the user opens the General tab
- **THEN** both the Control hint and the Control+Shift hint are shown

---

### Requirement: History shows rewrites
A History entry for a rewrite SHALL store both the spoken transcript and the rewritten text, together with the template used. Its row SHALL show:
- the rewritten text
- a caption such as "Rewritten as Jira ticket"
- a "Your words" disclosure revealing the spoken transcript

Copy SHALL copy the rewritten text. Search SHALL match either text. Entries saved before this change, and rewrites that fell back to dictation, SHALL show as dictation.

#### Scenario: Viewing a rewrite
- **WHEN** the user opens History after a Jira-ticket rewrite
- **THEN** the row shows the ticket, "Rewritten as Jira ticket", and the spoken words under "Your words"

#### Scenario: Searching spoken words
- **WHEN** the user searches History for a word they said but which the rewrite dropped
- **THEN** that rewrite's row is listed

---

### Requirement: VoiceOver announces rewriting
While a rewrite is being generated, the menu bar icon SHALL tell VoiceOver "Rewriting" as its state.

#### Scenario: VoiceOver reads the icon during a rewrite
- **WHEN** VoiceOver focuses the Honyaku icon while a rewrite is generating
- **THEN** it reads "Honyaku" followed by "Rewriting"

## MODIFIED Requirements

### Requirement: Clicking the menu bar icon opens Settings
Clicking the Honyaku menu bar icon SHALL open the Settings window directly. There is no popover and no transcript list in the menu bar; history lives in Settings > History.
- **While first run is incomplete** (a permission is missing, or models haven't been set up), clicking the icon SHALL open the first-run window instead.
- **Right-clicking** the icon SHALL show a menu with "Settings…", a "Rewrite as" submenu and "Quit Honyaku" (see "The right-click menu chooses the rewrite template"). A Control-click SHALL NOT open the menu, because holding Control is how the user dictates.
- **The icon itself** SHALL keep reflecting state: idle, recording, transcribing or processing, and error.
- **Current status** SHALL be shown at the top of the General tab: the Control keycap with "Hold Control to talk", the active speech model, whether cleanup is on, the full text of any error, and any background model download with its progress.
- **Clicking the icon SHALL NOT clear an error.** The error stays until the next dictation starts, or until the problem it reports is fixed (for example, the Control listener installs after Accessibility is granted).

#### Scenario: User clicks the menu bar icon after setup
- **WHEN** the user clicks the Honyaku icon in the menu bar
- **THEN** the Settings window opens (or comes to the front) on the last tab used, and no popover appears

#### Scenario: User right-clicks the icon
- **WHEN** the user right-clicks the Honyaku icon
- **THEN** a menu with "Settings…", "Rewrite as" and "Quit Honyaku" appears, and "Quit Honyaku" quits the app

#### Scenario: User Control-clicks the icon
- **WHEN** the user holds Control and clicks the Honyaku icon
- **THEN** the click is treated as a left click (Settings, or first run, opens), and no menu appears

#### Scenario: First run isn't finished
- **GIVEN** Accessibility isn't granted yet, or models haven't been set up
- **WHEN** the user clicks the icon
- **THEN** the first-run window opens at its first incomplete step

#### Scenario: An error occurred
- **WHEN** the last dictation failed and the user clicks the icon
- **THEN** the General tab shows the error's full text, and the error is still there after the click; the next dictation clears it

#### Scenario: A model is downloading in the background
- **WHEN** a migrated model is downloading and the user opens Settings
- **THEN** the General tab and the model's row in the Models tab show the download's progress

---

### Requirement: Settings is a single window
The system SHALL provide a single Settings window, opened by clicking the menu bar icon (or "Settings…" in its right-click menu), with these tabs, in this order:
- **General:** current status (see the menu bar icon requirement), launch at login, microphone device, permission status with "Open System Settings" for each missing permission.
- **Models:** the speech and cleanup models, each with its download state, disk space used, "Use" (only for downloaded models), "In use" for the active one, Download and Delete.
- **Dictation:** cleanup on/off, speaker labels on/off, the dictation language, and the cleanup prompt with "Reset to default", under an Advanced disclosure.
- **Vocabulary:** the user's terms and how they're misheard (see "Settings has a Vocabulary tab").
- **Rewrite:** the "Rewrite as" choice, the template for each kind of app, and the editable templates (see "Settings has a Rewrite tab").
- **Apps:** the formatting rules for each kind of app and for individual apps (see "Settings has an Apps tab for per-app formatting rules").
- **History:** a searchable list of transcripts. Each row SHALL have visible Copy and Delete buttons, reachable from the keyboard and named for VoiceOver, as well as Copy and Delete in its context menu. A row SHALL also offer "Add to vocabulary…", show the app the text went to (or "Not pasted"), and, for a rewrite, the "Rewritten as …" caption with the spoken words under "Your words". "Your words" SHALL show the speech model's original wording, before vocabulary corrections. "Delete all history…" sits behind a confirmation.
- **Privacy:** the offline guarantees, and the Hugging Face access token under an Advanced disclosure. A token that fails to save SHALL show an error rather than "Saved".

There SHALL never be more than one Settings window, and never more than one first-run window.

#### Scenario: User opens Settings
- **WHEN** the user clicks the menu bar icon, or chooses "Settings…" from its right-click menu
- **THEN** the Settings window opens on the General tab, or the last tab used, and comes to the front

#### Scenario: User clicks Settings again while it's open
- **GIVEN** the Settings window is already open, possibly behind other windows
- **WHEN** the user clicks the menu bar icon again, or chooses "Settings…" from its menu
- **THEN** that same window comes to the front, and no second Settings window opens

#### Scenario: Settings is minimised
- **GIVEN** the user minimised the Settings window (or the first-run window) to the Dock
- **WHEN** the user clicks the menu bar icon
- **THEN** that same window is restored from the Dock and comes to the front, with its content as the user left it

#### Scenario: User closes Settings
- **WHEN** the user closes the Settings window and later clicks Settings again
- **THEN** a single Settings window opens

#### Scenario: User searches history
- **WHEN** the user types "invoice" into the History search field
- **THEN** only transcripts containing "invoice" (ignoring case and accents) are listed

#### Scenario: User copies a transcript with the keyboard
- **WHEN** the user tabs to a history row's Copy button and presses Space
- **THEN** that transcript is on the clipboard

#### Scenario: The tabs are in order
- **WHEN** the user opens Settings
- **THEN** the tabs read General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy
