---
name: "Review & Push"
description: Senior Swift engineer code review — runs tests, lint, secrets scan, licence check, static analysis, multi-agent review, then pushes to remote if all checks pass.
category: Workflow
tags: [review, swift, security, testing, ci]
---

You are acting as a **Senior Swift Engineer** performing a thorough pre-push code review for the Honyaku macOS app. Follow every phase in order. Stop and report clearly if any phase fails — do not skip to push.

---

## Phase 1 — Tests

### 1.1 Unit tests

Run the unit test suite. Do NOT run xcodebuild without user approval — use the Bash tool to check if a pre-built test binary exists, otherwise remind the user to run tests in Xcode and confirm results before proceeding.

```bash
# Check for test results from a recent build
find ~/Library/Developer/Xcode/DerivedData -name "*.xcresult" -newer /tmp -maxdepth 6 2>/dev/null | head -5
```

If no recent results exist, output:

> **Action required**: Please run the `HonyakuTests` scheme in Xcode (⌘U) and confirm all tests pass before continuing. Type "tests passed" to proceed.

Wait for user confirmation before continuing to Phase 2.

### 1.2 Integration tests

Check whether integration test fixtures exist:

```bash
ls Sources/Tests/Fixtures/ 2>/dev/null || ls Tests/Fixtures/ 2>/dev/null
```

If fixture `.wav` files are present, note that integration tests (`INTEGRATION_TESTS=1`) are available. Remind the user they require downloaded models and ask if they want to run them. Do not block the review if they decline.

---

## Phase 2 — Lint

### 2.1 SwiftLint

Check if SwiftLint is available:

```bash
which swiftlint 2>/dev/null || echo "not found"
```

- **If found**: run `swiftlint lint --quiet` from the project root. Treat any **error** as a blocker; warnings are advisory.
- **If not found**: note it is not installed and recommend `brew install swiftlint`. Continue review — this is advisory only.

### 2.2 Swift compiler warnings

Check the most recent Xcode build log for compiler warnings:

```bash
find ~/Library/Developer/Xcode/DerivedData/Honyaku-*/Logs/Build -name "*.xcactivitylog" 2>/dev/null | sort -t_ -k1 | tail -1
```

If a recent log is found, search for `warning:` lines related to project sources (exclude SPM packages). List any warnings found.

---

## Phase 3 — Secrets scan

Scan the entire working tree for accidentally committed secrets. Run each check:

```bash
# HuggingFace tokens (hf_...)
grep -rn "hf_[a-zA-Z0-9]\{20,\}" --include="*.swift" --include="*.yml" --include="*.yaml" --include="*.json" --include="*.plist" . 2>/dev/null | grep -v ".git"

# Generic API key patterns
grep -rEn "(api_key|apikey|api-key|secret|password|token)\s*[:=]\s*['\"][a-zA-Z0-9+/]{16,}" --include="*.swift" --include="*.yml" . 2>/dev/null | grep -v ".git" | grep -vi "placeholder\|example\|your_\|<\|TODO"

# AWS keys
grep -rn "AKIA[0-9A-Z]\{16\}" --include="*.swift" . 2>/dev/null

# Private keys / certs
grep -rn "BEGIN.*PRIVATE KEY\|BEGIN CERTIFICATE" . 2>/dev/null | grep -v ".git"
```

**Blocker**: any match that is not a placeholder or comment must be resolved before push.

---

## Phase 4 — Licence check

Enumerate all Swift Package Manager dependencies and check their licences for compatibility with the project (MIT app):

```bash
# List resolved packages
cat Honyaku.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
pins = data.get('pins', data.get('object',{}).get('pins',[]))
for p in pins:
    print(p.get('identity','?'), '-', p.get('location','?'))
" 2>/dev/null || echo "Package.resolved not found or not readable"
```

Known dependency licences for this project:
| Package | Licence | Compatible |
|---|---|---|
| WhisperKit (argmaxinc) | MIT | ✅ |
| mlx-swift-lm (ml-explore) | MIT | ✅ |

Flag any new dependency whose licence is unknown, GPL, or AGPL as a **blocker**.

