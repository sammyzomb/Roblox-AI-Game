import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import claude_implementer as runner


class ImplementationTests(unittest.TestCase):
    def test_anthropic_http_error_reason_exposes_only_safe_fields(self):
        detail = ('HTTP 400 calling https://api.anthropic.com/v1/messages: '
                  '{"type":"error","error":{"type":"invalid_request_error",'
                  '"message":"messages: input length exceeds the model context window"}}')
        reason = runner.anthropic_http_error_reason(detail)
        self.assertIn("invalid_request_error", reason)
        self.assertIn("context window", reason)

        secret = ('HTTP 401 calling https://api.anthropic.com/v1/messages: '
                  '{"error":{"type":"authentication_error",'
                  '"message":"Bearer sk-ant-private-token"}}')
        safe = runner.anthropic_http_error_reason(secret)
        self.assertEqual(safe, "Anthropic HTTP 401; authentication_error")
        self.assertNotIn("sk-ant", safe)

        malformed = "HTTP 400 calling https://api.anthropic.com/v1/messages: not-json"
        self.assertEqual(
            runner.anthropic_http_error_reason(malformed),
            "Anthropic HTTP 400; inspect API access/model settings",
        )


    def test_anthropic_http_error_reason_normalizes_safe_multiline_message(self):
        detail = ('HTTP 400 calling https://api.anthropic.com/v1/messages: \n'
                  '{"error":{"type":"invalid_request_error",'
                  '"message":"  messages:\\n  input length exceeds the model context window  "}}')
        self.assertEqual(
            runner.anthropic_http_error_reason(detail),
            "Anthropic HTTP 400; invalid_request_error: messages: input length exceeds the model context window",
        )

    @patch.dict(os.environ, {"GITHUB_RUN_ID": "42", "GITHUB_REPOSITORY": "owner/game"})
    def test_pr_policy_denial_requires_saved_ref_and_exact_error(self):
        ws = self.workspace()
        ws.write("src/main.lua", "return 2\n")
        policy = "HTTP 403 calling https://api.github.com/repos/owner/game/pulls: GitHub Actions is not permitted to create or approve pull requests"
        for error, expected in ((policy, runner.PRCreationPending),
                                (policy.replace("403", "500"), RuntimeError),
                                (policy.replace("/pulls:", "/git/refs:"), RuntimeError),
                                ("HTTP 403 calling https://api.github.com/repos/owner/game/pulls: Resource not accessible", RuntimeError)):
            calls = []
            def post(path, payload):
                calls.append(path)
                if path == "/pulls":
                    raise RuntimeError(error)
                return {"sha": "saved"}
            with self.subTest(error=error), patch.object(runner, "github_post", side_effect=post):
                with self.assertRaises(expected) as caught:
                    runner.publish(ws, "parent", "tree", 23, "claude-dev", "handoff")
                self.assertIn("/git/refs", calls)
                if expected is runner.PRCreationPending:
                    self.assertEqual(caught.exception.sha, "saved")
            # A failure while saving the ref must never be reclassified.
        with patch.object(runner, "github_post", side_effect=RuntimeError(policy)):
            with self.assertRaises(RuntimeError):
                runner.publish(ws, "parent", "tree", 23, "claude-dev", "handoff")

    def test_pending_pr_status_and_incomplete_exit_are_distinct(self):
        import tempfile
        for incomplete in (False, True):
            pending = runner.PRCreationPending("branch-url", "saved-sha", "claude-dev", incomplete)
            with tempfile.TemporaryDirectory() as directory:
                summary = str(Path(directory) / "summary.md")
                with patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": summary}), \
                     patch.object(runner, "load_event", return_value={}), \
                     patch.object(runner, "authorize", return_value=(23, "claude-dev", "a" * 40, "task")), \
                     patch.object(runner, "github_get", side_effect=pending), \
                     patch.object(runner, "comment") as comment:
                    self.assertEqual(runner.main(), int(incomplete))
                self.assertEqual([c.args[0] for c in comment.call_args_list], [23, 3])
                status = Path(summary).read_text()
                self.assertIn("WAITING_FOR_TECHNICAL_LEAD_PR", status)
                self.assertIn("saved-sha", status)
                self.assertIn("NOT run", status)
                self.assertTrue(status.startswith("[BLOCKED]" if incomplete else "[HANDOFF]"))

    @patch.dict(os.environ, {"CLAUDE_MODEL": "claude-sonnet-5"})
    def test_real_request_reserves_output_for_file_tools(self):
        messages = [{"role": "user", "content": "bounded increment"}]
        with patch.object(runner, "http_json", return_value={"stop_reason": "tool_use"}) as api:
            runner.request_claude(messages, "test-token")
        payload = api.call_args.kwargs["payload"]
        self.assertEqual(payload["thinking"], {"type": "disabled"})
        self.assertEqual(payload["max_tokens"], 8000)
        self.assertEqual(payload["model"], "claude-sonnet-5")
        self.assertEqual(payload["messages"], messages)
        self.assertEqual(payload["tools"], runner.TOOLS)

    @patch.dict(os.environ, {"CLAUDE_MODEL": "a-future-model"})
    def test_other_models_do_not_inherit_sonnet5_thinking_setting(self):
        with patch.object(runner, "http_json", return_value={}) as api:
            runner.request_claude([], "test-token")
        self.assertNotIn("thinking", api.call_args.kwargs["payload"])

    def workspace(self):
        return runner.Workspace({"tree": [
            {"path": "src/main.lua", "type": "blob", "mode": "100644", "sha": "code", "size": 10},
            {"path": "src/link.lua", "type": "blob", "mode": "120000", "sha": "link", "size": 10},
        ]}, lambda sha: "return 1\n")

    @patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/game", "EVENT_NAME": "issue_comment"})
    def test_only_owner_issue_command_authorized(self):
        event = {"action": "created", "issue": {"number": 23}, "comment": {
            "user": {"login": "owner"}, "author_association": "OWNER",
            "body": "[IMPLEMENT:CLAUDE]\nBase: claude-dev\nSpec-commit: " + "a" * 40}}
        self.assertEqual(runner.authorize(event)[:3], (23, "claude-dev", "a" * 40))
        event["comment"]["user"]["login"] = "outsider"
        with self.assertRaises(ValueError):
            runner.authorize(event)
        event["comment"]["user"]["login"] = "owner"
        event["issue"]["pull_request"] = {}
        with self.assertRaises(ValueError):
            runner.authorize(event)

    @patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/game", "EVENT_NAME": "issue_comment"})
    def test_continuation_only_same_issue_and_pinned_head(self):
        event = {"action": "created", "issue": {"number": 23}, "comment": {
            "user": {"login": "owner"}, "author_association": "OWNER"}}
        def body(base, pin=True):
            return ("[IMPLEMENT:CLAUDE]\nBase: " + base + "\nSpec-commit: " + "a" * 40
                    + ("\nExpected-head: " + "b" * 40 if pin else ""))
        for base in ("claude/issue-22/run-42-1", "other", "claude/issue-23/../../main"):
            event["comment"]["body"] = body(base)
            with self.assertRaises(ValueError):
                runner.authorize(event)
        event["comment"]["body"] = body("claude/issue-23/run-42-1", False)
        with self.assertRaises(ValueError):
            runner.authorize(event)
        event["comment"]["body"] = body("claude/issue-23/run-42-1")
        self.assertEqual(runner.authorize(event)[1], "claude/issue-23/run-42-1")

    def test_protected_paths_traversal_and_symlink_denied(self):
        ws = self.workspace()
        for path in ("../src/a.lua", "src/../a.lua", "src//a.lua", "src/.env.lua",
                     "src/secret.lua", "scripts/ai_dispatcher.py", "docs/AI_RULES.md",
                     ".github/workflows/a.yml", "src/link.lua"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                ws.write(path, "return 2\n")

    def test_edit_context_and_validation(self):
        ws = self.workspace()
        ws.tool("replace_text", {"path": "src/main.lua", "old": "return 1", "new": "return 2"})
        self.assertEqual(ws.read("src/main.lua"), "return 2\n")
        ws.validate()
        ws.write("src/config.json", "{bad json}")
        with self.assertRaises(ValueError):
            ws.validate()
        ws.write("src/config.json", "{}\n")
        ws.write("src/main.lua", "return 2 \n")
        with self.assertRaises(ValueError):
            ws.validate()

    def test_model_tool_round_trip_and_error_results(self):
        ws = self.workspace()
        responses = iter([
            {"stop_reason": "tool_use", "content": [
                {"type": "tool_use", "id": "bad", "name": "write_file", "input": {
                    "path": "scripts/ai_dispatcher.py", "content": "bad"}},
                {"type": "tool_use", "id": "good", "name": "write_file", "input": {
                    "path": "src/main.lua", "content": "return 2\n"}},
            ]},
            {"stop_reason": "end_turn", "content": [{"type": "text", "text": "Studio not run"}]},
        ])
        def request(messages):
            if len(messages) == 3:
                results = messages[-1]["content"]
                self.assertTrue(results[0]["is_error"])
                self.assertEqual(results[1]["tool_use_id"], "good")
            return next(responses)
        self.assertEqual(runner.run_agent(ws, "task", request), "Studio not run")

    def test_empty_truncated_and_budget_output_not_published(self):
        for response in (
            {"stop_reason": "max_tokens", "content": []},
            {"stop_reason": "end_turn", "content": [{"type": "text", "text": "done"}]},
        ):
            with self.assertRaises((ValueError, RuntimeError)):
                runner.run_agent(self.workspace(), "task", lambda messages: response)
        with self.assertRaises(ValueError):
            self.workspace().write("src/a.lua", "a" * (runner.MAX_FILE_BYTES + 1))

    def test_truncated_failure_is_explicit_without_response_text(self):
        response = {"stop_reason": "max_tokens", "model": "test-model",
                    "usage": {"output_tokens": 8000},
                    "content": [{"type": "text", "text": "PRIVATE-RESPONSE"}]}
        with self.assertRaisesRegex(runner.RunnerBlocked, "max_tokens"):
            runner.run_agent(self.workspace(), "task", lambda messages: response)
        diagnostic = runner.anthropic_safe_diagnostics(response)
        self.assertIn('"output_tokens": 8000', diagnostic)
        self.assertNotIn("PRIVATE-RESPONSE", diagnostic)

    def test_budget_checkpoint_preserves_edits_and_warns_before_limit(self):
        ws = self.workspace()
        response = {"stop_reason": "tool_use", "content": [{"type": "tool_use",
                    "id": "write", "name": "write_file", "input": {
                    "path": "src/main.lua", "content": "return 2\n"}}]}
        seen = []
        def request(messages):
            if len(messages) > 1:
                seen.append(messages[-1]["content"][-1]["text"])
            return response
        with self.assertRaises(runner.IncompleteDraft):
            runner.run_agent(ws, "task", request, rounds=2)
        self.assertIn("1 provider calls remain", seen[0])
        self.assertIn("STOP expanding scope", seen[0])
        self.assertEqual(ws.changes, {"src/main.lua": "return 2\n"})

    def test_invalid_empty_and_truncated_edits_never_become_checkpoint(self):
        for content in ("return 2 \n", None):
            ws = self.workspace()
            if content is not None:
                ws.write("src/main.lua", content)
            try:
                runner.run_agent(ws, "task", lambda _: {}, rounds=0)
            except (ValueError, runner.RunnerBlocked) as exc:
                self.assertNotIsInstance(exc, runner.IncompleteDraft)
            else:
                self.fail("Invalid checkpoint accepted")
        ws = self.workspace()
        ws.write("src/main.lua", "return 2\n")
        with self.assertRaises(runner.RunnerBlocked) as caught:
            runner.run_agent(ws, "task", lambda _: {"stop_reason": "max_tokens"})
        self.assertNotIsInstance(caught.exception, runner.IncompleteDraft)

    @patch.dict(os.environ, {"GITHUB_RUN_ID": "42", "GITHUB_REPOSITORY": "owner/game"})
    def test_main_checkpoint_reports_blocked_and_keeps_failure_exit(self):
        import base64
        def get(path):
            if path == "/issues/23":
                return {"state": "open", "title": "training", "body": "task"}
            if path.startswith("/branches/"):
                return {"commit": {"sha": "parent"}}
            if path.startswith("/git/commits/"):
                return {"tree": {"sha": "tree"}}
            if path.startswith("/git/trees/"):
                return {"tree": []}
            return {"content": base64.b64encode(b"governance").decode()}
        def agent(ws, prompt, request):
            ws.write("src/new.lua", "return 1\n")
            runner.budget_exhausted(ws)
        with patch.object(runner, "load_event", return_value={}), \
             patch.object(runner, "authorize", return_value=(23, "claude-dev", "a" * 40, "task")), \
             patch.object(runner, "github_get", side_effect=get), \
             patch.object(runner, "exchange_anthropic_token", return_value="test"), \
             patch.object(runner, "run_agent", side_effect=agent), \
             patch.object(runner, "publish", return_value=("draft-url", "sha")) as publish, \
             patch.object(runner, "comment") as comment:
            self.assertEqual(runner.main(), 1)
        self.assertTrue(publish.call_args.kwargs["incomplete"])
        blockers = [c.args for c in comment.call_args_list if c.args[1].startswith("[BLOCKED]")]
        self.assertEqual([b[0] for b in blockers], [23, 3])
        self.assertTrue(all("draft-url" in b[1] for b in blockers))
        self.assertFalse(any(c.args[1].startswith("[HANDOFF]") for c in comment.call_args_list))

    def test_deadline_checkpoint_requires_valid_edits(self):
        ws = self.workspace()
        ws.write("src/main.lua", "return 2\n")
        with patch.object(runner.time, "monotonic", side_effect=[0, 1201]):
            with self.assertRaises(runner.IncompleteDraft):
                runner.run_agent(ws, "task", lambda _: self.fail("Extra paid call"))

    @patch.dict(os.environ, {"GITHUB_RUN_ID": "42", "GITHUB_REPOSITORY": "owner/game"})
    def test_checkpoint_pr_is_explicitly_incomplete_and_draft(self):
        ws = self.workspace()
        ws.write("src/main.lua", "return 2\n")
        with patch.object(runner, "github_post", return_value={"sha": "new", "html_url": "pr"}) as post:
            runner.publish(ws, "parent", "tree", 23, "claude-dev", "No handoff", incomplete=True)
        pr = next(c.args[1] for c in post.call_args_list if c.args[0] == "/pulls")
        self.assertTrue(pr["draft"])
        self.assertIn("incomplete", pr["title"])
        self.assertIn("DO NOT MERGE", pr["body"])
        self.assertIn("NOT RUN", pr["body"])

    @patch.dict(os.environ, {"GITHUB_RUN_ID": "42", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_REPOSITORY": "owner/game"})
    def test_publish_creates_isolated_ref_and_draft_without_merge(self):
        ws = self.workspace()
        ws.write("src/main.lua", "return 2\n")
        calls = []
        def post(path, payload):
            calls.append((path, payload))
            return {"sha": "new", "html_url": "https://github.com/owner/game/pull/24"}
        with patch.object(runner, "github_post", side_effect=post):
            runner.publish(ws, "parent", "tree", 23, "claude-dev", "Studio not run")
        refs = [body for path, body in calls if path == "/git/refs"]
        self.assertEqual(refs[0]["ref"], "refs/heads/claude/issue-23/run-42-1")
        commits = [body for path, body in calls if path == "/git/commits"]
        self.assertEqual(commits[0]["parents"], ["parent"])
        prs = [body for path, body in calls if path == "/pulls"]
        self.assertTrue(prs[0]["draft"])
        self.assertEqual(prs[0]["base"], "claude-dev")
        self.assertFalse(any("merge" in path for path, _ in calls))


if __name__ == "__main__":
    unittest.main()
