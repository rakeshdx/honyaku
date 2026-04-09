# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Spec-Driven Development (SDD)

This project uses **OpenSpec** by Fission AI for spec-driven development. Every feature or change **must begin with a spec** — no code is written before specs are agreed upon.

### Setup

```bash
npm install -g @fission-ai/openspec@latest
openspec init       # initialize in project root
openspec update     # refresh AI guidance / activate latest commands
```

### Core Workflow

Every change follows this lifecycle:

1. **Propose** — `/opsx:propose` — capture intent, scope, approach (`proposal.md`)
2. **Spec** — define delta specs (ADDED / MODIFIED / REMOVED requirements with Given-When-Then scenarios)
3. **Design** — `design.md` — technical architecture decisions
4. **Tasks** — `tasks.md` — checkbox-based implementation plan
5. **Apply** — `/opsx:apply` — implement tasks against the agreed spec
6. **Archive** — `/opsx:archive` — merge delta specs into main specs, move change folder to `changes/archive/`

### Directory Structure

```
openspec/
├── specs/              # Source of truth — current system behavior, organized by domain
│   └── <domain>/spec.md
├── changes/            # Active proposals (one folder per in-flight change)
│   └── <change-name>/
│       ├── proposal.md
│       ├── specs/      # Delta specs — only what's changing
│       ├── design.md
│       └── tasks.md
└── config.yaml         # Optional configuration
```

### Spec Format

Requirements use RFC 2119 keywords and Given-When-Then scenarios:

```markdown
### Requirement: [Behavior description]
The system MUST/SHALL/SHOULD [action].

#### Scenario: [Specific case]
- GIVEN [initial state]
- WHEN [trigger event]
- THEN [observable outcome]
```

- `MUST` / `SHALL` — absolute requirement
- `SHOULD` — recommended
- `MAY` — optional

### Delta Specs

Specs in `changes/<name>/specs/` describe **only what's changing**, not the full state:

- **ADDED Requirements** — new functionality
- **MODIFIED Requirements** — updated behavior (note the previous version)
- **REMOVED Requirements** — deprecated features

### Key Principle

> Agree on **what** to build before writing any code. Implementation details go in `design.md` and `tasks.md` — not in `spec.md`.

### CLI Reference

```bash
openspec list                    # list active changes
openspec show <change-name>      # view a change's details
openspec validate <change-name>  # check spec formatting
openspec view                    # interactive dashboard
```
