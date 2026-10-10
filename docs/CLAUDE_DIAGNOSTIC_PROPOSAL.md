# Claude provider diagnostic proposal

For review by the existing Technical Lead. This is an offline-tested review
proposal against `sammyzomb/Roblox-AI-Game` main commit
`3ddbd37a6d37036aefe93d381b6583a40c3f4556`. It does not restore Claude by itself.

## What changes

The existing implementation runner accepts `--diagnostic`. With this flag alone,
it validates the owner-authored event contract without network access. The
separate `--live-provider-check` flag permits one tool-free provider request only
in diagnostic mode. Neither diagnostic path posts comments, creates branches,
publishes changes, opens PRs, executes file tools, or starts gameplay work.
Normal invocation still calls the existing production entry point.

Diagnostic events require the exact `[DIAGNOSTIC:CLAUDE]` marker, repository owner
and OWNER association, an issue creation-comment event, a single allowed Base,
Spec-commit, and one full Expected-head SHA. The repository must be exactly
`sammyzomb/Roblox-AI-Game`. The existing base allowlist is unchanged. Live mode
also checks the issue remains open and resolves the base SHA before exchanging
credentials. A mismatch stops before the provider request. Mixed diagnostic and
implementation markers are rejected on both paths.

There is deliberately NO workflow change. Existing workflows do not route this
new marker. Technical Lead must review and explicitly authorize any later
integration or invocation, including its cost. Do not combine markers to trigger
an existing workflow, and do not blindly rerun the failed historical jobs.

## Diagnostic limits

The opt-in request contains a fixed prompt, no repository content and no tools,
uses the existing configured model and WIF mechanism, and limits output to 128
tokens with a 30-second HTTP timeout and no retry loop. These are request bounds,
not a dollar spending guarantee. A later successful probe only establishes that
this bounded provider call worked; it does not validate production tools,
long-context requests, official Claude Code Action, or game functionality.

Only an exact OK response with a completed message is accepted. Unexpected,
truncated or tool-use responses fail closed without printing response content.
Failure output is structured JSON limited to a fixed execution stage, numeric
HTTP status when available and an allowlisted Anthropic error type; raw messages, response bodies, credentials and identifiers are never
printed by the diagnostic path. Unknown errors get a fixed generic report.
Detailed provider causes may still require separately reviewed diagnostics.

The existing production HTTP error sanitizer and budget settings are unchanged.
No credentials, account permissions, payment settings or branch access expand.
Current Cursor branches remain unaccepted by the custom runner. TL must choose
and approve a specific production base before extending that contract; this
proposal does not guess or enable arbitrary branches.

## Verified offline

- `python -m unittest discover -s tests -p 'test_claude*.py' -v`: 34 tests passed
  (19 existing runner tests plus 15 diagnostic tests).
- `python -m py_compile scripts/claude_implementer.py tests/test_claude_diagnostic.py`: passed.
- `git diff --check`: passed.
- All provider/WIF/GitHub requests in new tests are mocked; no live request,
  external write, CI invocation, push, merge, or Roblox Studio operation occurred.

Coverage includes offline default, one bounded call, no publishing/file tools,
owner/repository/marker/base/SHA validation, stale-head rejection before WIF,
HTTP 400/401/403/429/500/529, malformed duplicate Expected-head fields,
WIF failures with appended OIDC claims, secret-bearing/malformed errors, unexpected responses,
and production CLI compatibility. This is focused runner coverage, not a full
repository or game test run.

## Actual incident evidence

- Custom run 36903281477 / job 110507420033 (2026-10-01 UTC): WIF exchange succeeded;
  the first real model call returned HTTP 400. The old run omitted its error body.
  https://github.com/sammyzomb/Roblox-AI-Game/actions/runs/36903281477/job/110507420033
- Official run 36941472611 / job 110633721795: initialization followed by
  is_error:true, duration 216 ms, one turn, empty modelUsage and reported cost 0;
  no branch. This does not identify the underlying provider error.
  https://github.com/sammyzomb/Roblox-AI-Game/actions/runs/36941472611/job/110633721795
- No official run artifacts were available. The official workflow still fixes
  base_branch to claude-dev. This proposal does not modify that separate route.

## Next review decision

Review this patch and the existing runner contract first. If accepted, decide
whether to authorize a bounded diagnostic invocation and how to integrate it
without expanding permissions. Diagnose the returned category before changing
configuration. Account/access/payment changes need separate approval. Only after
provider recovery and an approved exact production base should TL assign a
small non-overlapping Claude task alongside Cursor and verify an actual commit,
tests and draft PR. Keep Studio/public-PvP gates unchanged.
