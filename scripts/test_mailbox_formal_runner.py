"""Timeouts must retain diagnostics without leaving stale proof evidence."""
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import run_mailbox_formal as runner


class FormalRunnerTests(unittest.TestCase):
    def test_timeout_is_not_a_stale_pass(self):
        parent = runner.ROOT / 'generated/experiments'
        parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as folder:
            output = Path(folder)
            (output / 'result.json').write_text('{"result":"PASS"}')
            args = ['formal', '--yosys', 'yosys', '--output', folder, '--timeout-seconds', '30']
            with patch('sys.argv', args), patch.object(runner.subprocess, 'check_output', return_value='help'), \
                 patch.object(runner.subprocess, 'run', side_effect=subprocess.TimeoutExpired(
                     'yosys', 30, output=b'partial SAT diagnostics')):
                with self.assertRaisesRegex(SystemExit, 'no pass/counterexample claimed'):
                    runner.main()
            self.assertFalse((output / 'result.json').exists())
            self.assertIn('partial SAT diagnostics', (output / 'mailbox.log').read_text())
            self.assertIn('SOLVER TIMEOUT', (output / 'mailbox.log').read_text())


if __name__ == '__main__':
    unittest.main()
