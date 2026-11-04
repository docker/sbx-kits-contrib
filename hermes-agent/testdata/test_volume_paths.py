import os
from pathlib import Path
import subprocess
import unittest


STATE = Path("/home/agent/.hermes/profiles/persistent")
# A root-owned empty tmpfs the hook would accept if it followed a symlinked ancestor.
DECOY = Path("/decoy/persistent")


class VolumePathsTest(unittest.TestCase):
    def test_refuses_missing_unmounted_and_symlink_paths(self):
        self.assertTrue(Path("/.dockerenv").exists())
        self.assertTrue(DECOY.is_mount())
        STATE.parent.mkdir(parents=True, exist_ok=True)
        self.assertFalse(os.path.lexists(STATE))
        for kind in ("missing", "directory", "symlink", "file", "symlinked ancestor"):
            with self.subTest(kind=kind):
                if kind == "directory":
                    STATE.mkdir()
                elif kind == "symlink":
                    STATE.rmdir()
                    STATE.symlink_to("/tmp")
                elif kind == "file":
                    STATE.unlink()
                    STATE.write_text("keep")
                elif kind == "symlinked ancestor":
                    STATE.unlink()
                    STATE.parent.rmdir()
                    STATE.parent.symlink_to(DECOY.parent)
                result = subprocess.run(
                    ["python3", "/kit/hermes-volume-init.py"],
                    env={**os.environ, "HERMES_INIT_VOLUME": "1", "HERMES_HOME": str(STATE)},
                    capture_output=True, text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Hermes volume initialization failed", result.stderr)
                self.assertEqual(Path("/tmp").stat().st_uid, 0)
                self.assertEqual(DECOY.stat().st_uid, 0)
                if kind == "file":
                    self.assertEqual(STATE.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
