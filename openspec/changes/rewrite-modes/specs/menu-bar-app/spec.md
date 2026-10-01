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
