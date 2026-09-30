import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import claude_implementer as runner


class ImplementationTests(unittest.TestCase):
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
