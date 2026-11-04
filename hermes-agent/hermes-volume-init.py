#!/usr/bin/env python3
import contextlib
import fcntl
import os
import shutil
import sys

# Under ~/.hermes so Hermes keeps its install root there; a home outside it becomes its own root.
STATE_DIR = "/home/agent/.hermes/profiles/persistent"
SEED_SOURCE = "/home/agent/.hermes"
SEED_FILES = ("config.yaml", ".env")
FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW


def open_state_dir():
    # Opens one component at a time with O_NOFOLLOW, since the agent owns the path's ancestors.
    *ancestors, leaf = STATE_DIR.strip("/").split("/")
    parent = os.open("/", FLAGS)
    try:
        for name in ancestors:
            child = os.open(name, FLAGS, dir_fd=parent)
            os.close(parent)
            parent = child
        fd = os.open(leaf, FLAGS, dir_fd=parent)
        if os.fstat(fd).st_dev == os.fstat(parent).st_dev:
            os.close(fd)
            raise RuntimeError(f"{STATE_DIR} must be a separately mounted filesystem")
        return fd
    finally:
        os.close(parent)


def seed_missing_files():
    # Copies through a temporary name so an interrupted copy is redone, never kept half-written.
    for name in SEED_FILES:
        source = os.path.join(SEED_SOURCE, name)
        if os.path.lexists(name) or not os.path.isfile(source):
            continue
        partial = f".{name}.seeding"
        # Exclusive create, so a leftover link at the temporary name is replaced, never written through.
        with contextlib.suppress(FileNotFoundError):
            os.unlink(partial)
        with open(source, "rb") as src, open(partial, "xb") as dst:
            shutil.copyfileobj(src, dst)
        shutil.copystat(source, partial)
        try:
            os.link(partial, name)
        except FileExistsError:
            pass
        os.unlink(partial)


def initialize():
    enabled = os.environ.get("HERMES_INIT_VOLUME", "")
    if enabled in ("", "0"):
        return
    if enabled != "1" or os.environ.get("HERMES_HOME") != STATE_DIR:
        raise RuntimeError(f"volume initialization requires HERMES_INIT_VOLUME=1 and HERMES_HOME={STATE_DIR}")
    if os.geteuid() != 0:
        raise RuntimeError("volume initialization must run as root")

    fd = open_state_dir()
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        current = os.fstat(fd)
        owner = (current.st_uid, current.st_gid)
        if owner == (0, 0):
            entries = os.listdir(fd)
            if entries == ["lost+found"]:
                recovery = os.open("lost+found", FLAGS, dir_fd=fd)
                try:
                    info = os.fstat(recovery)
                    if (info.st_uid, info.st_gid) != (0, 0) or os.listdir(recovery):
                        raise RuntimeError("refusing incompatible lost+found")
                finally:
                    os.close(recovery)
            elif entries:
                raise RuntimeError("refusing to initialize a nonempty root-owned volume")
            # Transfer ownership last so a retry can finish interrupted initialization.
            os.fchmod(fd, 0o700)
            os.fchown(fd, 1000, 1000)
        elif owner != (1000, 1000):
            raise RuntimeError("refusing to change an existing volume's owner")

        os.fchdir(fd)
        os.setgroups([])
        os.setgid(1000)
        os.setuid(1000)
        if not os.access(".", os.W_OK | os.X_OK):
            raise RuntimeError(f"{STATE_DIR} is not writable by UID 1000")
        seed_missing_files()
    finally:
        os.close(fd)


if __name__ == "__main__":
    try:
        initialize()
    except (OSError, RuntimeError) as error:
        sys.exit(f"Hermes volume initialization failed: {error}")
