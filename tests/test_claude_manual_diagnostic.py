"""Offline tests for the manual-only diagnostic route and workflow guardrails."""
import contextlib
import copy
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
CODE = 'b' * 40
ENV = {'GITHUB_REPOSITORY': 'sammyzomb/Roblox-AI-Game', 'EVENT_NAME': 'workflow_dispatch',
       'GITHUB_ACTOR': 'sammyzomb', 'GITHUB_TRIGGERING_ACTOR': 'sammyzomb',
       'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_SHA': CODE, 'CLAUDE_MODEL': 'do-not-use-this-model'}

def manual(live='false'):
    return {'sender': {'login': 'sammyzomb'},
            'repository': {'full_name': 'sammyzomb/Roblox-AI-Game'},
            'inputs': {'agent': 'CLAUDE-DIAGNOSTIC', 'issue_number': '23',
                       'diagnostic_live': live, 'diagnostic_base': 'claude-dev',
                       'diagnostic_expected_head': SHA, 'diagnostic_spec_commit': 'c' * 40,
                       'diagnostic_runner_sha': CODE}}

class ManualDiagnosticTests(unittest.TestCase):
    def call(self, event=None, live=False, environment=None, head=SHA):
        output = io.StringIO()
        def get(path):
            if path == '/issues/23': return {'state': 'open'}
            if path == '/branches/claude-dev': return {'commit': {'sha': head}}
            raise AssertionError('Unexpected read')
        with patch.dict(os.environ, {**ENV, **(environment or {})}), \
             patch.object(runner, 'load_event', return_value=manual() if event is None else event), \
             patch.object(runner, 'github_get', side_effect=get) as read, \
             patch.object(runner, 'exchange_anthropic_token', return_value='fixture') as wif, \
             patch.object(runner, 'http_json', return_value={'type':'message','stop_reason':'end_turn',
                          'content':[{'type':'text','text':'OK'}]}) as http, \
             patch.object(runner, 'github_post', side_effect=AssertionError('No writes')) as write, \
             patch.object(runner, 'publish', side_effect=AssertionError('No publication')) as publish, \
             patch.object(runner, 'run_agent', side_effect=AssertionError('No tools')) as agent, \
             contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            result = runner.diagnose_provider(live=live)
        write.assert_not_called(); publish.assert_not_called(); agent.assert_not_called()
        return result, output.getvalue(), read, wif, http

    def test_manual_offline_has_no_reads_wif_or_provider(self):
        result, output, read, wif, http = self.call()
        self.assertEqual(result, 0)
        self.assertIn('provider NOT called', output)
        read.assert_not_called(); wif.assert_not_called(); http.assert_not_called()

    def test_live_gate_default_blocks_before_network(self):
        result, _, read, wif, http = self.call(live=True)
        self.assertEqual(result, 1)
        read.assert_not_called(); wif.assert_not_called(); http.assert_not_called()

    def test_live_request_is_pinned_despite_model_environment(self):
        result, _, _, wif, http = self.call(manual('true'), live=True)
        self.assertEqual(result, 0); wif.assert_called_once(); http.assert_called_once()
        payload = http.call_args.kwargs['payload']
        self.assertEqual(payload, {'model':'claude-sonnet-5','max_tokens':128,
                                  'thinking':{'type':'disabled'},
                                  'messages':[{'role':'user','content':'Reply with OK only.'}]})
        self.assertEqual(http.call_args.args[0], 'https://api.anthropic.com/v1/messages')

    def test_offline_validation_does_not_honor_live_input_by_itself(self):
        result, _, read, wif, http = self.call(manual('true'), live=False)
        self.assertEqual(result, 0)
        read.assert_not_called(); wif.assert_not_called(); http.assert_not_called()

    def test_replay_actor_repo_and_code_mismatches_block_without_network(self):
        cases = [({'GITHUB_RUN_ATTEMPT':'2'}, manual('true')),
                 ({'GITHUB_ACTOR':'outsider'}, manual('true')),
                 ({'GITHUB_TRIGGERING_ACTOR':'outsider'}, manual('true')),
                 ({'GITHUB_SHA':'d'*40}, manual('true')),
                 ({'GITHUB_REPOSITORY':'other/repo'}, manual('true'))]
        for key, value in [('sender', {'login':'outsider'}),
                           ('repository', {'full_name':'other/repo'})]:
            event = manual('true'); event[key] = value; cases.append(({}, event))
        for environment, event in cases:
            with self.subTest(environment=environment, event=event):
                result, _, read, wif, http = self.call(event, live=True, environment=environment)
                self.assertEqual(result, 1)
                read.assert_not_called(); wif.assert_not_called(); http.assert_not_called()

    def test_malformed_dispatch_inputs_block_without_network(self):
        for key, value in [('agent','CLAUDE'), ('issue_number','23; echo bad'),
                           ('issue_number','0'), ('diagnostic_live','yes'),
                           ('diagnostic_live',True), ('diagnostic_base','cursor/support'),
                           ('diagnostic_base','claude/issue-24/run-1-1'),
                           ('diagnostic_base',None), ('diagnostic_expected_head','main'),
                           ('diagnostic_expected_head',SHA+'\nExpected-head: main'),
                           ('diagnostic_spec_commit','latest'), ('diagnostic_runner_sha',CODE+'\n')]:
            event = manual('true'); event['inputs'][key] = value
            with self.subTest(key=key,value=value):
                result, _, read, wif, http = self.call(event,live=True)
                self.assertEqual(result,1)
                read.assert_not_called(); wif.assert_not_called(); http.assert_not_called()

    def test_changed_base_head_stops_before_wif(self):
        result, output, _, wif, http = self.call(manual('true'),live=True,head='d'*40)
        self.assertEqual(result,1)
        self.assertEqual(json.loads(output)['stage'],'head_lookup')
        wif.assert_not_called(); http.assert_not_called()

    def test_workflow_keeps_diagnostics_out_of_normal_dispatch(self):
        text = (Path(__file__).resolve().parents[1]/'.github/workflows/ai-dispatcher.yml').read_text()
        dispatch = text.split('  dispatch:\n',1)[1].split('  implement:\n',1)[0]
        self.assertIn("inputs.agent != 'CLAUDE-DIAGNOSTIC' && !inputs.diagnostic_live",dispatch)
        diagnostic = text.split('  diagnose:\n',1)[1]
        offline_job, live_job = diagnostic.split('  diagnose_live:\n',1)
        self.assertNotIn('id-token:',offline_job)
        self.assertNotIn('GITHUB_TOKEN:',offline_job)
        self.assertIn('needs: diagnose',live_job)
        self.assertIn('inputs.diagnostic_live &&',live_job)
        for clause in ["github.event_name == 'workflow_dispatch'", "inputs.agent == 'CLAUDE-DIAGNOSTIC'",
                       "github.repository == 'sammyzomb/Roblox-AI-Game'",
                       'github.actor == github.repository_owner',
                       'github.triggering_actor == github.repository_owner',
                       'github.run_attempt == 1', 'inputs.diagnostic_runner_sha == github.sha']:
            self.assertIn(clause,diagnostic)
        self.assertIn('permissions:\n      contents: read\n      id-token: write',diagnostic)
        self.assertNotIn('issues: write',diagnostic)
        self.assertNotIn('contents: write',diagnostic)
        self.assertNotIn('pull-requests: write',diagnostic)
        self.assertIn('persist-credentials: false',diagnostic)
        offline, live = offline_job, live_job
        self.assertNotIn('curl',offline)
        self.assertNotIn('ANTHROPIC_IDENTITY_TOKEN_FILE',offline)
        self.assertIn('if: ${{ inputs.diagnostic_live }}',live)
        self.assertIn('trap ',live)
        self.assertIn('default: false',text.split('diagnostic_live:',1)[1].split('diagnostic_base:',1)[0])
        self.assertNotIn('pull_request:',text); self.assertNotIn('push:',text)

if __name__ == '__main__': unittest.main()
