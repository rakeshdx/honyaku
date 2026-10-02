## ADDED Requirements

### Requirement: Settings has an Apps tab for per-app formatting rules
Settings SHALL have an Apps tab. Once all three features have merged, the tab order SHALL be General, Models, Dictation, Vocabulary, Rewrite, Apps, History, Privacy.

The tab SHALL:
- list the categories Terminals, Code editors, Chat, Email, Browsers and Everything else, each with editable formatting rules and "Reset to defaults" when changed;
- list the apps that have their own rules, with Delete;
- let the user add an app from the running apps or with "Choose app…". A new app's rules start as a copy of its category's rules.

The tab SHALL say that the rules change formatting only and that Honyaku never pastes into password fields.

The rules SHALL be saved to `~/Library/Application Support/Honyaku/app-profiles.json` with owner-only permissions (0600), excluded from backup. Only changed categories and per-app overrides are stored. If the file can't be read, Honyaku SHALL use the defaults, SHALL move the file aside as `app-profiles.damaged-<date>.json` and SHALL say so in the Apps tab. If the file can't be moved aside, or was written by a newer version of Honyaku, Honyaku SHALL leave it in place, SHALL say so in the Apps tab, and SHALL NOT save over it.

#### Scenario: User adds an app from the running apps
- **GIVEN** Ghostty is running
- **WHEN** the user clicks + in Settings > Apps and chooses Ghostty
- **THEN** Ghostty appears under apps with their own rules, with the Terminals rules as its starting point

#### Scenario: User chooses an app that isn't running
- **WHEN** the user chooses "Choose app…" and picks Notion in /Applications
- **THEN** Notion appears under apps with their own rules

#### Scenario: User resets a category
- **GIVEN** the user changed Chat to drop the final full stop
- **WHEN** the user clicks "Reset to defaults" on Chat
- **THEN** Chat keeps the final full stop again and the change is saved

#### Scenario: Rules survive a relaunch
- **WHEN** the user changes a rule and relaunches Honyaku
- **THEN** the changed rule is still in effect

#### Scenario: The rules file is damaged
- **GIVEN** app-profiles.json can't be read
- **WHEN** Honyaku launches
- **THEN** the default rules are used, the file is kept as app-profiles.damaged-<date>.json, and the Apps tab says so until the user dismisses it

#### Scenario: The damaged file can't be moved aside
- **GIVEN** app-profiles.json can't be read and can't be moved
- **WHEN** the user changes a rule
- **THEN** the change applies until Honyaku quits, the file is not overwritten, and the Apps tab says changes can't be saved

#### Scenario: The rules file is from a newer version
- **GIVEN** app-profiles.json was written by a newer version of Honyaku
- **WHEN** Honyaku launches
- **THEN** the default rules are used, the file is left unchanged even when the user changes a rule, and the Apps tab says so

### Requirement: History shows where each transcript went
Each History row SHALL show the app the transcript was pasted into, or saved for, with its icon and name. If the app is no longer installed, the row SHALL show its bundle ID instead. A transcript saved without pasting SHALL say "Not pasted". Entries with no app recorded, such as older entries, SHALL show nothing extra.

#### Scenario: A transcript pasted into Slack
- **WHEN** the user opens Settings > History after dictating into Slack
- **THEN** the row shows Slack's icon and name

#### Scenario: A History-only transcript
- **WHEN** a transcript was saved because its app is set not to paste
- **THEN** its row shows the app and "Not pasted"

#### Scenario: An entry from before this change
- **WHEN** History contains an entry saved before apps were recorded
- **THEN** the row shows no app, and the history file still loads
