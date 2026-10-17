#!/usr/bin/env python3
"""Seed only missing global Pi model defaults without replacing operator pins."""

from __future__ import annotations

import errno
import json
import os
import signal
import stat
import sys
from typing import Any

DEFAULT_PROVIDER = "openai-codex"
DEFAULT_MODEL = "gpt-6.1-sol"
DEFAULT_THINKING = "high"
SETTINGS_NAME = "settings.json"
MAX_BYTES = 1_048_576

O_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)

agent_path = ""
agent_fd = -1


def fail(message: str, *, diagnostic: bool = False) -> None:
    stream = sys.stderr
    prefix = "pi-settings-config: "
    print(prefix + message, file=stream)
    if not diagnostic:
        raise SystemExit(1)


def test_hook(name: str) -> None:
    if os.environ.get("PI_SETTINGS_CONFIG_TEST_HOOK") == name:
        os.kill(os.getpid(), signal.SIGSTOP)


def same_identity(left: os.stat_result, right: os.stat_result) -> bool:
    return left.st_dev == right.st_dev and left.st_ino == right.st_ino


def same_metadata(left: os.stat_result, right: os.stat_result) -> bool:
    return (
        same_identity(left, right)
        and left.st_size == right.st_size
        and left.st_nlink == right.st_nlink
        and left.st_mtime_ns == right.st_mtime_ns
        and left.st_ctime_ns == right.st_ctime_ns
    )


def open_directory_at(parent: int, name: str, create: bool) -> int:
    flags = os.O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    try:
        return os.open(name, flags, dir_fd=parent)
    except OSError as exc:
        if not create or exc.errno != errno.ENOENT:
            raise
    try:
        os.mkdir(name, 0o700, dir_fd=parent)
    except OSError as exc:
        if exc.errno != errno.EEXIST:
            raise
    return os.open(name, flags, dir_fd=parent)


