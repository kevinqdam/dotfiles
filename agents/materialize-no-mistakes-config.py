#!/usr/bin/env python3
"""Converge no-mistakes pipeline-agent routing without replacing live YAML."""

from __future__ import annotations

import errno
import os
import re
import signal
import stat
import sys

APPROVED_AGENT = "pi"
APPROVED_PI_ARGS = ("--model", "xai/grok-4.6", "--thinking", "high")
CONFIG_NAME = "config.yaml"
MAX_BYTES = 1_048_576
STUB = """\
# Pipeline execution matches Firstmate: Pi + Grok (test/lint/push/PR).
# High-reasoning review is a separate Firstmate Astra pass, not this file.
agent: pi
agent_args_override:
  pi:
    - --model
    - xai/grok-4.6
    - --thinking
    - high
"""

KEY_RE = re.compile(
    r"^(?P<key>[A-Za-z_][A-Za-z0-9_-]*)[ \t]*:"
    r"(?:[ \t]+(?P<value>\S.*?))?[ \t]*$"
)

O_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
O_DIRECTORY = getattr(os, "O_DIRECTORY", 0)
O_NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)

home_path = ""
home_fd = -1


def fail(message: str, name: str | None = CONFIG_NAME) -> None:
    if name is None:
        suffix = home_path
    else:
        suffix = f"{home_path}/{name}"
    print(f"no-mistakes-config: {message}: {suffix}", file=sys.stderr)


def test_hook(name: str) -> None:
    selected = os.environ.get("NO_MISTAKES_CONFIG_TEST_HOOK")
    if selected is not None and selected == name:
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


def verify_home() -> bool:
    try:
        current = open_directory_chain(home_path, False)
    except OSError:
        return False
    try:
        return same_identity(os.fstat(home_fd), os.fstat(current))
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
            raise OSError(errno.EFBIG, "config.yaml exceeds the size limit")
        chunks.append(chunk)


def write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        if written == 0:
            raise OSError(errno.EIO, "short write")
        view = view[written:]


def content_indent(line: str) -> int | None:
    if line.startswith("\t"):
        return None
    stripped = line.lstrip(" ")
    if stripped == "" or stripped.startswith("#"):
        return None
    return len(line) - len(stripped)


def parse_key_line(line: str, indent: int) -> tuple[str, str | None] | None:
    match = KEY_RE.match(line[indent:])
    if match is None:
        return None
    return match.group("key"), match.group("value")


def strip_inline_comment(value: str) -> str:
    if value.startswith(("'", '"')):
        return value
    if " #" in value:
        return value.split(" #", 1)[0].rstrip()
    return value


def unquote(value: str) -> str:
    value = strip_inline_comment(value).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def find_key(
    lines: list[str], key: str, key_indent: int, start: int, limit: int
) -> tuple[int, str | None] | None:
    index = start
    while index < limit:
        indent = content_indent(lines[index])
        if indent is None:
            index += 1
            continue
        if indent < key_indent:
            return None
        if indent == key_indent:
            parsed = parse_key_line(lines[index], indent)
            if parsed is not None and parsed[0] == key:
                return index, parsed[1]
        index += 1
    return None


def node_end(
    lines: list[str], start: int, key_indent: int, limit: int, same_line_value: str | None
) -> int:
    if same_line_value is not None:
        return start + 1
    last = start
    index = start + 1
    while index < limit:
        indent = content_indent(lines[index])
        if indent is None:
            index += 1
            continue
        if indent <= key_indent:
            break
        last = index
        index += 1
    return last + 1


def first_content_indent(lines: list[str], start: int, limit: int) -> int | None:
    for index in range(start, limit):
        indent = content_indent(lines[index])
        if indent is not None:
            return indent
    return None


def read_sequence(lines: list[str], start: int, end: int, parent_indent: int) -> tuple[str, ...]:
    items: list[str] = []
    for index in range(start + 1, end):
        indent = content_indent(lines[index])
        if indent is None or indent <= parent_indent:
            continue
        body = lines[index][indent:]
        if not body.startswith("-"):
            continue
        item = body[1:].strip()
        items.append(unquote(item) if item else "")
    return tuple(items)


def root_is_sequence(lines: list[str]) -> bool:
    for line in lines:
        indent = content_indent(line)
        if indent is None:
            continue
        return indent == 0 and line.lstrip(" ").startswith("-")
    return False


def has_tab_structure(lines: list[str]) -> bool:
    for line in lines:
        stripped = line.lstrip(" ")
        if stripped == "" or stripped.startswith("#"):
            continue
        if line.startswith("\t") or stripped != line.lstrip(" \t"):
            return True
    return False


