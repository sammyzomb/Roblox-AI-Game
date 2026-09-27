#!/usr/bin/env python3
"""
AI Dispatcher v1

Purpose:
- Wake an assigned AI from a GitHub Issue command.
- Gather issue context + project governance docs.
- Call Claude or Grok through their official APIs.
- Post the AI response back to the same GitHub Issue.

Safety boundary for v1:
- Read-only repository access.
- No file writes, commits, pushes, merges, or PR creation.
- The model may propose implementation steps, but cannot mutate production code.
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from typing import Any

GITHUB_API = "https://api.github.com"
ANTHROPIC_API = "https://api.anthropic.com/v1/messages"
XAI_RESPONSES_API = "https://api.x.ai/v1/responses"

ROLE_MAP = {
    "CLAUDE": {
        "provider": "anthropic",
        "role": "Primary Programmer / 主要程式",
        "focus": "Production code planning, implementation analysis, tests, architecture compliance, and blocker reporting.",
    },
    "GROK": {
        "provider": "xai",
        "role": "Secondary Developer / Reviewer",
        "focus": "Architecture/code review, combat balance, exploit/mobile/networking risks, prototype analysis.",
    },
    "GROK-ART-PLANNER": {
        "provider": "xai",
        "role": "Art Planner / 美術策畫",
        "focus": "Art direction, asset planning, visual language, UI art direction, mobile readability.",
    },
    "GROK-ART-SUPERVISOR": {
        "provider": "xai",
        "role": "Art Supervisor / 美術監督",
        "focus": "Art review, visual quality standards, consistency, readability, mobile/performance review.",
    },
    "GROK-SFX-PLANNER": {
        "provider": "xai",
        "role": "Sound Effects Planner / 音效策畫",
        "focus": "SFX event map, naming, priorities, 2D/3D usage, mix rules, mobile/performance constraints.",
    },
    "GROK-MUSIC-PLANNER": {
        "provider": "xai",
        "role": "Music Planner / 音樂策畫",
        "focus": "Music identity, dynamic music states, loops, cues, transitions, and SFX alignment.",
    },
}

PROJECT_DOCS = [
    "README.md",
    "docs/AI_RULES.md",
    "docs/AI_COORDINATION_PROTOCOL.md",
    "docs/TEAM_ROLES.md",
    "docs/GAME_DESIGN.md",
    "docs/ARCHITECTURE.md",
]


def http_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    payload: dict[str, Any] | None = None,
    timeout: int = 90,
) -> Any:
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=body, method=method)
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} calling {url}: {detail}") from exc


def github_headers() -> dict[str, str]:
    token = require_env("GITHUB_TOKEN")
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "roblox-ai-game-dispatcher-v1",
    }


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def load_event() -> dict[str, Any]:
    path = require_env("EVENT_PATH")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_dispatch_marker(text: str) -> str | None:
    match = re.search(r"\[DISPATCH:([A-Z0-9-]+)\]", text.upper())
    if not match:
        return None
    key = match.group(1)
    return key if key in ROLE_MAP else None


def resolve_target(event: dict[str, Any]) -> tuple[int, str, str]:
    event_name = os.getenv("EVENT_NAME", "")
    if event_name == "workflow_dispatch":
        issue_number = int(require_env("MANUAL_ISSUE_NUMBER"))
        agent = require_env("MANUAL_AGENT").upper()
        if agent not in ROLE_MAP:
            raise RuntimeError(f"Unsupported agent: {agent}")
        return issue_number, agent, "manual workflow_dispatch"

    issue = event.get("issue") or {}
    comment = event.get("comment") or {}
    issue_number = int(issue["number"])
    body = str(comment.get("body") or "")
    agent = parse_dispatch_marker(body)
    if not agent:
        raise RuntimeError(
            "No supported [DISPATCH:<AGENT>] marker found. "
            "Use [DISPATCH:CLAUDE], [DISPATCH:GROK], "
            "[DISPATCH:GROK-ART-PLANNER], [DISPATCH:GROK-ART-SUPERVISOR], "
            "[DISPATCH:GROK-SFX-PLANNER], or [DISPATCH:GROK-MUSIC-PLANNER]."
        )
    return issue_number, agent, body


def github_get(path: str) -> Any:
    repo = require_env("GITHUB_REPOSITORY")
    return http_json(
        f"{GITHUB_API}/repos/{repo}{path}",
        headers=github_headers(),
    )


def github_post(path: str, payload: dict[str, Any]) -> Any:
    repo = require_env("GITHUB_REPOSITORY")
    return http_json(
        f"{GITHUB_API}/repos/{repo}{path}",
        method="POST",
        headers=github_headers(),
        payload=payload,
    )


def fetch_text_file(path: str) -> str:
    try:
        data = github_get(f"/contents/{path}")
    except Exception:
        return f"[{path}: unavailable]"
    import base64

    encoded = data.get("content", "")
    if not encoded:
        return f"[{path}: empty/unavailable]"
    return base64.b64decode(encoded).decode("utf-8", errors="replace")


def build_context(issue_number: int, agent: str, trigger_text: str) -> str:
    issue = github_get(f"/issues/{issue_number}")
    comments = github_get(f"/issues/{issue_number}/comments?per_page=100")

    latest_comments = comments[-30:] if isinstance(comments, list) else []
    comment_text = "\n\n".join(
        f"COMMENT by {c.get('user', {}).get('login', 'unknown')}:\n{c.get('body', '')}"
        for c in latest_comments
    )

    docs = "\n\n".join(
        f"===== {path} =====\n{fetch_text_file(path)[:16000]}"
        for path in PROJECT_DOCS
    )

    role = ROLE_MAP[agent]
    return f"""
