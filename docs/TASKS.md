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

## Sprint 0 — Foundation

### Claude — Primary Programmer
Branch: `claude-dev`

Tasks:
- Create the Roblox project source structure.
- Set up a clean Luau module architecture.
- Add bootstrap scripts for ServerScriptService, ReplicatedStorage, StarterPlayer, and StarterGui.
- Create a reusable service/module pattern.
- Add basic player data model interfaces.
- Add a minimal testable game loop scaffold.
- Document setup instructions in `docs/CLAUDE_IMPLEMENTATION.md`.

Deliverable:
- Pull Request titled: `feat: Roblox project foundation`

### Grok — Secondary Developer / Reviewer
Branch: `grok-dev`

Tasks:
- Review the proposed repository structure and Roblox architecture.
- Propose a lightweight MVP gameplay loop suitable for rapid iteration.
- Identify risks in networking, RemoteEvents, DataStore usage, exploit prevention, and mobile controls.
- Add recommendations to `docs/GROK_REVIEW.md`.
- If useful, create isolated prototype modules only on `grok-dev`.

Deliverable:
- Pull Request titled: `docs: gameplay and architecture review`

### ChatGPT — Technical Lead
Branch: `chatgpt-dev`

Tasks:
- Define architecture and conventions.
- Review Claude and Grok Pull Requests.
- Resolve conflicts.
- Maintain `docs/ARCHITECTURE.md` and `docs/TASKS.md`.
- Prepare integration plan and Roblox publishing workflow.

## Rule

Claude and Grok must not wait for each other unless a task explicitly depends on the other's PR.
