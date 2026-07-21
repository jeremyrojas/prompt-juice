#!/usr/bin/env python3
"""Capture approved Claude Code read-only outputs into a private directory."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import pty
import select
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

from sanitize_capture import SanitizationError, sanitize_file


RAW_NAMES = ("version.raw", "auth-status.raw", "usage.raw")
SANITIZED_NAMES = ("version.txt", "auth-status.json", "usage.ans")
USAGE_COMMAND_BYTES = b"/usage\r"
USAGE_BASE_ARGUMENTS = (
    "--safe-mode",
    "--ax-screen-reader",
    "--allowed-tools",
    "",
)


class CaptureError(RuntimeError):
    """A safe, user-presentable capture failure."""


def _mkdir_private(path: Path) -> None:
    path.mkdir(mode=0o700, parents=False, exist_ok=False)
    path.chmod(0o700)


def _open_private(path: Path):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    os.fchmod(descriptor, 0o600)
    return os.fdopen(descriptor, "wb")


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=2)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=2)


def _run_noninteractive(
    executable: Path,
    arguments: list[str],
    working_directory: Path,
    raw_path: Path,
    timeout: float = 30,
) -> int:
    with _open_private(raw_path) as raw:
        process = subprocess.Popen(
            [str(executable), *arguments],
            cwd=working_directory,
            stdin=subprocess.DEVNULL,
            stdout=raw,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired as error:
            _terminate_process_group(process)
            raise CaptureError("an approved noninteractive capture timed out") from error


def _set_terminal_size(descriptor: int, rows: int = 40, columns: int = 120) -> None:
    fcntl.ioctl(descriptor, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))


def _capture_usage(
    executable: Path,
    working_directory: Path,
    raw_path: Path,
    startup_delay: float = 8,
    capture_duration: float = 20,
    hard_timeout: float = 45,
    bypass_project_trust: bool = False,
) -> int:
    master, slave = pty.openpty()
    _set_terminal_size(slave)
    writes: list[bytes] = []
    with _open_private(raw_path) as raw:
        arguments = [*USAGE_BASE_ARGUMENTS]
        if bypass_project_trust:
            arguments.append("--dangerously-skip-permissions")
        process = subprocess.Popen(
            [str(executable), *arguments],
            cwd=working_directory,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            start_new_session=True,
            close_fds=True,
        )
        os.close(slave)
        started_at = time.monotonic()
        sent_at: float | None = None
        try:
            while True:
                now = time.monotonic()
                if sent_at is None and now - started_at >= startup_delay:
                    os.write(master, USAGE_COMMAND_BYTES)
                    writes.append(USAGE_COMMAND_BYTES)
                    sent_at = now

                readable, _, _ = select.select([master], [], [], 0.2)
                if readable:
                    try:
                        chunk = os.read(master, 65_536)
                    except OSError:
                        chunk = b""
                    if chunk:
                        raw.write(chunk)
                        raw.flush()

                if process.poll() is not None:
                    break
                if sent_at is not None and now - sent_at >= capture_duration:
                    break
                if now - started_at >= hard_timeout:
                    raise CaptureError("the approved /usage capture timed out")
        finally:
            _terminate_process_group(process)
            try:
                while True:
                    chunk = os.read(master, 65_536)
                    if not chunk:
                        break
                    raw.write(chunk)
            except OSError:
                pass
            os.close(master)

    if writes != [USAGE_COMMAND_BYTES]:
        raise CaptureError("the PTY command allowlist invariant failed")
    return process.returncode if process.returncode is not None else -signal.SIGTERM


def _validate_permissions(
    root: Path,
    raw_directory: Path,
    controlled_directory: Path,
    raw_names: tuple[str, ...],
) -> None:
    for directory in (root, raw_directory, controlled_directory, root / "sanitized"):
        if stat.S_IMODE(directory.stat().st_mode) != 0o700:
            raise CaptureError("a private capture directory does not have mode 0700")
    for name in raw_names:
        if stat.S_IMODE((raw_directory / name).stat().st_mode) != 0o600:
            raise CaptureError("a raw capture file does not have mode 0600")


def _write_metadata(path: Path, payload: dict[str, object]) -> None:
    with _open_private(path) as output:
        output.write(json.dumps(payload, indent=2, sort_keys=True).encode("utf-8"))
        output.write(b"\n")


def _create_private_capture_directories(
    scratch_parent: Path | None,
) -> tuple[Path, Path, Path, Path]:
    parent = str(scratch_parent) if scratch_parent is not None else None
    scratch = Path(tempfile.mkdtemp(prefix="promptjuice-claude-usage-", dir=parent))
    scratch.chmod(0o700)
    raw_directory = scratch / "raw"
    sanitized_directory = scratch / "sanitized"
    controlled_directory = scratch / "controlled-workdir"
    _mkdir_private(raw_directory)
    _mkdir_private(sanitized_directory)
    _mkdir_private(controlled_directory)
    return scratch, raw_directory, sanitized_directory, controlled_directory


def run_capture(
    executable: Path,
    scratch_parent: Path | None = None,
    startup_delay: float = 8,
    capture_duration: float = 20,
) -> dict[str, object]:
    if not executable.is_absolute() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise CaptureError("the Claude executable could not be resolved safely")

    scratch, raw_directory, sanitized_directory, controlled_directory = (
        _create_private_capture_directories(scratch_parent)
    )

    version_exit = _run_noninteractive(
        executable, ["--version"], controlled_directory, raw_directory / "version.raw"
    )
    auth_exit = _run_noninteractive(
        executable, ["auth", "status"], controlled_directory, raw_directory / "auth-status.raw"
    )
    usage_exit = _capture_usage(
        executable,
        controlled_directory,
        raw_directory / "usage.raw",
        startup_delay=startup_delay,
        capture_duration=capture_duration,
    )

    _validate_permissions(scratch, raw_directory, controlled_directory, RAW_NAMES)

    reports: dict[str, object] = {}
    for raw_name, sanitized_name in zip(RAW_NAMES, SANITIZED_NAMES, strict=True):
        report = sanitize_file(raw_directory / raw_name, sanitized_directory / sanitized_name)
        reports[sanitized_name] = report.as_dict()

    metadata = {
        "commands": [
            "claude --version",
            "claude auth status",
            "claude --safe-mode --ax-screen-reader --allowed-tools '' (PTY input: /usage)",
        ],
        "exitStatus": {
            "version": version_exit,
            "authStatus": auth_exit,
            "usage": usage_exit,
        },
        "sanitizerReports": reports,
        "writesToClaudePTY": ["/usage\\r"],
    }
    _write_metadata(scratch / "capture-metadata.json", metadata)

    return {
        "status": "sanitized",
        "scratchDirectory": str(scratch),
        "rawDirectory": str(raw_directory),
        "sanitizedDirectory": str(sanitized_directory),
        "commands": metadata["commands"],
        "exitStatus": metadata["exitStatus"],
        "sanitizerReports": reports,
    }


def run_usage_retry(
    executable: Path,
    scratch_parent: Path | None = None,
    startup_delay: float = 8,
    capture_duration: float = 20,
    trusted_working_directory: Path | None = None,
) -> dict[str, object]:
    """Run Jeremy's separately approved one-shot retry after a project-trust interception."""
    if not executable.is_absolute() or not executable.is_file() or not os.access(executable, os.X_OK):
        raise CaptureError("the Claude executable could not be resolved safely")

    scratch, raw_directory, sanitized_directory, controlled_directory = (
        _create_private_capture_directories(scratch_parent)
    )
    working_directory = controlled_directory
    bypass_project_trust = True
    working_directory_policy = "private-controlled"
    if trusted_working_directory is not None:
        resolved_working_directory = trusted_working_directory.resolve()
        if not resolved_working_directory.is_dir():
            raise CaptureError("the approved trusted working directory is unavailable")
        working_directory = resolved_working_directory
        bypass_project_trust = False
        working_directory_policy = "explicit-trusted-fixture-exception"
    usage_exit = _capture_usage(
        executable,
        working_directory,
        raw_directory / "usage.raw",
        startup_delay=startup_delay,
        capture_duration=capture_duration,
        bypass_project_trust=bypass_project_trust,
    )
    _validate_permissions(scratch, raw_directory, controlled_directory, ("usage.raw",))

    report = sanitize_file(raw_directory / "usage.raw", sanitized_directory / "usage.ans")
    command = "claude --safe-mode --ax-screen-reader --allowed-tools ''"
    if bypass_project_trust:
        command += " --dangerously-skip-permissions"
    command += " (PTY input: /usage)"
    metadata = {
        "commands": [command],
        "exitStatus": {"usage": usage_exit},
        "sanitizerReports": {"usage.ans": report.as_dict()},
        "writesToClaudePTY": ["/usage\\r"],
        "workingDirectoryPolicy": working_directory_policy,
    }
    _write_metadata(scratch / "capture-metadata.json", metadata)
    return {
        "status": "sanitized",
        "scratchDirectory": str(scratch),
        "rawDirectory": str(raw_directory),
        "sanitizedDirectory": str(sanitized_directory),
        "commands": metadata["commands"],
        "exitStatus": metadata["exitStatus"],
        "sanitizerReports": metadata["sanitizerReports"],
        "workingDirectoryPolicy": working_directory_policy,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scratch-parent",
        type=Path,
        help="Optional existing private parent directory for the new 0700 capture directory.",
    )
    parser.add_argument(
        "--usage-only-approved-retry",
        action="store_true",
        help="Run only the separately approved one-shot /usage retry with trust bypass.",
    )
    parser.add_argument(
        "--trusted-working-directory",
        type=Path,
        help="Explicitly approved existing trusted cwd for fixture capture only.",
    )
    arguments = parser.parse_args()
    if arguments.trusted_working_directory is not None and not arguments.usage_only_approved_retry:
        parser.error("--trusted-working-directory requires --usage-only-approved-retry")

    resolved = shutil.which("claude")
    if resolved is None:
        print(json.dumps({"status": "failed", "reason": "Claude Code was not found"}), file=sys.stderr)
        return 1

    try:
        if arguments.usage_only_approved_retry:
            result = run_usage_retry(
                Path(resolved).resolve(),
                scratch_parent=arguments.scratch_parent,
                trusted_working_directory=arguments.trusted_working_directory,
            )
        else:
            result = run_capture(Path(resolved).resolve(), scratch_parent=arguments.scratch_parent)
    except (CaptureError, OSError, SanitizationError) as error:
        print(json.dumps({"status": "failed", "reason": str(error)}, sort_keys=True), file=sys.stderr)
        return 1

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