---

## Phase 5 — Static analysis (multi-agent)

Launch **four parallel review agents** using the Agent tool, each specialising in a different dimension. Collect all findings before proceeding.

### Agent assignments

**Agent A — Security & Privacy**
Review all Swift source files under `Sources/Honyaku/` for:
- Command injection risks (Process(), shell invocations)
- Insecure data storage (UserDefaults for sensitive data, plaintext secrets)
- Network requests outside the explicit model-download path
- Pasteboard data leaks beyond the intended 5-second window
- CGEventTap scope — ensure only flagsChanged events are tapped
- Entitlements — confirm JIT entitlement is absent, sandbox is off intentionally

**Agent B — Concurrency & Threading**
Review for:
- Data races: shared mutable state accessed from multiple actors/queues
- `@MainActor` correctness — pipeline, AppState, views all on main; actors (TranscriptionService, CleanupService, ModelDownloader) isolated correctly
- Continuation misuse in `ModelDownloader.downloadFile` — ensure resume is called exactly once
- Task cancellation — verify timeout tasks are cancelled after the winner resolves
- `AVAudioEngine` tap installed/removed symmetrically on all code paths (start, stop, cancel, error)

**Agent C — Architecture & Swift Best Practices**
Review for:
- Protocol conformance completeness (`ServiceProtocols.swift`)
- Error propagation — all throws are handled or propagated; no silent swallows except documented fallbacks
- Memory management — `[weak self]` in closures, no retain cycles between pipeline and services
- SwiftUI environment object injection — all views receive required objects
- `AppStatus.isBusy` vs `isIdle` used consistently everywhere (post bug-fix audit)
- `ModelStore.isDownloaded` logic correctness for each model type

**Agent D — Robustness & Edge Cases**
Review for:
- Empty audio / silence handling through the full pipeline
- MLX model not downloaded — `CleanupService.loadModel()` throws `modelNotLoaded`; verify pipeline handles it gracefully (falls back, does not crash)
- Disk full during model download — `insufficientDiskSpace` error surfaced to UI
- Transcript store decode failure — `history.json` corrupt; verify app does not crash on launch
- `keyDownTime` staleness fix — verify the 5-second reset is correct and cannot cause a double-start
- `clearError()` called before `startCapture()` — verify no race if audio engine is mid-setup

---

### Consolidation

After all four agents complete, consolidate findings into three buckets:

| Severity | Definition |
|---|---|
| 🔴 Blocker | Must be fixed before push — correctness, security, or crash risk |
| 🟡 Warning | Should be fixed soon — quality or robustness concern |
| 🟢 Advisory | Nice to have — style, minor improvement |

Print the consolidated report. If any 🔴 Blockers exist, **stop here** and list what must be fixed.

---

## Phase 6 — Push

Only reached if Phases 1–5 have no blockers.

### 6.1 Pre-push checklist

Confirm all of the following before pushing:

- [ ] All unit tests passed (user confirmed)
- [ ] No secrets found in scan
- [ ] No GPL/AGPL licences introduced
- [ ] No 🔴 blockers from static analysis
- [ ] `.gitignore` excludes `xcuserstate`, `xcuserdata/`, `DerivedData/`, `Package.resolved`

### 6.2 Verify remote

```bash
git remote -v
git status
git log --oneline -5
```

Show the user what commits will be pushed and to which remote/branch. **Ask for explicit confirmation before pushing.**

### 6.3 Push

Only after explicit user confirmation:

```bash
git push origin main
```

Report success or failure. If push is rejected (non-fast-forward), explain the situation and ask the user how to proceed — do not force push.

---

## Output format

At each phase, print a clearly labelled status line:

```
✅ Phase 1 — Tests: passed
✅ Phase 2 — Lint: 0 errors, 3 warnings (advisory)
✅ Phase 3 — Secrets: clean
✅ Phase 4 — Licences: all compatible
🔴 Phase 5 — Static analysis: 2 blockers found (see report)
⏸  Phase 6 — Push: blocked until Phase 5 resolved
```
