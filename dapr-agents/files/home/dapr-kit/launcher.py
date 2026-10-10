#!/usr/bin/env python3
"""Own the local Dapr service lifecycle for the Dapr Agents sandbox kit."""

from __future__ import annotations

import fcntl
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import tomllib
import urllib.error
import urllib.request
from pathlib import Path
from typing import NoReturn

KIT_ROOT = Path("/home/agent/dapr-kit")
RUNTIME_ROOT = Path.home() / ".local/share/dapr-kit"
COMPOSE_FILE = KIT_ROOT / "compose.yaml"
DAPR_CONFIG = KIT_ROOT / "config.yaml"
BASE_RESOURCES = KIT_ROOT / "resources"
PROVIDERS_ROOT = KIT_ROOT / "providers"
EXAMPLE_ROOT = KIT_ROOT / "example"
STARTUP_TIMEOUT_SECONDS = 120
SHUTDOWN_GRACE_SECONDS = 15
SHUTDOWN_KILL_SECONDS = 5
DAPR_AGENTS_VERSION = "1.0.6"
DAPR_SDK_MINOR = "1.18."
DEFAULT_PROVIDER = "openai"
SUPPORTED_PROVIDERS = (
    "openai",
    "anthropic",
    "deepseek",
    "google",
    "huggingface",
    "mistral",
)


class KitError(RuntimeError):
    """A concise, user-actionable launch failure."""


def fail(message: str) -> NoReturn:
    raise KitError(f"dapr-agents: {message}")


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def workspace_root() -> Path:
    """Use the runtime's launch directory instead of assuming a mount path."""
    return Path.cwd().resolve()


def relative_child(root: Path, value: str, label: str, *, directory: bool = False) -> Path:
    if not value:
        fail(f"{label} is required in custom mode")
    root = root.resolve()
    candidate = (root / value).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        fail(f"{label} must stay inside the supplied workspace")
    if not candidate.exists():
        fail(f"{label} does not exist: {value}")
    if directory and not candidate.is_dir():
        fail(f"{label} must be a directory: {value}")
    if not directory and not candidate.is_file():
        fail(f"{label} must be a file: {value}")
    return candidate


def resolve_provider_model(provider: str, model: str) -> str:
    """Validate a bundled provider selection and return its optional model override."""
    if provider not in SUPPORTED_PROVIDERS:
        fail(f"provider must be one of: {', '.join(SUPPORTED_PROVIDERS)}")
    return model


def stage_resources(
    source: Path,
    providers: Path,
    destination: Path,
    provider: str,
    model: str,
    override: Path | None = None,
) -> str:
    """Stage common components, the selected provider, then an optional overlay."""
    effective_model = resolve_provider_model(provider, model)
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    provider_component = providers / f"{provider}.yaml"
    if not provider_component.is_file():
        fail(f"bundled provider component is unavailable: {provider}")
    shutil.copy2(provider_component, destination / "llm-provider.yaml")
    if override is not None:
        shutil.copytree(override, destination, dirs_exist_ok=True)
    return effective_model


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def run_checked(
    argv: list[str], *, cwd: Path | None = None, extra_env: dict[str, str] | None = None
) -> None:
    try:
        child_env = os.environ.copy()
        if extra_env:
            child_env.update(extra_env)
        subprocess.run(argv, cwd=cwd, env=child_env, check=True)
    except FileNotFoundError:
        fail(f"required command is unavailable: {argv[0]}")
    except subprocess.CalledProcessError as exc:
        fail(f"command failed ({exc.returncode}): {' '.join(argv)}")


def wait_until(description: str, predicate) -> None:
    deadline = time.monotonic() + STARTUP_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(1)
    fail(f"timed out after {STARTUP_TIMEOUT_SECONDS}s waiting for {description}")


