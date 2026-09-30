# Claude automatic implementation

Owner communicates with Technical Lead. Technical Lead assigns through GitHub;
Claude implements; Technical Lead reviews the actual code and verification.
The Owner does not need to copy tasks into another AI conversation.

## Two separate entry points

- Existing `[DISPATCH:CLAUDE]` remains read-only analysis.
- A repository-owner comment on an open Issue can request bounded implementation:

```text
[IMPLEMENT:CLAUDE]
Base: claude-dev
Spec-commit: d7db9eeef4c3b1f25900f556bc1f0afc376922ca
Implement Issue #23 against the pinned PvP/training scope. Reuse existing combat.
Report every missing acceptance item; submit code and a Studio smoke checklist.
```

`Base` must be `claude-dev` or `main`. `Spec-commit` must be a 40-character commit
containing `docs/PVP_FIRST_SLICE.md`. The current task and pinned spec are loaded
automatically; required governance is loaded from main. The runner reads source
from a pinned base commit, not from an untrusted workflow checkout.

## What the implementation runner does

1. Verifies owner identity, exact command, open Issue and parameters.
2. Posts Claude check-in to #3 and a task start report.
3. Uses the existing Anthropic OIDC/WIF identity and Messages API file tools.
4. Lets Claude inspect files and edit `src/`, `tests/`, and
   `docs/TRAINING_SMOKE_TEST.md`. Workflows, scripts, governance, dotfiles,
   secret-related paths, symlinks and shell access are unavailable to the model.
5. Enforces 24 model turns, a 20-minute loop deadline (plus active request),
   100 KB per file, 40 files and 500 KB total changed contents.
6. Validates paths, JSON and added-line whitespace, creates an isolated
   `claude/issue-N/run-ID-attempt` branch with a real commit, and opens a draft PR.
7. Reports the PR/commit to the task and #3 for Technical Lead review.

No existing branch is overwritten. No merge API is available. Incomplete or
truncated output is rejected; no branch is published for those failed runs.
Reruns use separate branches and require Technical Lead to reconcile duplicates.

## Verification limits

Runner unit tests are run before each implementation job. These test the
automation, not the Roblox game. Luau tests, Rojo builds, LSP and Studio are
not executed by this runner. The draft PR explicitly records these gaps and
labels Claude's handoff as unverified claims. Technical Lead must arrange
verification; PR #4 still requires Studio smoke evidence before merge.

GitHub Actions must permit workflow PR creation. If repository settings deny it,
the task records the already-created branch/commit and a blocker. Technical Lead
can open the draft through the GitHub connector; the Owner only needs to act if
a setting or permission cannot be changed with available access.

API usage is incurred only for explicitly authorized implementation commands.
This is a bounded file-tool runner, not Claude Code or a general shell agent.
Current rollout status must be read from Actions and task comments; documentation
alone does not prove successful API authentication, code submission or gameplay.