def current_agent(lines: list[str]) -> str | None:
    found = find_key(lines, "agent", 0, 0, len(lines))
    if found is None:
        return None
    _, value = found
    if value is None:
        return None
    scalar = unquote(value)
    if scalar.startswith("["):
        return None
    return scalar


def current_pi_args(lines: list[str]) -> tuple[str, ...] | None:
    found = find_key(lines, "agent_args_override", 0, 0, len(lines))
    if found is None:
        return None
    index, value = found
    if value is not None:
        return None
    end = node_end(lines, index, 0, len(lines), value)
    child_indent = first_content_indent(lines, index + 1, end)
    if child_indent is None:
        return None
    child = find_key(lines, "pi", child_indent, index + 1, end)
    if child is None:
        return None
    child_index, child_value = child
    if child_value is not None:
        return None
    child_end = node_end(lines, child_index, child_indent, end, child_value)
    return read_sequence(lines, child_index, child_end, child_indent)


def pi_block(indent: int) -> list[str]:
    inner = indent + 2
    pad = " " * indent
    nested = " " * inner
    return [f"{pad}pi:"] + [f"{nested}- {item}" for item in APPROVED_PI_ARGS]


def insert_index_for_agent(lines: list[str]) -> int:
    index = 0
    saw_document = False
    while index < len(lines):
        stripped = lines[index].strip()
        if stripped == "" or stripped.startswith("#"):
            index += 1
            continue
        if stripped == "---" and not saw_document:
            saw_document = True
            index += 1
            continue
        return index
    return len(lines)


def ensure_agent(lines: list[str]) -> bool:
    found = find_key(lines, "agent", 0, 0, len(lines))
    if found is None:
        index = insert_index_for_agent(lines)
        lines[index:index] = [f"agent: {APPROVED_AGENT}"]
        return True
    index, value = found
    end = node_end(lines, index, 0, len(lines), value)
    if current_agent(lines) == APPROVED_AGENT and end == index + 1:
        return False
    lines[index:end] = [f"agent: {APPROVED_AGENT}"]
    return True


def ensure_pi_args(lines: list[str]) -> bool:
    found = find_key(lines, "agent_args_override", 0, 0, len(lines))
    if found is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.append("agent_args_override:")
        lines.extend(pi_block(2))
        return True
    index, value = found
    end = node_end(lines, index, 0, len(lines), value)
    if value is not None:
        lines[index:end] = ["agent_args_override:"] + pi_block(2)
        return True
    child_indent = first_content_indent(lines, index + 1, end)
    if child_indent is None:
        lines[index + 1:index + 1] = pi_block(2)
        return True
    child = find_key(lines, "pi", child_indent, index + 1, end)
    if child is None:
        lines[index + 1:index + 1] = pi_block(child_indent)
        return True
    child_index, child_value = child
    child_end = node_end(lines, child_index, child_indent, end, child_value)
    if child_value is None and current_pi_args(lines) == APPROVED_PI_ARGS:
        return False
    lines[child_index:child_end] = pi_block(child_indent)
    return True


def converge(text: str) -> str | None:
    if text.strip() == "":
        return STUB
    body = text[:-1] if text.endswith("\n") else text
    lines = body.split("\n")
    if has_tab_structure(lines):
        raise ValueError("tab indentation is not supported")
    if root_is_sequence(lines):
        raise ValueError("root document is a sequence")
    changed = ensure_agent(lines)
    changed = ensure_pi_args(lines) or changed
    if not changed:
        return None
    return "\n".join(lines) + "\n"


def inspect_target() -> os.stat_result | None:
    try:
        current = os.stat(CONFIG_NAME, dir_fd=home_fd, follow_symlinks=False)
    except OSError as exc:
        if exc.errno == errno.ENOENT:
            return None
        fail("could not inspect target")
        raise
    if not stat.S_ISREG(current.st_mode):
        fail("refusing symlink or non-regular target")
        raise OSError(errno.ELOOP if stat.S_ISLNK(current.st_mode) else errno.EINVAL)
    return current


def open_temp() -> tuple[str, int]:
    counter = 0
    while counter < 100:
        name = f".no-mistakes-config.{os.getpid()}.{counter}"
        counter += 1
        try:
            fd = os.open(
                name,
                os.O_RDWR | os.O_CREAT | os.O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                0o600,
                dir_fd=home_fd,
            )
            return name, fd
        except OSError as exc:
            if exc.errno != errno.EEXIST:
                raise
    raise OSError(errno.EEXIST, "could not allocate a temporary file")


