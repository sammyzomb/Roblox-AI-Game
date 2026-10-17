# TASKS

## Project Command Structure

Product Owner: **sammyzomb** (direction, priorities, Studio acceptance, merges into `main`)
Primary Developer: **Claude Code**
Advisor / Reviewer: **ChatGPT** (advisory only)

All contributors must:
1. Read `STATUS.md`
2. Read `README.md`
3. Read `docs/AI_RULES.md`
4. Read `docs/ARCHITECTURE.md`
5. Do not modify `main` directly; merging into `main` needs Product Owner approval

## Current Development Roles

### Claude Code — Primary Developer
Branch: the current candidate branch in `STATUS.md` (now `candidate/v1`), or task branches integrated into it.

Primary responsibilities:
- Implement core Roblox / Luau systems and major gameplay features.
- Own primary implementations for combat, progression, player data, NPCs, training systems, weapons, skills, UI glue, and other assigned core systems.
- Keep implementations data-driven and server-authoritative where applicable.
- Add or update tests and implementation documentation.
- Integrate work into the candidate branch and keep `STATUS.md` current.
- Evaluate advisory feedback and bring decisions to the Product Owner.

Current priority: see "下一步" in `STATUS.md`.

### Cursor — Secondary Developer (read-only checks)
Branch: none of its own. Reads the candidate branch named in `STATUS.md`.

Primary responsibilities:
- Read and check the candidate branch: run tests and builds, look for reproducible bugs, missing tests, and integration risks.
- Report findings to Claude Code through an Issue or PR comment.
- Do not modify code, create branches, open code PRs, or merge.

### Grok Bot — Independent Reviewer / Prototype Developer
Branch: `grok-dev`

Primary responsibilities:
- Provide an independent architecture, gameplay, balance, security, exploit-surface, networking, DataStore, and mobile-controls review.
- Review Claude and Cursor changes from a separate perspective.
- Propose isolated prototypes or alternative designs only when requested.
- Record disagreements as review findings or `[CONFLICT]` items instead of silently creating a competing core implementation.
- Do not duplicate Claude Code work unless the Product Owner approves parallel exploration.

Current priority:
- Review combat balance and exploit surface.
- Review architecture decisions that affect PvP/PvE fairness, networking, and mobile play.
- Produce isolated prototypes only for decisions that need comparison.

### Creative Grok Bots — Specialist Planning Roles

#### Art Planner
Primary responsibilities:
- Define visual direction, world theme, environment style, character/enemy visual language, weapon visual families, UI visual direction, and asset priorities.
- Maintain `docs/ART_DIRECTION.md` and art briefs.
- Does not own production gameplay code.

#### Art Supervisor
Primary responsibilities:
- Review visual quality, consistency, readability, style compliance, and mobile visual/performance complexity.
- Maintain review guidance and art-related approval/revision notes.
- Does not own production gameplay code.

#### Animation Designer
Primary responsibilities:
- Define locomotion and combat animation language.
- Specify idle/walk/run/jump/fall/landing, melee/ranged/magic/defense, dodge/block/parry, hit/knockback/death, combo transitions, weapon handling, boss telegraphs, mobile readability, and animation performance constraints.
- Maintain `docs/ANIMATION_DIRECTION.md` and animation priority/state matrices.
- Does not own gameplay rules, combat balance, or production gameplay code.

#### Sound Effects Planner
Primary responsibilities:
- Define combat, magic, UI, ambience, reward/progression, defense, and impact SFX.
- Maintain `docs/SFX_PLAN.md`, event maps, naming rules, and implementation priorities.
- Does not own production gameplay code.

#### Music Planner
Primary responsibilities:
- Define the musical identity for hub, exploration, combat, boss, and PvP.
- Define dynamic transitions, loop lengths, intensity layers, cue maps, and implementation priorities.
- Maintain `docs/MUSIC_PLAN.md`.
- Does not own production gameplay code.

Creative roles may be separate Grok bots. They report through GitHub and raise gameplay/performance conflicts to Claude Code, which brings decisions to the Product Owner.

### ChatGPT — Advisor / Reviewer
Branch: none required. Optional `chatgpt/*` branches for document drafts, evaluated by Claude Code.

Primary responsibilities:
- Discuss gameplay, architecture, and plans when asked.
- Review plans and PRs and point out risks.
- Feedback is advisory: ChatGPT does not assign tasks, gate work, or decide merge readiness.

## Default Delivery Flow

1. **Product Owner** decides what to build and in what order.
2. **Claude Code implements**, tests, integrates into the candidate branch, and updates `STATUS.md`.
3. **Cursor checks** the candidate branch read-only and reports findings.
4. **ChatGPT and Grok Bot** give advisory reviews when useful.
5. **Product Owner / Roblox Studio acceptance** confirms the feature actually works in Studio before it is called truly playable, and approves any merge into `main`.

## Coordination Rules

- No agent duplicates Claude Code's implementation unless the Product Owner approves parallel exploration.
- No contributor modifies `main` directly.
- All substantive changes go through Pull Requests.
- PRs must state purpose, changes, tests, risks, and dependencies.
- A passing unit test does not equal Roblox Studio acceptance.
- `STATUS.md` and GitHub are the system of record for progress, decisions, evidence, and handoffs.
