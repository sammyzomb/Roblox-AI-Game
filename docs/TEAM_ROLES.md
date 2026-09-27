# TEAM ROLES AND RESPONSIBILITY BOUNDARIES

## Product Owner
**sammyzomb**
- Defines product direction and priorities.
- Makes final decisions on major scope, theme, monetization, and player-facing behavior.

## ChatGPT — Technical Lead / Primary Coordinator
- Single coordination point for the whole project.
- Converts Product Owner decisions into GitHub tasks.
- Maintains architecture, task ownership, integration rules, and cross-agent dependencies.
- Reviews PRs and resolves conflicts.
- Consolidates progress, blockers, and decisions.
- Escalates only decisions that require Product Owner input.

## Claude — Primary Programmer
**Claude is the primary and authoritative implementation agent for production code.**
- Owns primary Luau implementation.
- Owns core systems, gameplay systems, data systems, networking implementation, UI logic implementation, combat implementation, and technical refactors.
- Produces production-ready code through `claude-dev` and Pull Requests.
- Other agents may review or prototype, but should not create competing production implementations unless explicitly assigned by ChatGPT.

## Grok — Secondary Developer / Reviewer
- Reviews architecture and code.
- Produces technical recommendations, prototypes, balance models, and risk analysis.
- May implement isolated prototypes only when explicitly assigned.
- Must not assume ownership of Claude's production modules.
- Must not assign implementation work to Cursor or any external agent.

## Creative Grok Roles
### Art Planner
- Owns art direction and asset planning only.

### Art Supervisor
- Owns visual quality review and consistency only.

### SFX Planner
- Owns sound-effect planning and event mapping only.

### Music Planner
- Owns music direction and cue planning only.

Creative roles do not own gameplay code.

## Cursor Policy
**Cursor is not a project role and is not a required dependency.**

Current policy:
- Do not write "Cursor will implement", "Cursor will commit", "Cursor cloud agent will push", or equivalent as part of the standard workflow.
- Do not block work waiting for Cursor.
- If an AI lacks GitHub write access, post the full deliverable in the assigned GitHub Issue.
- ChatGPT can transfer approved documentation into GitHub when needed.
- Production code implementation defaults to Claude unless ChatGPT explicitly assigns otherwise.
- Cursor may be used manually by the Product Owner in the future, but it is outside the core AI team and must never be treated as an automatic handoff target.

## Source of Truth
GitHub is the project source of truth.

Standard flow:
Product Owner -> ChatGPT -> GitHub task -> Assigned AI -> GitHub report/PR -> ChatGPT integration -> Product Owner only when a decision is needed.
