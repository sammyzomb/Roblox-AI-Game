# TEAM ROLES AND RESPONSIBILITY BOUNDARIES

## Product Owner
**sammyzomb**
- Defines product direction and priorities.
- Makes final decisions on major scope, theme, monetization, and player-facing behavior.
- Approves merges into `main`, releases, and closing PRs.
- Runs Roblox Studio tests and gives final acceptance.

## Claude Code — Primary Developer
**Claude Code is the primary and authoritative implementation agent for production code.** (Product Owner decision, 2026-10-17.)
- Owns all code changes: core systems, gameplay, data, networking, UI logic, combat, and refactors.
- Integrates work into the current candidate branch (see `STATUS.md`).
- Maintains architecture documents and `STATUS.md`.
- Evaluates advisory feedback from ChatGPT and Grok; adopts it or records why not.
- Brings conflicts and product decisions to the Product Owner with options and a recommendation.
- Other agents may review or prototype, but must not create competing production implementations unless the Product Owner approves.

## ChatGPT — Advisor / Reviewer
- Gives design, architecture, and gameplay opinions when asked.
- Reviews plans and PRs and points out risks.
- Its feedback is advisory: it does not assign tasks, gate work, or decide merge readiness.
- Posts feedback as Issue or PR comments. Disagreements go to the Product Owner.

## Grok — Independent Reviewer
- Reviews architecture and code.
- Produces technical recommendations, prototypes, balance models, and risk analysis.
- May implement isolated prototypes only when explicitly assigned.
- Must not assume ownership of Claude's production modules.
- Must not assign implementation work to Cursor or any external agent.
- Review feedback is advisory and goes to Claude Code; disagreements go to the Product Owner.

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

## Cursor — Secondary Developer (read-only checks)
Current policy (Product Owner decision, 2026-10-17):
- Cursor performs read-only checks on the assigned candidate branch: reads code, runs tests and builds, and reports reproducible problems.
- Cursor does not modify code, create branches, open code PRs, or merge.
- Findings go to Claude Code (Issue or PR comment), which fixes them on the candidate branch.

## Source of Truth
GitHub is the project source of truth.

Standard flow:
Product Owner -> Claude Code (implement, test, integrate into candidate branch, update `STATUS.md`) -> Cursor read-only check / advisory reviews -> Product Owner Studio test and decision.
