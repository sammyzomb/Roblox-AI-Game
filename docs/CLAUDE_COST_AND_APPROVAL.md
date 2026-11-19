# Phase 1 — Claude launch approval and cost controls (Issue #60)

Status: **proposed; not deployed**. This document describes an initial safety gate, **not** a completed billing cap.

## What the proposed workflow patch does
- The `implement` job will run only when the GitHub Actions repository variable `CLAUDE_IMPLEMENT_ENABLED` is exactly `true`. An unset value is treated as disabled.
- The existing owner-authored new Issue comment, exact `[IMPLEMENT:CLAUDE]` marker, `Base:` and pinned `Spec-commit:` requirements remain in force.
- This variable is a repository-level *enable switch*, **not** per-task human approval. Connector actions performed using the owner's identity may be attributed to that owner; do not treat attribution alone as proof of a separate human review.
- No automatic merge is introduced, and the `main` branch remains protected by the existing review policy.

## Before enabling paid implementation
1. Confirm who can change Actions repository variables, and establish a human-reviewed approval path that is independent of connector-issued comments.
2. Inspect the full workflow, runner unit tests, recent Action runs, GitHub Actions PR permission, and Codex integration evidence.
3. Implement and test provider-usage accounting (including cached input/output and retry behavior), a configurable ceiling and fail-closed budget behavior. Monetary estimates can lag and cannot guarantee an exact NT$30 charge cap by themselves. Prefer an Anthropic-side spending limit when available; verify its scope.
4. Verify the actual model and published price tier; set request, token, runtime and retry limits and test all stop conditions before live use.
5. Keep `CLAUDE_IMPLEMENT_ENABLED` unset/false until owner authorization and safety tests pass. For a controlled single test, enable only within an approved window, then disable again and inspect the result.

## Limits not solved by this patch
- Existing `[DISPATCH:CLAUDE]` analysis and manual dispatch paths are separate from `implement` and may call paid providers. Audit their cost controls separately.
- The current implementation runner limits iterations/time/output size but does not track cumulative provider charges or enforce a precise currency budget.
- This PR has not tested real provider billing, repository permissions or Roblox Studio behavior.
- The Claude implementation runner only edits a narrow set of `src/`, `tests/` and smoke-test files. It **cannot** update this workflow or infrastructure itself.

Acceptance: verify the job is skipped when the variable is absent/false and still requires the original owner/marker/pinning conditions when true. Independently verify any billing limits before enabling production runs.
