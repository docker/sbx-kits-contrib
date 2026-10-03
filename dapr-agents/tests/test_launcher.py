"""Secret-free checks for launch configuration boundaries."""

from __future__ import annotations

import importlib.util
import socket
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


LAUNCHER = Path(__file__).parents[1] / "files/home/dapr-kit/launcher.py"
LLM_COMPONENT = Path(__file__).parents[1] / "files/home/dapr-kit/resources/llm-provider.yaml"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("dapr_kit_launcher", LAUNCHER)
assert SPEC and SPEC.loader
launcher = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(launcher)


class RelativeChildTests(unittest.TestCase):
    def test_accepts_an_existing_script_inside_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "agent.py"
            script.write_text("print('ok')\n")
            self.assertEqual(launcher.relative_child(root, "agent.py", "entrypoint"), script.resolve())

    def test_rejects_a_path_that_escapes_workspace(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(launcher.KitError, "stay inside"):
                launcher.relative_child(Path(directory), "../outside.py", "entrypoint")

    def test_rejects_a_file_for_resources_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            item = root / "resources.yaml"
            item.write_text("apiVersion: dapr.io/v1alpha1\n")
            with self.assertRaisesRegex(launcher.KitError, "must be a directory"):
                launcher.relative_child(root, item.name, "resources-dir", directory=True)


class ReadinessTests(unittest.TestCase):
    def test_port_ready_reports_connection_failure(self) -> None:
        with patch.object(socket, "create_connection", side_effect=OSError("closed")):
            self.assertFalse(launcher.port_ready(50006))

    def test_services_require_every_endpoint(self) -> None:
        compose_result = type("Result", (), {"returncode": 0, "stdout": "redis healthy"})()
        with patch.object(launcher, "compose", return_value=compose_result):
            with patch.object(launcher, "port_ready", side_effect=[True, True, False]):
                self.assertFalse(launcher.services_ready())


class ComponentTests(unittest.TestCase):
    def test_openai_component_uses_dapr_environment_references(self) -> None:
        component = LLM_COMPONENT.read_text()
        self.assertIn("envRef: OPENAI_API_KEY", component)
        self.assertIn("envRef: SANDBOX_DAPR_AGENTS_MODEL", component)
        self.assertNotIn("envRef: DAPR_", component)
        self.assertNotIn("{{", component)


class LockfileTests(unittest.TestCase):
    def test_rejects_incompatible_dapr_agents_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / "uv.lock"
            lock.write_text(
                'version = 1\n[[package]]\nname = "dapr-agents"\nversion = "0.9.0"\n'
            )
            with self.assertRaisesRegex(launcher.KitError, "dapr-agents==1.0.6"):
                launcher.validate_custom_lock(lock)

    def test_accepts_the_supported_dependency_set(self) -> None:
        source_lock = Path(__file__).parents[1] / "files/home/dapr-kit/example/uv.lock"
        launcher.validate_custom_lock(source_lock)

    def test_locked_project_with_spaces_uses_vm_local_environment(self) -> None:
        source_lock = Path(__file__).parents[1] / "files/home/dapr-kit/example/uv.lock"
        with tempfile.TemporaryDirectory(prefix="dapr agent ") as directory:
            project = Path(directory)
            (project / "pyproject.toml").write_text('[project]\nname = "fixture"\nversion = "0.1.0"\n')
            (project / "uv.lock").write_bytes(source_lock.read_bytes())
            runtime = project.parent / "runtime data"
            with patch.object(launcher, "RUNTIME_ROOT", runtime):
                with patch.object(launcher, "run_checked") as run_checked:
                    python, argv = launcher.locked_project_environment(project)
            expected = runtime / "venvs/custom/bin/python"
            self.assertEqual(python, expected)
            self.assertEqual(argv, [str(expected)])
            self.assertEqual(
                run_checked.call_args.kwargs["extra_env"]["UV_PROJECT_ENVIRONMENT"],
                str(runtime / "venvs/custom"),
            )

    def test_entrypoint_only_project_uses_bundled_environment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            runtime = project / "runtime"
            source_example = Path(__file__).parents[1] / "files/home/dapr-kit/example"
            with patch.object(launcher, "RUNTIME_ROOT", runtime):
                with patch.object(launcher, "EXAMPLE_ROOT", source_example):
                    with patch.object(launcher, "run_checked") as run_checked:
                        python, argv = launcher.locked_project_environment(project)
            expected = runtime / "example/.venv/bin/python"
            self.assertEqual(python, expected)
            self.assertEqual(argv, [str(expected)])
            run_checked.assert_called_once_with(
                ["uv", "sync", "--frozen", "--project", str(runtime / "example")]
            )