def docker_ready() -> bool:
    try:
        return subprocess.run(
            ["docker", "info"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5
        ).returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def compose(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["docker", "compose", "--project-name", "dapr-agents", "--file", str(COMPOSE_FILE), *argv],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def services_ready() -> bool:
    result = compose(["ps", "--format", "json"])
    if result.returncode != 0:
        return False
    # Compose's JSON shape varies across releases, so use it only to confirm
    # Redis health and establish the actual service endpoints with TCP probes.
    return (
        "redis" in result.stdout
        and "healthy" in result.stdout.lower()
        and all(port_ready(port) for port in (6379, 50005, 50006))
    )


def port_ready(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except OSError:
        return False


def locked_project_environment(project: Path) -> tuple[Path, list[str]]:
    pyproject = project / "pyproject.toml"
    lock = project / "uv.lock"
    if pyproject.exists() and lock.exists():
        validate_custom_lock(lock)
        venv = RUNTIME_ROOT / "venvs" / "custom"
        run_checked(
            ["uv", "sync", "--frozen", "--project", str(project), "--no-install-project"],
            extra_env={"UV_PROJECT_ENVIRONMENT": str(venv)},
        )
        return venv / "bin/python", [str(venv / "bin/python")]
    if pyproject.exists() and not lock.exists():
        fail("custom project has pyproject.toml but no uv.lock; lock it with `uv lock` first")
    python = sync_bundled_environment()
    return python, [str(python)]


def sync_bundled_environment() -> Path:
    example_runtime = RUNTIME_ROOT / "example"
    # Preserve the VM-local environment across application and sandbox restarts while
    # refreshing the immutable bundled source and lockfile.
    shutil.copytree(EXAMPLE_ROOT, example_runtime, dirs_exist_ok=True)
    run_checked(["uv", "sync", "--frozen", "--project", str(example_runtime)])
    return example_runtime / ".venv/bin/python"


def validate_custom_lock(lock: Path) -> None:
    try:
        with lock.open("rb") as handle:
            document = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        fail(f"could not read custom uv.lock: {exc}")

    versions = {
        package.get("name"): package.get("version")
        for package in document.get("package", [])
        if isinstance(package, dict)
    }
    if versions.get("dapr-agents") != DAPR_AGENTS_VERSION:
        fail(
            f"custom project must lock dapr-agents=={DAPR_AGENTS_VERSION}; "
            f"found {versions.get('dapr-agents') or 'no dapr-agents package'}"
        )
    for package in ("dapr", "dapr-ext-fastapi", "dapr-ext-workflow"):
        version = versions.get(package, "")
        if not version.startswith(DAPR_SDK_MINOR):
            fail(
                f"custom project must lock {package} to Dapr SDK {DAPR_SDK_MINOR}x; "
                f"found {version or 'no package'}"
            )


def prepare_application(mode: str, workspace: Path) -> tuple[Path, list[str], Path]:
    if mode not in {"example", "custom"}:
        fail("mode must be `example` or `custom`")

    resources = RUNTIME_ROOT / "resources"
    source_resources: Path | None = None
    resources_arg = env("DAPR_KIT_RESOURCES_DIR")
    if resources_arg:
        source_resources = relative_child(workspace, resources_arg, "resources-dir", directory=True)
        if not list(source_resources.glob("*.yaml")):
            fail("resources-dir must contain Dapr component YAML files")
    effective_model = stage_resources(
        BASE_RESOURCES,
        PROVIDERS_ROOT,
        resources,
        env("DAPR_KIT_PROVIDER", DEFAULT_PROVIDER),
        env("SANDBOX_DAPR_AGENTS_MODEL"),
        source_resources,
    )
    # Keep the variable present so Dapr can resolve every provider manifest's
    # envRef. An empty value delegates model selection to the Dapr component.
    os.environ["SANDBOX_DAPR_AGENTS_MODEL"] = effective_model

    if mode == "example":
        python = sync_bundled_environment()
        example_runtime = python.parents[2]
        return example_runtime, [str(python), "agent.py"], resources

    entrypoint = relative_child(workspace, env("DAPR_KIT_ENTRYPOINT"), "entrypoint")

    _, python = locked_project_environment(workspace)
    return workspace, [*python, str(entrypoint)], resources


def start_sidecar(app_dir: Path, app_command: list[str], resources: Path) -> subprocess.Popen[bytes]:
    app_id = env("DAPR_KIT_APP_ID", "dapr-agent")
    if not app_id:
        fail("app-id cannot be empty")
    argv = [
        "dapr",
        "run",
        "--app-id", app_id,
        "--app-port", "8001",
        "--dapr-http-port", "3500",
        "--dapr-grpc-port", "50001",
        "--placement-host-address", "localhost:50005",
        "--scheduler-host-address", "localhost:50006",
        "--config", str(DAPR_CONFIG),
        "--resources-path", str(resources),
        "--",
        *app_command,
    ]
    return subprocess.Popen(argv, cwd=app_dir, start_new_session=True)


def signal_process_group(process: subprocess.Popen[bytes] | None, signum: int) -> bool:
    """Send one signal when the child group still exists."""
    if process is None or process.poll() is not None:
        return False
    try:
        os.killpg(process.pid, signum)
    except ProcessLookupError:
        return False
    return True


def terminate_process_group(
    process: subprocess.Popen[bytes] | None, *, term_sent: bool = False
) -> None:
    """Reap the child group, escalating without leaking cleanup exceptions."""
    if process is None or process.poll() is not None:
        return
    if not term_sent:
        signal_process_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=SHUTDOWN_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        signal_process_group(process, signal.SIGKILL)
        try:
            process.wait(timeout=SHUTDOWN_KILL_SECONDS)
        except subprocess.TimeoutExpired:
            print(
                "dapr-agents: child process did not exit after SIGKILL",
                file=sys.stderr,
            )


def application_ready(process: subprocess.Popen[bytes]) -> bool:
    if process.poll() is not None:
        fail(f"Dapr sidecar exited during startup with status {process.returncode}")
    try:
        with urllib.request.urlopen("http://127.0.0.1:8001/openapi.json", timeout=2) as response:
            return response.status == 200
    except (urllib.error.URLError, TimeoutError):
        return False


def main() -> int:
    if not command_exists("docker"):
        fail("private Docker Engine is unavailable; use the shell-docker sandbox template")
    if not docker_ready():
        fail("private Docker Engine is not ready; wait for sandbox startup and retry")
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    lock_path = RUNTIME_ROOT / "launcher.lock"
    lock_file = lock_path.open("w")
    try:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        fail("another launcher is already running in this sandbox")

    mode = env("DAPR_KIT_MODE", "example")
    workspace = workspace_root()
    app_dir, app_command, resources = prepare_application(mode, workspace)
    result = compose(["up", "--detach", "--remove-orphans"])
    if result.returncode != 0:
        fail(f"could not start supporting services:\n{result.stdout}")
    wait_until("Redis service readiness", services_ready)

    sidecar: subprocess.Popen[bytes] | None = None
    shutdown_signum: int | None = None
    termination_sent = False

    def handle_signal(signum, _frame) -> None:
        nonlocal shutdown_signum, termination_sent
        if shutdown_signum is not None:
            return
        shutdown_signum = signum
        termination_sent = signal_process_group(sidecar, signal.SIGTERM)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    if shutdown_signum is not None:
        return 128 + shutdown_signum
    sidecar = start_sidecar(app_dir, app_command, resources)
    if shutdown_signum is not None and not termination_sent:
        termination_sent = signal_process_group(sidecar, signal.SIGTERM)
    cleanup_attempted = False
    try:
        wait_until(
            "Dapr sidecar and agent HTTP API readiness",
            lambda: shutdown_signum is not None or application_ready(sidecar),
        )
        if shutdown_signum is None:
            print(
                "dapr-agents ready: POST http://localhost:8001/agent/run and GET "
                "http://localhost:8001/agent/instances/<workflow-id> from `sbx exec`."
            )

        while True:
            try:
                exit_code = sidecar.wait(timeout=1)
                break
            except subprocess.TimeoutExpired:
                if shutdown_signum is not None:
                    cleanup_attempted = True
                    terminate_process_group(sidecar, term_sent=termination_sent)
                    return 128 + shutdown_signum

        if shutdown_signum is not None:
            return 128 + shutdown_signum
        if exit_code:
            print(
                f"dapr-agents: Dapr sidecar or application exited with status {exit_code}",
                file=sys.stderr,
            )
        return exit_code
    finally:
        if not cleanup_attempted:
            terminate_process_group(sidecar, term_sent=termination_sent)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KitError as exc:
        print(exc, file=sys.stderr)
        raise SystemExit(2)
