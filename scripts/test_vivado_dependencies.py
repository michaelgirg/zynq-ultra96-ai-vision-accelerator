"""The portable preflight must reject missing shared helpers and source inputs."""
import tempfile
import unittest
from pathlib import Path
from check_vivado_dependencies import check


class DependencyTests(unittest.TestCase):
    def test_missing_shared_helper_and_rtl(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "vivado/scripts"
            scripts.mkdir(parents=True)
            (root / "scripts").mkdir()
            # Fixtures are generated test inputs, not repository sources.
            (scripts / "caller.tcl").write_text(
                'source [file join $script_dir "shared.tcl"]\n'
                'read_verilog [file join $repo_root "rtl/core.sv"]\n')
            self.assertEqual(len(check(root)), 2)
            (scripts / "shared.tcl").touch()
            (root / "rtl").mkdir()
            (root / "rtl/core.sv").touch()
            self.assertEqual(check(root), [])

    def test_missing_powershell_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "vivado/scripts").mkdir(parents=True)
            (root / "scripts").mkdir()
            (root / "scripts/run_ultra96_test.ps1").write_text('Invoke-VivadoStage "missing.tcl"')
            self.assertEqual(len(check(root)), 1)


if __name__ == "__main__":
    unittest.main()
