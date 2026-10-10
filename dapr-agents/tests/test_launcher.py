"""Secret-free checks for launch configuration boundaries."""

from __future__ import annotations

import importlib.util
import io
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


LAUNCHER = Path(__file__).parents[1] / "files/home/dapr-kit/launcher.py"
PROVIDERS = Path(__file__).parents[1] / "files/home/dapr-kit/providers"
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


class ShutdownTests(unittest.TestCase):
    def test_graceful_shutdown_signals_and_reaps_the_process_group(self) -> None:
        process = unittest.mock.Mock(pid=1234)
        process.poll.return_value = None
        process.wait.return_value = 0

        with patch.object(launcher.os, "killpg") as killpg:
            launcher.terminate_process_group(process)

        killpg.assert_called_once_with(1234, launcher.signal.SIGTERM)
        process.wait.assert_called_once_with(timeout=launcher.SHUTDOWN_GRACE_SECONDS)

    def test_shutdown_escalates_to_sigkill_after_the_grace_period(self) -> None:
        process = unittest.mock.Mock(pid=1234)
        process.poll.return_value = None
        process.wait.side_effect = [
            subprocess.TimeoutExpired("dapr", launcher.SHUTDOWN_GRACE_SECONDS),
            0,
        ]

        with patch.object(launcher.os, "killpg") as killpg:
            launcher.terminate_process_group(process)

        self.assertEqual(
            killpg.call_args_list,
            [
                unittest.mock.call(1234, launcher.signal.SIGTERM),
                unittest.mock.call(1234, launcher.signal.SIGKILL),
            ],
        )

    def test_shutdown_does_not_repeat_a_forwarded_sigterm(self) -> None:
        process = unittest.mock.Mock(pid=1234)
        process.poll.return_value = None
        process.wait.side_effect = [
            subprocess.TimeoutExpired("dapr", launcher.SHUTDOWN_GRACE_SECONDS),
            0,
        ]

        with patch.object(launcher.os, "killpg") as killpg:
            launcher.terminate_process_group(process, term_sent=True)

        killpg.assert_called_once_with(1234, launcher.signal.SIGKILL)

    def test_shutdown_reports_a_final_timeout_without_a_traceback(self) -> None:
        process = unittest.mock.Mock(pid=1234)
        process.poll.return_value = None
        process.wait.side_effect = [
            subprocess.TimeoutExpired("dapr", launcher.SHUTDOWN_GRACE_SECONDS),
            subprocess.TimeoutExpired("dapr", launcher.SHUTDOWN_KILL_SECONDS),
        ]
        stderr = io.StringIO()

        with patch.object(launcher.os, "killpg"):
            with patch.object(sys, "stderr", stderr):
                launcher.terminate_process_group(process)

        self.assertEqual(
            stderr.getvalue(),
            "dapr-agents: child process did not exit after SIGKILL\n",
        )


