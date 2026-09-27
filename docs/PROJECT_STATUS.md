# AI Project Status Dashboard

Technical Lead / Coordinator: **ChatGPT**
Product Owner: **sammyzomb**

This file is the consolidated status source for all AI contributors.

## Current Agents

| Agent | Role | Branch | Check-in | Current Focus | Blocked |
|---|---|---|---|---|---|
| ChatGPT | Technical Lead / Integration | `chatgpt-dev` | Active | Coordination, architecture, review | No |
| Claude | Primary Programmer | `claude-dev` | Pending | Roblox project foundation | Unknown until check-in |
| Grok | Secondary Developer / Reviewer | `grok-dev` | Pending | Architecture review, MVP gameplay proposal | Unknown until check-in |

## Coordination Rules

- ChatGPT consolidates progress from Issues, Pull Requests, commits, blockers, and handoffs.
- Claude and Grok must report status in Issue #3 using the defined templates.
- Any blocker, conflict, failed test, or architecture disagreement must be posted to Issue #3.
- Important cross-agent decisions must be recorded in GitHub.
- No AI should assume another AI has seen an external chat.
- No AI may modify `main` directly.

## Escalation

Report to the Product Owner when:
- A task is blocked by missing product direction.
- Two AI agents disagree on architecture or requirements.
- A change risks data loss, security, monetization, or major rework.
- Roblox publishing, API credentials, or external services require owner action.
- A PR cannot be safely merged.
- Scope changes materially affect the planned MVP.

## Consolidation Workflow

1. AI checks in.
2. AI works on its assigned branch.
3. AI posts status / blocker / handoff.
4. ChatGPT reviews Issues, PRs, commits, and tests.
5. ChatGPT updates the consolidated status.
6. Product Owner is notified when a decision or intervention is required.
