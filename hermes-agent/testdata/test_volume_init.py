import os
from pathlib import Path
import shutil
import subprocess
import unittest


SCRIPT = "/kit/hermes-volume-init.py"
CREDENTIAL_HOOK = "/kit/files/home/.local/bin/hermes-credential-auth.sh"
STATE = Path("/home/agent/.hermes/profiles/persistent")
SEED = Path("/home/agent/.hermes")
SEEDS = {"config.yaml": ("model: image\n", 0o644), ".env": ("# template\n", 0o600)}


class VolumeInitTest(unittest.TestCase):
    def setUp(self):
        # This suite runs only in a disposable container with a private tmpfs at STATE.
        self.assertTrue(STATE.is_mount())
        self.assertTrue(Path("/.dockerenv").exists())
        self.assertTrue(any(line.split()[1:3] == [str(STATE), "tmpfs"]
                            for line in Path("/proc/mounts").read_text().splitlines()))
        os.chown(STATE, 0, 0)
        os.chmod(STATE, 0o755)
        for entry in STATE.iterdir():
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry)
            else:
                entry.unlink()
        for name, (content, mode) in SEEDS.items():
            (SEED / name).write_text(content)
            os.chmod(SEED / name, mode)
            os.chown(SEED / name, 1000, 1000)

    def run_hook(self, enabled="1", home=str(STATE), user=0):
        return subprocess.run(
            ["python3", SCRIPT],
            env={**os.environ, "HERMES_INIT_VOLUME": enabled, "HERMES_HOME": home},
            capture_output=True, text=True, user=user, group=user, extra_groups=[],
        )

    def run_startup(self, anthropic_mode, home=str(STATE)):
        # The kit's startup order: the root hook, then the credential hook as the agent.
        self.assertEqual(self.run_hook().returncode, 0)
        os.chown("/home/agent", 1000, 1000)
        env = {**os.environ, "HOME": "/home/agent", "HERMES_HOME": home,
               "ANTHROPIC_API_KEY": "proxy-managed", "OPENROUTER_API_KEY": "proxy-managed",
               "SBX_CRED_ANTHROPIC_MODE": anthropic_mode}
        return subprocess.run(["sh", CREDENTIAL_HOOK], env=env, capture_output=True, text=True,
                              user=1000, group=1000, extra_groups=[])

    def test_startup_keeps_bound_placeholders_in_profile_env(self):
        # OPENROUTER_API_KEY carries the sentinel in every row but is never bound, so it never lands.
        rows = [
            ("bound placeholder lands once", "", "apikey", ["ANTHROPIC_API_KEY=proxy-managed"]),
            ("unbound adds nothing", "", "none", []),
            ("unbound removes the placeholder", "ANTHROPIC_API_KEY=proxy-managed\n", "none", []),
            ("user value is kept", "ANTHROPIC_API_KEY=sk-ant-mine\n", "apikey", ["ANTHROPIC_API_KEY=sk-ant-mine"]),
            ("exported user value is kept", "export ANTHROPIC_API_KEY=sk-ant-mine\n", "apikey",
             ["export ANTHROPIC_API_KEY=sk-ant-mine"]),
            ("spaced user value is kept", "ANTHROPIC_API_KEY = sk-ant-mine\n", "apikey",
             ["ANTHROPIC_API_KEY = sk-ant-mine"]),
            ("missing final newline stays a separate line", "FOO=bar", "apikey",
             ["FOO=bar", "ANTHROPIC_API_KEY=proxy-managed"]),
            ("commented-out value still gets the placeholder", "# ANTHROPIC_API_KEY=sk-ant-old\n", "apikey",
             ["ANTHROPIC_API_KEY=proxy-managed"]),
        ]
        env_file = STATE / ".env"
        for name, existing, mode, expected in rows:
            with self.subTest(name):
                self.assertEqual(self.run_hook().returncode, 0)
                env_file.write_text(SEEDS[".env"][0] + existing)
                os.chown(env_file, 1000, 1000)
                os.chmod(env_file, 0o600)
                for _ in range(2):
                    result = self.run_startup(mode)
                    self.assertEqual(result.returncode, 0, result.stderr)
                lines = env_file.read_text().splitlines()
                self.assertEqual([line for line in lines if not line.startswith("#")], expected)
                self.assertEqual(env_file.stat().st_mode & 0o777, 0o600)

    def test_default_home_env_is_not_written(self):
        os.chown(SEED, 1000, 1000)
        for home in (str(SEED), f"{SEED}/"):
            with self.subTest(home=home):
                result = self.run_startup("apikey", home=home)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((SEED / ".env").read_text(), SEEDS[".env"][0])

    def test_fresh_volume_becomes_writable(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((STATE.stat().st_uid, STATE.stat().st_gid), (1000, 1000))
        self.assertEqual(STATE.stat().st_mode & 0o777, 0o700)
        subprocess.run(["sh", "-c", f"echo state > {STATE}/state"],
                       user=1000, group=1000, extra_groups=[], check=True)

    def test_fresh_volume_gets_image_config(self):
        self.assertEqual(self.run_hook().returncode, 0)
        for name, (content, mode) in SEEDS.items():
            with self.subTest(name=name):
                seeded = (STATE / name).stat()
                self.assertEqual((STATE / name).read_text(), content)
                self.assertEqual((seeded.st_uid, seeded.st_mode & 0o777), (1000, mode))
        self.assertEqual(sorted(p.name for p in STATE.iterdir()), sorted(SEEDS))

    def test_seeding_keeps_volume_config(self):
        self.assertEqual(self.run_hook().returncode, 0)
        (STATE / "config.yaml").write_text("model: mine\n")
        (STATE / ".env").unlink()
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertEqual((STATE / "config.yaml").read_text(), "model: mine\n")
        self.assertEqual((STATE / ".env").read_text(), SEEDS[".env"][0])

    def test_seeding_finishes_interrupted_initialization(self):
        os.chown(STATE, 1000, 1000)
        os.chmod(STATE, 0o700)
        partial = STATE / ".config.yaml.seeding"
        partial.write_text("model: half")
        os.chown(partial, 1000, 1000)
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertEqual((STATE / "config.yaml").read_text(), SEEDS["config.yaml"][0])
        self.assertFalse(partial.exists())

    def test_seeding_does_not_write_through_a_linked_temporary_name(self):
        os.chown(STATE, 1000, 1000)
        os.chmod(STATE, 0o700)
        (STATE / "state").write_text("keep")
        os.chown(STATE / "state", 1000, 1000)
        (STATE / ".config.yaml.seeding").symlink_to(STATE / "state")
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertEqual((STATE / "state").read_text(), "keep")
        self.assertEqual((STATE / "config.yaml").read_text(), SEEDS["config.yaml"][0])

    def test_missing_image_config_is_skipped(self):
        for name in SEEDS:
            (SEED / name).unlink()
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(list(STATE.iterdir()), [])

    def test_disabled_does_not_change_ownership(self):
        for enabled in ("", "0"):
            with self.subTest(enabled=enabled):
                result = self.run_hook(enabled=enabled, home="/tmp", user=1000)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(STATE.stat().st_uid, 0)
                self.assertEqual(STATE.stat().st_mode & 0o777, 0o755)

    def test_enabled_hook_requires_root(self):
        result = self.run_hook(user=1000)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must run as root", result.stderr)
        self.assertEqual(STATE.stat().st_uid, 0)

    def test_refuses_wrong_home_and_invalid_opt_in(self):
        for enabled, home in [("1", "/tmp"), ("1", str(SEED)), ("true", str(STATE))]:
            with self.subTest(enabled=enabled, home=home):
                self.assertNotEqual(self.run_hook(enabled, home).returncode, 0)
                self.assertEqual(STATE.stat().st_uid, 0)

    def test_refuses_existing_root_owned_content(self):
        (STATE / "state").write_text("keep")
        self.assertNotEqual(self.run_hook().returncode, 0)
        self.assertEqual(STATE.stat().st_uid, 0)
        self.assertEqual((STATE / "state").read_text(), "keep")

    def test_lost_found_is_not_changed(self):
        recovery = STATE / "lost+found"
        recovery.mkdir(mode=0o700)
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(recovery.stat().st_uid, 0)
        self.assertEqual(recovery.stat().st_mode & 0o777, 0o700)

    def test_refuses_incompatible_recovery_owner(self):
        recovery = STATE / "lost+found"
        recovery.mkdir()
        os.chown(recovery, 1000, 1000)
        result = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(STATE.stat().st_uid, 0)
        self.assertEqual(recovery.stat().st_uid, 1000)

    def test_refuses_nonempty_or_symlink_recovery_directory(self):
        recovery = STATE / "lost+found"
        recovery.mkdir()
        (recovery / "recovered").write_text("keep")
        self.assertNotEqual(self.run_hook().returncode, 0)
        shutil.rmtree(recovery)
        recovery.symlink_to("/tmp", target_is_directory=True)
        self.assertNotEqual(self.run_hook().returncode, 0)
        self.assertEqual(STATE.stat().st_uid, 0)

    def test_retries_preserve_existing_content_and_children(self):
        self.assertEqual(self.run_hook().returncode, 0)
        (STATE / "state").write_text("keep")
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((STATE / "state").read_text(), "keep")
        self.assertEqual((STATE / "state").stat().st_uid, 0)

    def test_retry_after_private_mode_before_ownership_transfer(self):
        os.chmod(STATE, 0o700)
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(STATE.stat().st_uid, 1000)

    def test_incompatible_owner_is_not_repaired(self):
        for owner in ((2000, 2000), (1000, 0), (0, 1000)):
            with self.subTest(owner=owner):
                os.chown(STATE, *owner)
                self.assertNotEqual(self.run_hook().returncode, 0)
                self.assertEqual((STATE.stat().st_uid, STATE.stat().st_gid), owner)

    def test_owned_but_unwritable_volume_is_not_repaired(self):
        os.chown(STATE, 1000, 1000)
        os.chmod(STATE, 0o500)
        self.assertNotEqual(self.run_hook().returncode, 0)
        self.assertEqual(STATE.stat().st_mode & 0o777, 0o500)

    def test_duplicate_initialization(self):
        self.initialize_concurrently()
        self.assertEqual(STATE.stat().st_uid, 1000)

    def initialize_concurrently(self):
        children = [subprocess.Popen(
            ["python3", SCRIPT],
            env={**os.environ, "HERMES_INIT_VOLUME": "1", "HERMES_HOME": str(STATE)},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ) for _ in range(8)]
        for child in children:
            _, errors = child.communicate(timeout=10)
            self.assertEqual(child.returncode, 0, errors)

    def test_concurrent_retries_preserve_agent_state(self):
        self.assertEqual(self.run_hook().returncode, 0)
        state = STATE / "state"
        subprocess.run(["sh", "-c", f"echo state > {state}"],
                       user=1000, group=1000, extra_groups=[], check=True)
        before = state.stat()
        self.initialize_concurrently()
        self.assertEqual(state.read_text(), "state\n")
        self.assertEqual(state.stat().st_uid, 1000)
        self.assertEqual(state.stat().st_ino, before.st_ino)


if __name__ == "__main__":
    unittest.main()
