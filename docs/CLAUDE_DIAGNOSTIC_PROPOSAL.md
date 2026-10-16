# Claude recovery diagnostic: review and validation plan

Scope: PR #54, infrastructure only. This prepares a safe diagnostic entry; it does
not establish that Claude has recovered. Gameplay, merging, deployment, provider
configuration, permissions, credentials and production base rules remain outside
this change. Coordination takeover is limited to this repair.

## Existing incident evidence

- Custom runner job 110507420033: WIF exchange succeeded, then the first model
  request returned HTTP 400. The historical response body is unavailable.
  https://github.com/sammyzomb/Roblox-AI-Game/actions/runs/36903281477/job/110507420033
- Official Action job 110633721795: initialized, then is_error:true, one turn,
  216 ms, empty modelUsage, reported cost 0 and no new branch. No retained artifact
  provides the underlying error. This does not prove quota or model-name failure.
  https://github.com/sammyzomb/Roblox-AI-Game/actions/runs/36941472611/job/110633721795

## Manual entry and least privilege

The existing ai-dispatcher.yml gains a manual CLAUDE-DIAGNOSTIC agent mode. It is
explicitly excluded from the ordinary paid dispatcher. No new workflow, trigger,
credential, provider identity or permission grant is created. There is no push,
pull_request, schedule or issue-comment trigger for diagnostic work.

The offline diagnose job has only contents:read and no explicitly injected
GITHUB_TOKEN or id-token permission. A separate diagnose_live job, gated on the
offline job succeeding AND explicit live=true, uses contents:read and the
workflow's existing id-token:write; it drops all repository write permissions. The same existing federation
identifiers and workflow path are reused. This is a new use of an existing WIF
route, so its execution still needs review. No federation trust-rule change is
included. If the existing trust rejects the selected branch/ref/job, stop and
report it; do not broaden trust to make the test work.

Manual inputs require authenticated owner sender/actor/triggering_actor, exact
repository, issue, allowed base, full Expected-head and Spec-commit, and the full
reviewed runner SHA matching GitHub's selected SHA. Reruns (attempt > 1) stop.
The runner consumes the genuine workflow_dispatch event; it does not forge an
owner issue comment. Existing issue-comment diagnostic authorization remains
supported. Production branch allowlists are unchanged; cursor/* is not enabled.

- diagnostic_live=false (default): validate the contract and run mocked tests.
  No OIDC token is requested, no WIF exchange or provider request occurs, and no
  external writes occur. GitHub still checks out source and may account for runner
  time; this is provider-offline, not a claim that GitHub infrastructure is offline.
- diagnostic_live=true plus the explicit CLI live option: after the same offline
  validation/tests, request an ephemeral OIDC token, exchange through existing WIF,
  and make one fixed tool-free Messages request. The temporary token file is
  private and removed on exit. No retries, file tools, comments, commits or PRs.

The diagnostic request is pinned to claude-sonnet-5, a fixed 19-character user
prompt, no system message/tools/history, thinking disabled and max_tokens=128.
The diagnostic ignores a different CLAUDE_MODEL environment setting; production
behavior is unchanged. Timeout is 30 seconds for the Messages request.

Failure output includes only fixed stage labels, numeric HTTP status and
allowlisted error.type. It never prints raw errors, credentials, OIDC claims,
provider text or identifiers. WIF errors with appended claims retain safe status.
Malformed duplicate Expected-head fields fail before any network access.

## Price evidence and the proposed one-test approval

Checked 2026-10-11 against official Anthropic documentation:
- claude-sonnet-5 remains active (legacy), with first-party API prices of USD 2
  per million input tokens and USD 10 per million output tokens.
  https://platform.claude.com/docs/en/models/sonnet-5/overview
  https://platform.claude.com/docs/en/about-claude/pricing
- Token counting is free but estimates may differ slightly from generation usage.
  https://platform.claude.com/docs/en/build-with-claude/token-counting

This route uses api.anthropic.com directly with existing WIF, not Claude Code
subscription credit, Bedrock or a new model. Account-specific billing remains
unverified. No pricing, subscription, balance or account setting was changed.

The output component is bounded to USD 0.00128 at the verified rate. Total model
usage estimate is (2 * input_tokens + 10 * 128) / 1,000,000 USD. As an illustration,
256 input tokens would give USD 0.001792. The fixed short prompt prevents repository
or user-supplied context growth, but an actual token count was NOT requested.

Proposed approval: one bounded diagnostic generation with an intended USD 0.01
model-usage budget, no automatic retry, no other model, no tool calls, no account
changes. This is NOT an enforceable provider-side dollar ceiling. Current API
controls enforce request shape/output/retry limits, not a billing cutoff. Taxes,
account adjustments, other simultaneous usage and GitHub charges are excluded.
If a strict invoice-level USD cap is required, do not run: obtain an approved
provider-side enforcement mechanism first. Do not change account limits yourself.

## Reproducible validation and execution plan

Baseline for this revision: PR #54 head db523d3bd12e1ed36530b834f76ee134f2f3146a.
Prior main source: 3ddbd37a6d37036aefe93d381b6583a40c3f4556.

Offline checks performed:
- python -m unittest discover -s tests -p 'test_claude*.py' -v: 42 passed.
- py_compile for the runner and new tests: passed.
- git diff --check: passed.
- YAML parsed successfully with PyYAML; actionlint is not installed.
- All provider/GitHub/WIF execution in tests is mocked; no real Actions dispatch,
  provider request, external job or account configuration was performed.

After independent review and approval to publish this draft revision:
1. Verify all remote files and exact new head. Do not merge to run diagnostics.
2. An authorized owner can select the reviewed PR branch on the existing
   ai-dispatcher workflow, using agent=CLAUDE-DIAGNOSTIC and live=false. Use the
   exact new head for diagnostic_runner_sha. Do not dispatch the old main version.
   GitHub supports manual runs against selected branches when the workflow already
   exists on default; this file already exists there. Actual launch is not tested.
   https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-running-a-workflow
3. Check job graph: dispatch, implement and diagnose_live skipped; diagnose
   succeeds without any OIDC/WIF/provider request. If not, stop; do not retry an ambiguous run.
4. Only after explicit one-test approval, launch one fresh manual run with
   live=true and the same reviewed contract. Do not use a rerun or broaden WIF.
5. Capture sanitized stage/status/type. WIF failure, Messages failure and malformed
   response have different stages. A successful OK verifies only this small
   request, not production tools, long contexts, official Action or Studio.
6. If provider configuration needs correction, obtain required authorization.
   Then separately approve the exact production base/head and a non-overlapping
   Claude implementation task. Verify commit, tests and draft PR before reporting
   Claude's return. Keep Studio and public-PvP gates intact.

Read-only branch check on 2026-10-11: claude-dev is
59443306f230e719cf90ccda03afd9cdc12e3779. It is suitable as a diagnostic identity
check only; it is not approval to restart stale training work. Recheck before run.
Use the established approved scope SHA d7db9eeef4c3b1f25900f556bc1f0afc376922ca
only after confirming that is still the intended diagnostic contract.
