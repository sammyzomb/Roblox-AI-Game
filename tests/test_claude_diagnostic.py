import contextlib
import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import claude_implementer as runner

SHA = 'a' * 40
ENV = {'GITHUB_REPOSITORY': 'sammyzomb/Roblox-AI-Game', 'EVENT_NAME': 'issue_comment'}

def event(body=None):
    return {'action': 'created', 'issue': {'number': 23}, 'comment': {
        'user': {'login': 'sammyzomb'}, 'author_association': 'OWNER',
        'body': body or '[DIAGNOSTIC:CLAUDE]\nBase: claude-dev\nExpected-head: ' + SHA + '\nSpec-commit: ' + 'b' * 40}}

class DiagnosticTests(unittest.TestCase):
    def invoke(self, *, live=False, fixture=None, response=None, error=None, sha=SHA, exchange_error=None):
        out, err = io.StringIO(), io.StringIO()
        def get(path):
            if path == '/issues/23':
                return {'state': 'open'}
            if path == '/branches/claude-dev':
                return {'commit': {'sha': sha}}
            self.fail('Unexpected GitHub read')
        with patch.dict(os.environ, ENV), patch.object(runner, 'load_event', return_value=fixture or event()), \
             patch.object(runner, 'github_get', side_effect=get) as reads, \
             patch.object(runner, 'exchange_anthropic_token', return_value='TEST-CREDENTIAL', side_effect=exchange_error) as exchange, \
             patch.object(runner, 'http_json', return_value=response, side_effect=error) as request, \
             patch.object(runner, 'github_post', side_effect=AssertionError('External write forbidden')) as writes, \
             patch.object(runner, 'publish', side_effect=AssertionError('Publish forbidden')) as publish, \
             patch.object(runner, 'run_agent', side_effect=AssertionError('File tools forbidden')) as agent, \
             contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = runner.diagnose_provider(live=live)
        writes.assert_not_called(); publish.assert_not_called(); agent.assert_not_called()
        return code, out.getvalue() + err.getvalue(), reads, exchange, request

    def test_default_is_network_free(self):
        code, text, reads, exchange, request = self.invoke()
        self.assertEqual(code, 0)
        self.assertIn('provider NOT called', text)
        reads.assert_not_called(); exchange.assert_not_called(); request.assert_not_called()

    def test_live_request_is_one_bounded_call_without_tools_or_task_context(self):
        response = {'type': 'message', 'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'OK'}]}
        code, text, _, exchange, request = self.invoke(live=True, response=response)
        self.assertEqual(code, 0)
        exchange.assert_called_once(); request.assert_called_once()
        kwargs = request.call_args.kwargs
        self.assertEqual(kwargs['timeout'], 30)
        self.assertEqual(kwargs['payload']['max_tokens'], 128)
        self.assertNotIn('tools', kwargs['payload'])
        self.assertEqual(kwargs['payload']['messages'], [{'role': 'user', 'content': 'Reply with OK only.'}])
        self.assertNotIn('TEST-CREDENTIAL', text)

    def test_head_mismatch_stops_before_provider(self):
        code, _, _, exchange, request = self.invoke(live=True, sha='c' * 40)
        self.assertEqual(code, 1); exchange.assert_not_called(); request.assert_not_called()

    def test_contract_rejections_are_network_free(self):
        original = event()['comment']['body']
        fixtures = []
        for body in [original.replace('Expected-head:', 'Missing-head:'),
                     original + '\nExpected-head: ' + SHA,
                     original + '\n[IMPLEMENT:CLAUDE]',
                     original + '\nExpected-head: main',
                     original + '\nExpected-head:',
                     original.replace('claude-dev', 'cursor/support-task'),
                     original.replace('[DIAGNOSTIC:CLAUDE]', '[IMPLEMENT:CLAUDE]'),
                     original.replace('claude-dev', 'claude/issue-24/run-1-1')]:
            fixtures.append(event(body))
        not_owner = event(); not_owner['comment']['user']['login'] = 'outsider'; fixtures.append(not_owner)
        pr = event(); pr['issue']['pull_request'] = {}; fixtures.append(pr)
        for fixture in fixtures:
            with self.subTest(fixture=fixture):
                code, _, reads, exchange, request = self.invoke(live=True, fixture=fixture)
                self.assertEqual(code, 1)
                reads.assert_not_called(); exchange.assert_not_called(); request.assert_not_called()

    def test_errors_reveal_only_status_and_allowlisted_type_without_retry(self):
        for status, kind in [(400, 'invalid_request_error'), (401, 'authentication_error'),
                             (403, 'permission_error'), (429, 'rate_limit_error'),
                             (500, 'api_error'), (529, 'overloaded_error')]:
            error = RuntimeError('HTTP %s calling https://api.anthropic.com/v1/messages: '
                                 '{"error":{"type":"%s","message":"secret TEST-CREDENTIAL"}}' % (status, kind))
            with self.subTest(status=status):
                code, text, _, _, request = self.invoke(live=True, error=error)
                self.assertEqual(code, 1); request.assert_called_once()
                self.assertEqual(json.loads(text), {'status': 'blocked', 'stage': 'provider_request',
                                                  'http_status': status, 'error_type': kind})
                self.assertNotIn('TEST-CREDENTIAL', text)

    def test_unknown_types_malformed_errors_and_exception_text_not_exposed(self):
        errors = [RuntimeError('HTTP 400 calling https://api.anthropic.com/v1/messages: not-json'),
                  RuntimeError('HTTP 400 calling https://api.anthropic.com/v1/messages: {"error":{"type":"private_marker","message":"private message"}}'),
                  ValueError('TEST-CREDENTIAL'), KeyError('TEST-CREDENTIAL')]
        for error in errors:
            with self.subTest(error=type(error).__name__):
                code, text, _, _, _ = self.invoke(live=True, error=error)
                self.assertEqual(code, 1)
                for private in ['TEST-CREDENTIAL', 'private_marker', 'private message', 'not-json']:
                    self.assertNotIn(private, text)

    def test_malformed_truncated_tool_and_error_responses_are_not_success(self):
        for response in [None, {}, {'type': 'message', 'stop_reason': 'max_tokens', 'content': []},
                         {'type': 'message', 'stop_reason': 'tool_use', 'content': [{'type': 'tool_use', 'name': 'write_file'}]},
                         {'type': 'result', 'is_error': True},
                         {'type': 'message', 'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'TEST-CREDENTIAL'}]}]:
            with self.subTest(response=response):
                code, text, _, _, request = self.invoke(live=True, response=response)
                self.assertEqual(code, 1); request.assert_called_once()
                self.assertNotIn('TEST-CREDENTIAL', text)

    def test_wif_failure_reports_stage_status_type_without_claims(self):
        error = RuntimeError('HTTP 401 calling https://api.anthropic.com/v1/oauth/token: '
                             '{"error":{"type":"authentication_error","message":"TEST-CREDENTIAL"}}'
                             '; OIDC claims={"sub":"private_subject","aud":"private_audience"}')
        code, text, _, exchange, request = self.invoke(live=True, exchange_error=error)
        self.assertEqual(code, 1)
        exchange.assert_called_once(); request.assert_not_called()
        self.assertEqual(json.loads(text), {'status': 'blocked', 'stage': 'wif_exchange',
                                          'http_status': 401, 'error_type': 'authentication_error'})
        for secret in ['TEST-CREDENTIAL', 'OIDC', 'private_subject', 'private_audience']:
            self.assertNotIn(secret, text)

    def test_wif_malformed_body_preserves_safe_http_status(self):
        error = RuntimeError('HTTP 400 calling https://api.anthropic.com/v1/oauth/token: '
                             'TEST-CREDENTIAL; OIDC claims={"sub":"private_subject"}')
        code, text, _, _, request = self.invoke(live=True, exchange_error=error)
        self.assertEqual(code, 1); request.assert_not_called()
        self.assertEqual(json.loads(text), {'status': 'blocked', 'stage': 'wif_exchange',
                                          'http_status': 400, 'error_type': 'unclassified_error'})

    def test_non_http_wif_failure_still_identifies_stage(self):
        code, text, _, _, request = self.invoke(live=True, exchange_error=RuntimeError('TEST-CREDENTIAL'))
        self.assertEqual(code, 1); request.assert_not_called()
        self.assertEqual(json.loads(text), {'status': 'blocked', 'stage': 'wif_exchange'})

    def test_wrong_repository_stops_before_network(self):
        with patch.dict(os.environ, {'GITHUB_REPOSITORY': 'other/repo'}), \
             patch.object(runner, 'load_event') as load, \
             patch.object(runner, 'http_json') as http, \
             contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(runner.diagnose_provider(live=True), 1)
        load.assert_not_called(); http.assert_not_called()

    def test_mixed_markers_cannot_start_production(self):
        fixture = event(event()['comment']['body'] + '\n[IMPLEMENT:CLAUDE]')
        with patch.dict(os.environ, ENV):
            with self.assertRaises(ValueError): runner.authorize(fixture)

    def test_cli_default_production_path_unchanged(self):
        with patch.object(runner, 'main', return_value=7) as main:
            self.assertEqual(runner.cli([]), 7); main.assert_called_once_with()

    def test_cli_live_flag_alone_rejected(self):
        with patch.object(runner, 'main') as main, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit): runner.cli(['--live-provider-check'])
        main.assert_not_called()

    def test_cli_diagnostic_default_is_offline(self):
        with patch.object(runner, 'diagnose_provider', return_value=0) as diagnose:
            runner.cli(['--diagnostic'])
            diagnose.assert_called_once_with(live=False)

if __name__ == '__main__':
    unittest.main()
