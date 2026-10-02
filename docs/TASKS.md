# TASKS

## Project Command Structure

Technical Lead / Coordinator: **ChatGPT**
Product Owner: **sammyzomb**

All contributors must:
1. Read `README.md`
2. Read `docs/AI_RULES.md`
3. Read `docs/ARCHITECTURE.md`
4. Work only on assigned branch
5. Submit Pull Requests into `main`
6. Do not modify `main` directly

## Current Development Roles

### Claude — Primary Programmer
Branch: `claude-dev`

Primary responsibilities:
- Implement core Roblox / Luau systems and major gameplay features.
- Own primary implementations for combat, progression, player data, NPCs, training systems, weapons, skills, UI glue, and other assigned core systems.
- Keep implementations data-driven and server-authoritative where applicable.
- Add or update tests and implementation documentation.
- Do not start a second implementation of work already assigned to Cursor or Grok Bot unless ChatGPT explicitly reassigns it.

Current priority:
- Finish and stabilize the core work represented by PR #4.
- Resolve integration issues required before Roblox Studio play-testing.
- Avoid broad new feature expansion until the current core is integration-ready.

### Cursor — Secondary Developer / Verification Engineer
Branch: task-specific `cursor/*` branches unless ChatGPT assigns another branch.

Primary responsibilities:
- Read and verify Claude's implementation before integration.
- Run fresh-agent smoke tests, regression tests, build checks, and pre-Studio verification.
- Identify reproducible bugs, merge conflicts, missing tests, unsafe assumptions, and integration risks.
- Make small, isolated, test-backed fixes when assigned.
- Review differences among `main`, `claude-dev`, and active PR heads.
- Prepare Studio test checklists and flag blockers before Product Owner play-testing.
- Do not independently rewrite Claude-owned core systems unless ChatGPT explicitly assigns that work.

Current priority:
- Verify PR #4 and its relationship to current `main`.
- Identify merge/integration blockers.
- Validate automated tests and Studio prerequisites.
- Continue acting as the main regression/smoke-test developer.

### Grok Bot — Independent Reviewer / Prototype Developer
Branch: `grok-dev`

Primary responsibilities:
- Provide an independent architecture, gameplay, balance, security, exploit-surface, networking, DataStore, and mobile-controls review.
- Review Claude and Cursor changes from a separate perspective.
- Propose isolated prototypes or alternative designs only when requested.
- Record disagreements as review findings or `[CONFLICT]` items instead of silently creating a competing core implementation.
- Do not duplicate Claude or Cursor work unless ChatGPT explicitly requests parallel exploration.

Current priority:
- Review combat balance and exploit surface.
- Review architecture decisions that affect PvP/PvE fairness, networking, and mobile play.
- Produce isolated prototypes only for decisions that need comparison.

### ChatGPT — Technical Lead
Branch: `chatgpt-dev` or task-specific `chatgpt/*` branches.

Primary responsibilities:
- Break down work and assign each task to exactly one primary owner.
- Review Claude, Cursor, and Grok Bot results.
- Prevent duplicate implementations and cross-branch conflicts.
- Resolve integration problems and maintain architecture/governance documents.
- Decide merge readiness based on evidence.
- Distinguish document complete, code complete, integrated, Studio-tested, and truly playable states.
- Escalate product-direction decisions to the Product Owner.

## Default Delivery Flow

1. **Claude implements** the primary feature or core-system change.
2. **Cursor verifies** the implementation, runs smoke/regression/build checks, and fixes only scoped issues assigned by ChatGPT.
3. **Grok Bot independently reviews** architecture, balance, security, exploit surface, or creates an isolated prototype when needed.
4. **ChatGPT integrates and reviews** the combined result and resolves conflicts.
5. **Product Owner / Roblox Studio acceptance** confirms the feature actually works in Studio before it is called truly playable.

## Coordination Rules

- Claude, Cursor, and Grok Bot must not duplicate the same implementation unless ChatGPT explicitly assigns parallel exploration.
- No contributor modifies `main` directly.
- All substantive changes go through Pull Requests.
- PRs must state purpose, changes, tests, risks, and dependencies.
- A passing unit test does not equal Roblox Studio acceptance.
- GitHub is the system of record for assignments, decisions, evidence, and handoffs.