You are acting as {agent}.
Project role: {role['role']}
Role focus: {role['focus']}

Repository: {require_env('GITHUB_REPOSITORY')}
Issue: #{issue_number}
Issue title: {issue.get('title', '')}
Issue body:
{issue.get('body', '')}

Dispatch trigger:
{trigger_text}

Recent issue comments:
{comment_text}

Core project governance/context:
{docs}

PROJECT EXECUTION RULES:
- GitHub is the source of truth.
- ChatGPT is Technical Lead / Primary Coordinator.
- Claude is the default owner of production code.
- Cursor is not a dependency.
- Do not modify main directly.
- Do not pretend you committed, pushed, opened a PR, tested in Studio, or changed files unless the context proves it.
- This dispatcher v1 is READ-ONLY. You cannot mutate repository files.
- If the task requires code/file changes, provide a concrete implementation plan and exact next actions for the assigned production owner.
- If blocked, say exactly what dependency is missing.
- If the requested work is complete as a review/planning deliverable, provide the full deliverable content when practical.

OUTPUT FORMAT:
Start with exactly one of:
[STATUS]
[BLOCKED]
[HANDOFF]
[COMPLETE]
[AVAILABLE]

Then include:
Agent: {agent}
Task: Issue #{issue_number}
Completed since last update:
Currently working on:
Next milestone:
Blocked by:

After that, provide the useful work product or technical details.
Keep claims grounded in the supplied repository/Issue context.
""".strip()


def call_anthropic(prompt: str) -> str:
    key = require_env("ANTHROPIC_API_KEY")
    model = os.getenv("CLAUDE_MODEL", "claude-sonnet-5").strip() or "claude-sonnet-5"
    data = http_json(
        ANTHROPIC_API,
        method="POST",
        headers={
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
        payload={
            "model": model,
            "max_tokens": 6000,
            "messages": [{"role": "user", "content": prompt}],
        },
        timeout=180,
    )
    parts = [
        block.get("text", "")
        for block in data.get("content", [])
        if block.get("type") == "text"
    ]
    text = "\n".join(p for p in parts if p).strip()
    if not text:
        raise RuntimeError("Anthropic returned no text content.")
    return text


def extract_xai_text(data: dict[str, Any]) -> str:
    if isinstance(data.get("output_text"), str) and data["output_text"].strip():
        return data["output_text"].strip()

    pieces: list[str] = []
    for item in data.get("output", []) or []:
        for content in item.get("content", []) or []:
            value = content.get("text")
            if isinstance(value, str) and value.strip():
                pieces.append(value)
    return "\n".join(pieces).strip()


def call_xai(prompt: str) -> str:
    key = require_env("XAI_API_KEY")
    model = os.getenv("XAI_MODEL", "grok-4.7").strip() or "grok-4.7"
    data = http_json(
        XAI_RESPONSES_API,
        method="POST",
        headers={"Authorization": f"Bearer {key}"},
        payload={
            "model": model,
            "input": prompt,
        },
        timeout=180,
    )
    text = extract_xai_text(data)
    if not text:
        raise RuntimeError("xAI returned no text content.")
    return text


def post_result(issue_number: int, agent: str, text: str) -> None:
    marker = f"<!-- ai-dispatcher-v1 agent={agent} -->"
    body = f"{marker}\n{text}"
    # GitHub issue comments have a maximum body size; keep room for marker.
    if len(body) > 60000:
        body = body[:59500] + "\n\n[TRUNCATED BY AI DISPATCHER V1]"
    github_post(f"/issues/{issue_number}/comments", {"body": body})


def post_failure(issue_number: int, agent: str, error: Exception) -> None:
    message = (
        f"<!-- ai-dispatcher-v1 agent={agent} failure=true -->\n"
        "[BLOCKED]\n"
        f"Agent: {agent}\n"
        f"Task: Issue #{issue_number}\n"
        "Completed since last update: Dispatcher received the task.\n"
        "Currently working on: Unable to continue because the automated dispatch failed.\n"
        "Next milestone: Retry after the integration issue is fixed.\n"
        f"Blocked by: {error}\n"
    )
    github_post(f"/issues/{issue_number}/comments", {"body": message[:60000]})


def main() -> int:
    event = load_event()
    issue_number = 0
    agent = "UNKNOWN"
    try:
        issue_number, agent, trigger = resolve_target(event)
        prompt = build_context(issue_number, agent, trigger)
        provider = ROLE_MAP[agent]["provider"]
        if provider == "anthropic":
            result = call_anthropic(prompt)
        elif provider == "xai":
            result = call_xai(prompt)
        else:
            raise RuntimeError(f"Unsupported provider: {provider}")
        post_result(issue_number, agent, result)
        print(f"Dispatched Issue #{issue_number} to {agent}")
        return 0
    except Exception as exc:
        print(f"Dispatcher failure: {exc}", file=sys.stderr)
        if issue_number and agent != "UNKNOWN":
            try:
                post_failure(issue_number, agent, exc)
            except Exception as post_exc:
                print(f"Failed to post blocker comment: {post_exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
