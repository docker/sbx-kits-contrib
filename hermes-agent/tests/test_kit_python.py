"""Execute the recipes' launcher setup and prove it preserves a real venv."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class InterpreterTests(unittest.TestCase):
    def test_both_recipe_launchers_preserve_environment_and_arguments(self):
        for kit in ('hermes-agent', 'hermes-agent-mixin'):
            with self.subTest(kit=kit), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                project = home / '.hermes/hermes-agent'
                venv = project / 'venv'
                subprocess.run([sys.executable, '-m', 'venv', '--without-pip', str(venv)],
                               check=True, capture_output=True)
                python = venv / 'bin/python'
                site = subprocess.check_output([str(python), '-c',
                    'import sysconfig; print(sysconfig.get_path("purelib"))'], text=True).strip()
                (Path(site) / 'kit_runtime_fixture.py').write_text('VALUE = "venv-only"\n')
                bindir = home / '.local/bin'
                bindir.mkdir(parents=True)
                # Run the full relevant recipe instruction; the adapter itself is
                # immaterial here, so replace its contents with a no-op fixture.
                (bindir / 'hermes-codex-catalog-compat.py').write_text('pass\n')
                recipe = (ROOT / kit / (kit + '.dockerfile')).read_text()
                marker = 'RUN set -eu; \\\n    kit_python='
                start = recipe.index(marker)
                block = recipe[start:].split('\n\n', 1)[0]
                script = block.removeprefix('RUN ').replace('\\\n', '\n')
                env = dict(os.environ, HOME=str(home))
                subprocess.run(['sh', '-c', script], env=env, check=True, capture_output=True)
                launcher = bindir / 'hermes-kit-python'
                result = subprocess.check_output([str(launcher), '-c',
                    'import json,sys,kit_runtime_fixture; '
                    'print(json.dumps([sys.prefix,kit_runtime_fixture.VALUE,sys.argv[1:]]))',
                    'argument with spaces', '$literal'], env=env, text=True)
                self.assertEqual(json.loads(result), [str(venv), 'venv-only',
                                                      ['argument with spaces', '$literal']])


if __name__ == '__main__':
    unittest.main()
