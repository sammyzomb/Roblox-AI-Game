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

### Animation Designer
- Owns animation direction, movement/combat animation language, timing/readability, boss telegraphs, weapon handling, and animation asset planning only.
- Primary deliverable: `docs/ANIMATION_DIRECTION.md`.
- Does not own gameplay rules, combat balance, or production gameplay code.

### SFX Planner
- Owns sound-effect planning and event mapping only.

### Music Planner
- Owns music direction and cue planning only.

Creative roles do not own gameplay code.

## Cursor — Secondary Developer / Verification Engineer
**Cursor is now an active project role under ChatGPT coordination.**

Current policy:
- Cursor verifies Claude implementation through fresh-agent smoke tests, regression/build checks, integration checks, and Studio prerequisites.
- Cursor may make small, isolated, test-backed fixes when explicitly assigned by ChatGPT.
- Cursor must not independently rewrite Claude-owned core production systems.
- Cursor does not replace Claude as Primary Programmer.
- Work must use assigned task-specific branches and Pull Requests.
- ChatGPT remains responsible for task ownership, conflict resolution, and merge readiness.

## Source of Truth
GitHub is the project source of truth.

Standard flow:
Product Owner -> ChatGPT -> GitHub task -> Assigned AI -> GitHub report/PR -> ChatGPT integration -> Product Owner only when a decision is needed.