def publish(
    content: bytes,
    mode: int,
    replacing: bool,
    expected: os.stat_result | None = None,
) -> None:
    name, fd = open_temp()
    try:
        write_all(fd, content)
        os.fchmod(fd, mode)
        os.fsync(fd)
        temporary = os.fstat(fd)
        if not stat.S_ISREG(temporary.st_mode) or temporary.st_nlink != 1:
            raise OSError(errno.EINVAL, "temporary file is not a private regular file")
        if not verify_home():
            raise OSError(errno.ESTALE, "canonical directory changed during activation")
        hook = "before-replace" if replacing else "before-publish"
        test_hook(hook)
        if replacing:
            if expected is None:
                raise OSError(errno.EINVAL, "missing expected target metadata")
            current = os.stat(CONFIG_NAME, dir_fd=home_fd, follow_symlinks=False)
            if not stat.S_ISREG(current.st_mode) or not same_metadata(expected, current):
                raise OSError(errno.ESTALE, "target changed during publication")
            os.rename(name, CONFIG_NAME, src_dir_fd=home_fd, dst_dir_fd=home_fd)
        else:
            os.link(
                name,
                CONFIG_NAME,
                src_dir_fd=home_fd,
                dst_dir_fd=home_fd,
                follow_symlinks=False,
            )
            os.unlink(name, dir_fd=home_fd)
        published = os.fstat(fd)
        current = os.stat(CONFIG_NAME, dir_fd=home_fd, follow_symlinks=False)
        if (
            not stat.S_ISREG(published.st_mode)
            or published.st_nlink != 1
            or not stat.S_ISREG(current.st_mode)
            or current.st_nlink != 1
            or not same_identity(published, current)
            or not verify_home()
        ):
            raise OSError(errno.ESTALE, "target changed during publication")
    except Exception:
        try:
            os.unlink(name, dir_fd=home_fd)
        except OSError:
            pass
        os.close(fd)
        raise
    os.close(fd)


def materialize() -> int:
    if not verify_home():
        fail("canonical directory changed during activation", None)
        return 1
    try:
        existing = inspect_target()
    except OSError:
        return 1
    if existing is None:
        try:
            publish(STUB.encode("utf-8"), 0o600, replacing=False, expected=None)
        except OSError as exc:
            if exc.errno == errno.EEXIST:
                fail("target appeared during publication and was preserved")
            else:
                fail("could not publish target")
            return 1
        print(f"no-mistakes-config: created {home_path}/{CONFIG_NAME}")
        return 0
    if existing.st_nlink != 1:
        fail("refusing hard-linked target")
        return 1
    try:
        fd = os.open(CONFIG_NAME, os.O_RDONLY | O_NOFOLLOW | O_CLOEXEC, dir_fd=home_fd)
    except OSError:
        fail("could not open existing regular target")
        return 1
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            fail("invalid existing regular target")
            return 1
        try:
            data = read_all(fd)
        except OSError:
            fail("could not read existing regular target")
            return 1
        after = os.fstat(fd)
        current = os.stat(CONFIG_NAME, dir_fd=home_fd, follow_symlinks=False)
        if (
            not same_metadata(before, after)
            or not same_metadata(after, current)
            or not verify_home()
        ):
            fail("target changed during preservation")
            return 1
        try:
            text = data.decode("utf-8")
            if text.startswith("\ufeff"):
                text = text[1:]
            updated = converge(text)
        except (UnicodeDecodeError, ValueError) as exc:
            fail(str(exc) if str(exc) else "invalid YAML document")
            return 1
        if updated is None:
            print(f"no-mistakes-config: unchanged {home_path}/{CONFIG_NAME}")
            return 0
        test_hook("before-replace-boundary")
        current = os.stat(CONFIG_NAME, dir_fd=home_fd, follow_symlinks=False)
        if not same_metadata(after, current) or not verify_home():
            fail("target changed during preservation")
            return 1
        try:
            publish(
                updated.encode("utf-8"),
                stat.S_IMODE(before.st_mode),
                replacing=True,
                expected=after,
            )
        except OSError:
            fail("could not publish target")
            return 1
        print(f"no-mistakes-config: patched {home_path}/{CONFIG_NAME}")
        return 0
    finally:
        os.close(fd)


def main(argv: list[str]) -> int:
    global home_path, home_fd
    if len(argv) != 2:
        print(f"usage: {argv[0]} <canonical-no-mistakes-home>", file=sys.stderr)
        return 2
    home_path = argv[1]
    try:
        home_fd = open_directory_chain(home_path, True)
    except OSError:
        fail("canonical home is not a stable regular directory", None)
        return 1
    try:
        test_hook("after-home-open")
        return materialize()
    finally:
        os.close(home_fd)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
