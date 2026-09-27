# AI Coordination Protocol

## Purpose

This document defines how ChatGPT, Claude, and Grok confirm presence, understand shared requirements, communicate, and hand off work through GitHub.

## Mandatory Check-In

Before starting any new task, every AI collaborator must post a check-in comment in the active coordination Issue using this format:

```
[CHECK-IN]
Agent: ChatGPT / Claude / Grok
Role:
Branch:
Current task:
Understood requirements:
Dependencies:
Blocked by:
Planned deliverable:
```

If there is no blocker, write `Blocked by: None`.

## Shared Understanding Rule

Before implementation, each AI must confirm:
1. What the Product Owner wants.
2. What the Technical Lead has assigned.
3. Which files/modules it owns.
4. Which files/modules it must not modify.
5. What other AI work it depends on.
6. What deliverable and PR title are expected.

If any requirement is unclear or conflicts with another instruction, do not guess. Post the conflict in the coordination Issue.

## Communication Channels

### Coordination Issue
Use for:
- Check-in / check-out
- Requirement clarification
- Architecture conflicts
- Cross-agent dependencies
- Handoffs
- Blockers

### Task Issues
Use for:
- Specific implementation tasks
- Acceptance criteria
- Progress updates

### Pull Requests
Use for:
- Code review
- Implementation discussion
- Requested changes
- Merge readiness

### docs/
Use for:
- Finalized architecture
- Stable decisions
- Shared conventions
- Long-term project knowledge

## Required Progress Update

When meaningful progress is made, post:

```
[STATUS]
Agent:
Completed:
In progress:
Needs from others:
Risks:
Next step:
```

## Required Handoff

When work is ready for another AI:

```
[HANDOFF]
From:
To:
What is ready:
Files/modules affected:
What the receiver should do:
Known risks:
Related Issue/PR:
```

## Completion Report

Before considering a task complete:

```
[COMPLETE]
Agent:
Task:
Deliverables:
Tests performed:
Known limitations:
PR:
Recommended next step:
```

## Authority

- Product Owner: sammyzomb
- Technical Lead / Primary Coordinator: ChatGPT
- Primary Programmer: Claude
- Secondary Developer / Reviewer: Grok

When requirements conflict:
1. Product Owner intent has highest priority.
2. ChatGPT coordinates technical resolution.
3. Claude and Grok must surface disagreements in GitHub instead of silently choosing different approaches.

## Main Rule

No agent may assume that another AI has seen a chat message outside GitHub.
Anything important to shared work must be written to GitHub.
