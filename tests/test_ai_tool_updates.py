"""Exercise real Ansible CLI-update tasks against isolated fake executables."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


REPO = Path(__file__).resolve().parents[1]
FAKE_CLI = '''#!/usr/bin/python3
import pathlib, sys
p = pathlib.Path(__file__)
version = p.with_suffix('.version')
if sys.argv[1:] == ['--version']:
    print(version.read_text() if version.exists() else '1.0')
else:
    p.with_suffix('.attempted').touch()
    if p.name == 'broken':
        print('simulated download failure', file=sys.stderr)
        sys.exit(7)
    version.write_text('2.0')
'''


class UpdateTasksTest(unittest.TestCase):
    def run_updates(self, names, check=False):
        with tempfile.TemporaryDirectory(prefix='ai-update-test-') as directory:
            root = Path(directory)
            for name in names:
                if name != 'missing':
                    executable = root / name
                    executable.write_text(FAKE_CLI)
                    executable.chmod(0o755)
            play = [{
                'name': 'Exercise isolated CLI updates',
                'hosts': 'localhost', 'connection': 'local', 'gather_facts': False,
                'vars': {
                    'ansible_python_interpreter': '/usr/bin/python3',
                    'ansible_remote_tmp': str(root / 'remote'),
                    'ai_updates_home': str(root), 'ai_run_as_user': [],
                    'ai_update_failures': [],
                },
                'tasks': [
                    {'name': 'Run CLI tasks',
                     'ansible.builtin.include_tasks': str(REPO / 'playbooks/ai-tool-updates/tasks/update-ai-cli.yml'),
                     'loop': [{'name': n, 'binary': n, 'arguments': ['update']} for n in names],
                     'loop_control': {'loop_var': 'ai_cli'}},
                    {'name': 'Propagate failures', 'ansible.builtin.assert': {
                        'that': 'ai_update_failures | length == 0',
                        'fail_msg': '{{ ai_update_failures }}'}},
                ],
            }]
            playbook = root / 'test.yml'
            playbook.write_text(yaml.safe_dump(play))
            config = root / 'ansible.cfg'
            config.write_text('[defaults]\nretry_files_enabled = False\n')
            result = subprocess.run(
                ['ansible-playbook', '-i', 'localhost,', str(playbook)]
                + (['--check'] if check else []),
                env={**os.environ, 'ANSIBLE_CONFIG': str(config),
                     'ANSIBLE_LOCAL_TEMP': str(root / 'tmp')},
                text=True, capture_output=True, timeout=90,
            )
            attempted = {p.stem for p in root.glob('*.attempted')}
            versions = {p.stem: p.read_text() for p in root.glob('*.version')}
            return result, attempted, versions

    def test_successful_updates_and_version_reporting(self):
        result, attempted, versions = self.run_updates(['first', 'second'])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(attempted, {'first', 'second'})
        self.assertEqual(versions, {'first': '2.0', 'second': '2.0'})
        self.assertIn('changed=2', result.stdout)

    def test_failure_and_missing_binary_do_not_block_later_updates(self):
        result, attempted, versions = self.run_updates(['broken', 'missing', 'last'])
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(attempted, {'broken', 'last'})
        self.assertEqual(versions, {'last': '2.0'})
        self.assertIn('simulated download failure', result.stdout)
        self.assertIn('Missing executable:', result.stdout)

    def test_check_mode_does_not_run_updaters(self):
        result, attempted, versions = self.run_updates(['first'], check=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(attempted, set())
        self.assertEqual(versions, {})


if __name__ == '__main__':
    unittest.main()