class ComponentTests(unittest.TestCase):
    def test_every_bundled_provider_has_the_expected_dapr_component(self) -> None:
        expected = {
            "openai": ("conversation.openai", "OPENAI_API_KEY", True),
            "anthropic": ("conversation.anthropic", "ANTHROPIC_API_KEY", True),
            "deepseek": ("conversation.deepseek", "DEEPSEEK_API_KEY", True),
            "google": ("conversation.googleai", "GOOGLE_API_KEY", True),
            "huggingface": ("conversation.huggingface", "HF_TOKEN", True),
            "mistral": ("conversation.mistral", "MISTRAL_API_KEY", True),
        }
        self.assertEqual(set(launcher.SUPPORTED_PROVIDERS), set(expected))
        for provider, (component_type, credential, has_model) in expected.items():
            with self.subTest(provider=provider):
                component = (PROVIDERS / f"{provider}.yaml").read_text()
                self.assertIn("pinned Dapr Runtime v1.18.2", component)
                self.assertIn("apiVersion: dapr.io/v1alpha1", component)
                self.assertIn("name: llm-provider", component)
                self.assertIn(f"type: {component_type}", component)
                self.assertIn("version: v1", component)
                self.assertIn(f"envRef: {credential}", component)
                self.assertEqual(
                    "envRef: SANDBOX_DAPR_AGENTS_MODEL" in component,
                    has_model,
                )
                self.assertNotIn("envRef: DAPR_", component)
                self.assertNotIn("{{", component)

    def test_every_bundled_provider_delegates_an_omitted_model_to_dapr(self) -> None:
        for provider in launcher.SUPPORTED_PROVIDERS:
            with self.subTest(provider=provider):
                self.assertEqual(launcher.resolve_provider_model(provider, ""), "")

    def test_rejects_an_unknown_provider(self) -> None:
        with self.assertRaisesRegex(launcher.KitError, "provider must be one of"):
            launcher.resolve_provider_model("unknown", "")

    def test_every_bundled_provider_accepts_an_explicit_model_override(self) -> None:
        for provider in launcher.SUPPORTED_PROVIDERS:
            with self.subTest(provider=provider):
                model = f"{provider}-model"
                self.assertEqual(launcher.resolve_provider_model(provider, model), model)

    def test_resource_overlay_replaces_provider_and_keeps_supporting_components(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundled = root / "bundled"
            override = root / "override"
            providers = root / "providers"
            destination = root / "staged"
            bundled.mkdir()
            override.mkdir()
            providers.mkdir()
            (bundled / "agent-memory.yaml").write_text("name: agent-memory\n")
            (providers / "openai.yaml").write_text("type: conversation.openai\n")
            (override / "llm-provider.yaml").write_text("type: conversation.anthropic\n")

            effective_model = launcher.stage_resources(
                bundled, providers, destination, "openai", "", override
            )

            self.assertEqual(effective_model, "")
            self.assertEqual(
                (destination / "llm-provider.yaml").read_text(),
                "type: conversation.anthropic\n",
            )
            self.assertEqual(
                (destination / "agent-memory.yaml").read_text(),
                "name: agent-memory\n",
            )

    def test_example_mode_selects_a_bundled_provider(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            bundled = root / "bundled"
            providers = root / "providers"
            runtime = root / "runtime"
            bundled.mkdir()
            providers.mkdir()
            workspace.mkdir()
            (providers / "mistral.yaml").write_text("type: conversation.mistral\n")
            python = runtime / "example/.venv/bin/python"

            with patch.object(launcher, "BASE_RESOURCES", bundled):
                with patch.object(launcher, "PROVIDERS_ROOT", providers):
                    with patch.object(launcher, "RUNTIME_ROOT", runtime):
                        with patch.object(
                            launcher, "sync_bundled_environment", return_value=python
                        ):
                            with patch.dict(
                                os.environ,
                                {
                                    "DAPR_KIT_PROVIDER": "mistral",
                                    "SANDBOX_DAPR_AGENTS_MODEL": "mistral-small-latest",
                                },
                                clear=True,
                            ):
                                app_dir, app_command, resources = launcher.prepare_application(
                                    "example", workspace
                                )
                                self.assertEqual(
                                    os.environ["SANDBOX_DAPR_AGENTS_MODEL"],
                                    "mistral-small-latest",
                                )

            self.assertEqual(app_dir, runtime / "example")
            self.assertEqual(app_command, [str(python), "agent.py"])
            self.assertEqual(resources, runtime / "resources")
            self.assertEqual(
                (resources / "llm-provider.yaml").read_text(),
                "type: conversation.mistral\n",
            )

    def test_example_mode_keeps_an_empty_model_for_the_dapr_default(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            bundled = root / "bundled"
            providers = root / "providers"
            runtime = root / "runtime"
            bundled.mkdir()
            providers.mkdir()
            workspace.mkdir()
            (providers / "anthropic.yaml").write_text("type: conversation.anthropic\n")
            python = runtime / "example/.venv/bin/python"

            with patch.object(launcher, "BASE_RESOURCES", bundled):
                with patch.object(launcher, "PROVIDERS_ROOT", providers):
                    with patch.object(launcher, "RUNTIME_ROOT", runtime):
                        with patch.object(
                            launcher, "sync_bundled_environment", return_value=python
                        ):
                            with patch.dict(
                                os.environ,
                                {"DAPR_KIT_PROVIDER": "anthropic"},
                                clear=True,
                            ):
                                launcher.prepare_application("example", workspace)
                                self.assertIn("SANDBOX_DAPR_AGENTS_MODEL", os.environ)
                                self.assertEqual(os.environ["SANDBOX_DAPR_AGENTS_MODEL"], "")

    def test_example_mode_accepts_a_provider_overlay(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workspace = root / "workspace"
            bundled = root / "bundled"
            providers = root / "providers"
            runtime = root / "runtime"
            override = workspace / "components"
            bundled.mkdir()
            providers.mkdir()
            override.mkdir(parents=True)
            (providers / "openai.yaml").write_text("type: conversation.openai\n")
            (override / "llm-provider.yaml").write_text("type: conversation.echo\n")
            python = runtime / "example/.venv/bin/python"

            with patch.object(launcher, "BASE_RESOURCES", bundled):
                with patch.object(launcher, "PROVIDERS_ROOT", providers):
                    with patch.object(launcher, "RUNTIME_ROOT", runtime):
                        with patch.object(
                            launcher, "sync_bundled_environment", return_value=python
                        ):
                            with patch.dict(
                                os.environ,
                                {"DAPR_KIT_RESOURCES_DIR": "components"},
                                clear=True,
                            ):
                                _, _, resources = launcher.prepare_application(
                                    "example", workspace
                                )

            self.assertEqual(
                (resources / "llm-provider.yaml").read_text(),
                "type: conversation.echo\n",
            )


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