def open_directory_chain(path: str, create: bool) -> int:
    if not path.startswith("/") or path == "/":
        raise OSError(errno.EINVAL, "path must be an absolute directory")
    fd = os.open("/", os.O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    try:
        for part in path.split("/")[1:]:
            if part in ("", ".", ".."):
                raise OSError(errno.EINVAL, "invalid path component")
            next_fd = open_directory_at(fd, part, create)
            os.close(fd)
            fd = next_fd
        return fd
    except Exception:
        os.close(fd)
        raise


def verify_agent_directory() -> bool:
    try:
        current = open_directory_chain(agent_path, False)
    except OSError:
        return False
    try:
        return same_identity(os.fstat(agent_fd), os.fstat(current))
    finally:
        os.close(current)


def read_all(fd: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = os.read(fd, 65536)
        if not chunk:
            return b"".join(chunks)
        total += len(chunk)
        if total > MAX_BYTES:
            raise OSError(errno.EFBIG, f"{SETTINGS_NAME} exceeds the size limit")
        chunks.append(chunk)


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON setting: {key}")
        result[key] = value
    return result


def reject_constant(value: str) -> None:
    raise ValueError(f"invalid JSON constant: {value}")


def parse_settings(data: bytes) -> dict[str, Any]:
    try:
        parsed = json.loads(
            data.decode("utf-8-sig"),
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise ValueError(f"invalid Pi settings JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError("Pi settings root must be a JSON object")
    return parsed


def seed_defaults(settings: dict[str, Any]) -> tuple[bool, str]:
    has_provider = "defaultProvider" in settings
    has_model = "defaultModel" in settings
    has_thinking = "defaultThinkingLevel" in settings

    if not has_provider and not has_model:
        settings["defaultProvider"] = DEFAULT_PROVIDER
        settings["defaultModel"] = DEFAULT_MODEL
        if not has_thinking:
            settings["defaultThinkingLevel"] = DEFAULT_THINKING
        return True, "seeded missing model defaults"

    if has_provider != has_model:
        return False, (
            "partial default model route found; leaving settings unchanged. "
            "Set both defaultProvider and defaultModel, or remove both to use "
            "the fresh-home default."
        )

    if (
        settings["defaultProvider"] == DEFAULT_PROVIDER
        and settings["defaultModel"] == DEFAULT_MODEL
        and not has_thinking
    ):
        settings["defaultThinkingLevel"] = DEFAULT_THINKING
        return True, "seeded missing thinking default for the existing Sol route"

    return False, "preserved existing model and thinking selections"


def write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written == 0:
            raise OSError(errno.EIO, "short write")
        view = view[written:]


def open_temp() -> tuple[str, int]:
    for counter in range(100):
        name = f".pi-settings-config.{os.getpid()}.{counter}"
        try:
            fd = os.open(
                name,
                os.O_RDWR | os.O_CREAT | os.O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                0o600,
                dir_fd=agent_fd,
            )
            return name, fd
        except OSError as exc:
            if exc.errno != errno.EEXIST:
                raise
    raise OSError(errno.EEXIST, "could not allocate a temporary settings file")


def publish(
    content: bytes,
    mode: int,
    replacing: bool,
    expected: os.stat_result | None,
) -> None:
    name, fd = open_temp()
    try:
        write_all(fd, content)
        os.fchmod(fd, mode)
        os.fsync(fd)
        temporary = os.fstat(fd)
        if not stat.S_ISREG(temporary.st_mode) or temporary.st_nlink != 1:
            raise OSError(errno.EINVAL, "temporary settings file is not private")
        if not verify_agent_directory():
            raise OSError(errno.ESTALE, "Pi agent directory changed during activation")
        test_hook("before-replace" if replacing else "before-publish")
        if replacing:
            if expected is None:
                raise OSError(errno.EINVAL, "missing expected settings metadata")
            current = os.stat(SETTINGS_NAME, dir_fd=agent_fd, follow_symlinks=False)
            if not stat.S_ISREG(current.st_mode) or not same_metadata(expected, current):
                raise OSError(errno.ESTALE, "settings changed during publication")
            os.rename(name, SETTINGS_NAME, src_dir_fd=agent_fd, dst_dir_fd=agent_fd)
        else:
            os.link(
                name,
                SETTINGS_NAME,
                src_dir_fd=agent_fd,
                dst_dir_fd=agent_fd,
                follow_symlinks=False,
            )
            os.unlink(name, dir_fd=agent_fd)

        published = os.fstat(fd)
        current = os.stat(SETTINGS_NAME, dir_fd=agent_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(published.st_mode)
            or published.st_nlink != 1
            or not stat.S_ISREG(current.st_mode)
            or current.st_nlink != 1
            or not same_identity(published, current)
            or not verify_agent_directory()
        ):
            raise OSError(errno.ESTALE, "settings changed during publication")
    except Exception:
        try:
            os.unlink(name, dir_fd=agent_fd)
        except OSError:
            pass
        os.close(fd)
        raise
    os.close(fd)


def materialize() -> int:
    if not verify_agent_directory():
        fail("canonical Pi agent directory changed during activation")
    try:
        existing = os.stat(SETTINGS_NAME, dir_fd=agent_fd, follow_symlinks=False)
    except OSError as exc:
        if exc.errno != errno.ENOENT:
            fail("could not inspect settings.json")
        existing = None

    if existing is not None and not stat.S_ISREG(existing.st_mode):
        fail("refusing symlink or non-regular settings.json")
    if existing is not None and existing.st_nlink != 1:
        fail("refusing hard-linked settings.json")

    if existing is None:
        settings: dict[str, Any] = {}
        changed, message = seed_defaults(settings)
        content = (json.dumps(settings, ensure_ascii=True, indent=2) + "\n").encode(
            "utf-8"
        )
        try:
            publish(content, 0o600, replacing=False, expected=None)
        except OSError as exc:
            if exc.errno == errno.EEXIST:
                fail("settings.json appeared during publication and was preserved")
            fail("could not publish fresh settings.json")
        print(f"pi-settings-config: {message}: {agent_path}/{SETTINGS_NAME}")
        return 0

    try:
        fd = os.open(
            SETTINGS_NAME,
            os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC,
            dir_fd=agent_fd,
        )
    except OSError:
        fail("could not open existing regular settings.json")
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            fail("invalid existing regular settings.json")
        try:
            data = read_all(fd)
        except OSError:
            fail("could not read settings.json")
        after = os.fstat(fd)
        try:
            current = os.stat(SETTINGS_NAME, dir_fd=agent_fd, follow_symlinks=False)
        except OSError:
            fail("settings.json changed during inspection")
        if (
            not same_metadata(before, after)
            or not same_metadata(after, current)
            or not verify_agent_directory()
        ):
            fail("settings.json changed during inspection")
        try:
            settings = parse_settings(data)
        except ValueError as exc:
            fail(str(exc))
        changed, message = seed_defaults(settings)
        if not changed:
            fail(message, diagnostic=True)
            return 0
        content = (json.dumps(settings, ensure_ascii=True, indent=2) + "\n").encode(
            "utf-8"
        )
        try:
            publish(content, stat.S_IMODE(before.st_mode), replacing=True, expected=after)
        except OSError:
            fail("could not publish settings.json without overwriting a concurrent change")
        print(f"pi-settings-config: {message}: {agent_path}/{SETTINGS_NAME}")
        return 0
    finally:
        os.close(fd)


def main(argv: list[str]) -> int:
    global agent_path, agent_fd
    if len(argv) != 2:
        print(f"usage: {argv[0]} <canonical-pi-agent-directory>", file=sys.stderr)
        return 2
    agent_path = argv[1]
    try:
        agent_fd = open_directory_chain(agent_path, True)
    except OSError:
        fail("canonical Pi agent directory is not a stable regular directory")
    try:
        test_hook("after-agent-open")
        return materialize()
    except SystemExit as exc:
        return int(exc.code)
    except OSError as exc:
        fail(f"activation failed safely: {exc}")
    finally:
        os.close(agent_fd)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
