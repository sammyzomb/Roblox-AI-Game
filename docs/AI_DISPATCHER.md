# AI Dispatcher v1

## Purpose

AI Dispatcher v1 removes the need to manually open each Claude/Grok chat just to wake the agent.

A Technical Lead command in a GitHub Issue can trigger GitHub Actions, call the assigned AI through its API, and write the response back to the same Issue.

## v1 safety boundary

Version 1 is intentionally read-only.

It can:
- read the target Issue and recent comments;
- read core project governance documents;
- call Claude or Grok;
- post `[STATUS]`, `[BLOCKED]`, `[HANDOFF]`, `[COMPLETE]`, or `[AVAILABLE]` back to the Issue.

It cannot:
- edit repository files;
- commit or push;
- merge;
- create production-code PRs;
- claim Roblox Studio testing occurred.

This boundary is deliberate. File mutation and automatic PR creation should be added only after the dispatcher is stable and auditable.

## Required GitHub Secrets

Repository → Settings → Secrets and variables → Actions → New repository secret

Create:

- `ANTHROPIC_API_KEY`
- `XAI_API_KEY`

Do not put API keys in Issues, source files, workflow YAML, or documentation.

## Optional repository variables

Repository → Settings → Secrets and variables → Actions → Variables

Optional:
- `CLAUDE_MODEL` — default: `claude-sonnet-5`
- `XAI_MODEL` — default: `grok-4.7`

## Dispatch commands

Post one of these markers in the assigned GitHub Issue:

```
[DISPATCH:CLAUDE]
```

```
[DISPATCH:GROK]
```

```
[DISPATCH:GROK-ART-PLANNER]
```

```
[DISPATCH:GROK-ART-SUPERVISOR]
```

```
[DISPATCH:GROK-SFX-PLANNER]
```

```
[DISPATCH:GROK-MUSIC-PLANNER]
```

Example:

```
[DISPATCH:CLAUDE]

[CONTINUE WORK — TECH LEAD]
Continue Issue #6. Read the latest Issue context and project rules.
Post a heartbeat first, then work toward the next milestone.
If blocked, report the exact dependency.
```

GitHub Actions will call the mapped provider and post the model response back to that Issue.

## Role routing

| Agent marker | Provider | Project role |
| --- | --- | --- |
| CLAUDE | Anthropic | Primary Programmer |
| GROK | xAI | Secondary Developer / Reviewer |
| GROK-ART-PLANNER | xAI | Art Planner |
| GROK-ART-SUPERVISOR | xAI | Art Supervisor |
| GROK-SFX-PLANNER | xAI | Sound Effects Planner |
| GROK-MUSIC-PLANNER | xAI | Music Planner |

## Manual test

The workflow can also be started from GitHub Actions using **Run workflow**.

Inputs:
- issue number
- agent key

This is useful for validating API keys before relying on Issue comment triggers.

## Failure behavior

If the provider call fails, the dispatcher posts a `[BLOCKED]` comment to the same Issue with the integration error.

Common causes:
- missing GitHub Secret;
- provider account has no credit/billing;
- invalid/expired API key;
- selected model unavailable to the account;
- provider outage or rate limit.

## Cost control

The dispatcher triggers only when a comment contains an explicit `[DISPATCH:...]` marker.

Ordinary Issue comments and normal `[STATUS]` updates do not call an AI API. This prevents loops and accidental token spend.

## Next phase

After v1 is stable:
1. Add a restricted mutation protocol where Claude returns validated file operations.
2. Allow writes only to an agent-owned feature branch.
3. Run tests/lint before commit.
4. Open a PR automatically.
5. Never allow automatic merge into `main`.
6. Add retry/stalled/escalation controls.
