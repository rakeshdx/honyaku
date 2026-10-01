## Why

Much of what gets dictated at work isn't meant to land word for word. A spoken bug report should become a Jira ticket, a thought for a colleague a short chat message, and a description of a change a commit message or a prompt for a coding agent. Today Honyaku can only paste exactly what was said: its cleanup model may delete fillers and nothing more (the faithfulness check rejects anything else). Turning loose speech into a structured format still has to be done by hand.

## What Changes

- **A second push-to-talk gesture, Control+Shift.** Hold Control and Shift together, in either order, to rewrite instead of dictate. Plain Control is unchanged. The mode is decided when Control is released, from every modifier seen during the hold, so key order doesn't matter and no delay is added.
- **Cancel when the hold becomes a shortcut.** Pressing any non-modifier key, or clicking the mouse, while Control is held cancels the recording; the event still reaches the app. This also fixes Control shortcuts held longer than 300 ms (Ctrl+C in a terminal, Ctrl+Tab) being transcribed today. Command or Option pressed during the hold also cancel it.
- **Seven built-in rewrite templates:** Jira ticket, Chat message, Email, Commit message, PR description, Coding-agent prompt, Standup update. Each prompt is editable, with "Reset to default". Every template follows one rule: use only what was said; never invent names, numbers, links or ticket IDs. Output is plain text with labels, "- " bullets and blank lines.
- **The template is picked by the app in front when the recording starts:** Slack/Teams → Chat message, terminals and code editors → Coding-agent prompt, Outlook/Mail → Email, browsers and everything else → Jira ticket. The mapping is editable. A "Rewrite as" submenu on the icon's right-click menu offers Automatic (by app) or a fixed template that stays until set back to Automatic.
- **Generation:** the selected cleanup model, temperature 0, a per-template output cap, a 60 s timeout, no faithfulness check. Vocabulary terms (from custom-vocabulary) are passed as "write these terms exactly as listed".
- **Fallbacks:** no cleanup model downloaded → the dictation is pasted as spoken with "To use Rewrite, download a cleanup model in Settings > Models"; failure or timeout → the dictation is pasted with "Couldn't rewrite: used your words as dictated". A rewrite cut off at its cap is trimmed to its last complete line with "The rewrite was cut short".
- **Terminals:** a rewrite going into a terminal is joined into one line, with no trailing line break. No characters are stripped. Per-app formatting rules apply to rewrites as to dictation.
- **UI:**
  - The capsule says "Rewriting as Jira ticket" (or the chosen template).
  - History keeps both the spoken words and the rewrite, and names the template.
  - A new Settings > Rewrite tab, between Vocabulary and Apps: the app-to-template mapping, the "Rewrite as" choice, the seven templates with editable prompts, and a note that Qwen3-1.7B writes weaker rewrites than Qwen3-4B.
  - A General-tab hint ("Hold Control+Shift to rewrite…"). First run is unchanged.
- The Dictation tab's cleanup toggle affects plain dictation only; rewrites always use the model.

## Capabilities

### New Capabilities
<!-- none: rewrite extends existing capabilities -->

### Modified Capabilities
- `push-to-talk`: the Control+Shift rewrite gesture; cancel on a key press, a click, or Command/Option during the hold; what the event tap may observe; the capsule's rewrite label.
- `text-cleanup`: rewrite generation, templates, fallbacks, terminal one-line output; the cleanup toggle doesn't apply to rewrites.
- `menu-bar-app`: the "Rewrite as" submenu, the Rewrite tab, the General hint, rewrites in History, VoiceOver "Rewriting".
- `testing`: unit, integration and UI coverage for rewrites.

## Impact

- **Depends on** `dictation-stages` (DictationMode, mode-carrying hotkey callbacks, DictationContext with the app at recording start, CleanupRequest with faithfulness off and maxTokens, the LLM stage, AppCategory, optional TranscriptEntry.mode). Names in this change follow whatever dictation-stages finally merges.
- **Merges after** `custom-vocabulary` (extraRules) and `per-app-behaviour` (terminal line joining, formatting rules on rewrites).
- **Code:**
  - `PushToTalkGesture`, `HotkeyService` (event mask: keyDown, mouse-down), `AppCoordinator` wiring
  - a new `RewriteTemplates` registry and `RewriteSettings` store
  - `CleanupService` (rewrite generation path)
  - the pipeline's LLM stage
  - `RecordingCapsule`, `StatusItemController` menu, `SettingsView` (new Rewrite tab file), the History row, `TranscriptEntry` (optional template ID)
- **Privacy:** the event tap starts observing key-down and mouse-down event *types* during a hold, to cancel. It never reads key codes or characters, and passes every event through unchanged. No new permission: the tap already runs under Accessibility.
- **Performance:** about 1.5–4 s per rewrite on an M3 Max (measured: Qwen3-1.7B ~153 tok/s, Qwen3-4B ~73 tok/s). Probably 2–3x slower on base M1/M2.

## Out of scope

- Custom (user-added) templates.
- A separate model setting for rewrites.
- A preview or confirm step before pasting.
- Per-app (as opposed to per-category) template mapping.
- Detecting the website in a browser (e.g. Jira in Chrome).
- Markdown output by default (a template's prompt can be edited to ask for it).
