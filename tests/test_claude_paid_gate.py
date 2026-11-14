"""Static regression checks for the proposed paid Claude implementation gate.

These checks do not start workflows, call providers, or prove live billing limits.
"""
from pathlib import Path
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / ".github" / "workflows" / "ai-dispatcher.yml"


class PaidClaudeGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        cls.implement = workflow.split("\n  implement:\n", 1)[1].split("\n  diagnose:\n", 1)[0]

    def test_implementation_defaults_to_disabled_without_explicit_opt_in(self):
        self.assertIn("vars.CLAUDE_IMPLEMENT_ENABLED == 'true'", self.implement)

    def test_existing_owner_and_pinned_comment_conditions_are_preserved(self):
        for condition in (
            "github.event_name == 'issue_comment'",
            "github.event.comment.user.login == github.repository_owner",
            "github.event.comment.author_association == 'OWNER'",
            "contains(github.event.comment.body, '[IMPLEMENT:CLAUDE]')",
        ):
            with self.subTest(condition=condition):
                self.assertIn(condition, self.implement)

    def test_implementation_cannot_run_as_manual_dispatch(self):
        self.assertNotIn("github.event_name == 'workflow_dispatch'", self.implement)


if __name__ == "__main__":
    unittest.main()
