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

## Authentication

Claude uses Anthropic Workload Identity Federation with GitHub Actions OIDC.

No static `ANTHROPIC_API_KEY` is required.

The configured Anthropic federation is restricted to:

- repository: `sammyzomb/Roblox-AI-Game`
- service account: `roblox-github-actions`
- workspace: `Default`

GitHub Actions must have:

```yaml
permissions:
  id-token: write
  contents: read
  issues: write
```

Grok/xAI still requires:

- `XAI_API_KEY` as a GitHub Actions repository secret

Do not put API keys in Issues, source files, workflow YAML, or documentation.

## Optional repository variables

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
[DISPATCH:GROK-ANIMATION-DESIGNER]
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

## Role routing

| Agent marker | Provider | Project role |
| --- | --- | --- |
| CLAUDE | Anthropic WIF | Primary Programmer |
| GROK | xAI | Secondary Developer / Reviewer |
| GROK-ART-PLANNER | xAI | Art Planner |
| GROK-ART-SUPERVISOR | xAI | Art Supervisor |
| GROK-ANIMATION-DESIGNER | xAI | Animation Designer |
| GROK-SFX-PLANNER | xAI | Sound Effects Planner |
| GROK-MUSIC-PLANNER | xAI | Music Planner |

## Manual test

After this workflow is merged into the default branch, use GitHub Actions → **AI Dispatcher v1** → **Run workflow**.

Test first with:
- issue number: `6`
- agent: `CLAUDE`

A successful run should:
1. request a short-lived GitHub OIDC token;
2. exchange it with Anthropic WIF;
3. call Claude Sonnet 5;
4. post Claude's result to Issue #6.

## Failure behavior

If the provider call fails, the dispatcher posts a `[BLOCKED]` comment to the same Issue.

Common Claude causes:
- Anthropic account has no API credits/billing;
- federation rule or repository claim mismatch;
- selected model unavailable to the account;
- provider outage or rate limit.

Common xAI causes:
- missing/invalid `XAI_API_KEY`;
- no xAI API credit/billing;
- provider outage or rate limit.

## Cost control

The dispatcher triggers only when a comment contains an explicit `[DISPATCH:...]` marker.

Ordinary Issue comments and normal `[STATUS]` updates do not call an AI API.

## Next phase

After v1 is stable:
1. Add a restricted mutation protocol where Claude returns validated file operations.
2. Allow writes only to an agent-owned feature branch.
3. Run tests/lint before commit.
4. Open a PR automatically.
5. Never allow automatic merge into `main`.
6. Add retry/stalled/escalation controls.
