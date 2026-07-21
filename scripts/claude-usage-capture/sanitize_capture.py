#!/usr/bin/env python3
"""Fail-closed sanitizer for private PromptJuice Claude capture artifacts."""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import stat
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


MAX_CAPTURE_BYTES = 2 * 1024 * 1024

EMAIL_RE = re.compile(
    r"(?i)(?<![a-z0-9._%+-])[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}(?![a-z0-9._%+-])"
)
UUID_RE = re.compile(
    r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"
)
ABSOLUTE_PATH_RE = re.compile(
    r"(?<![a-zA-Z0-9_:/])/(?:[^/\s\x00-\x1f\"'<>|]+/)+[^/\s\x00-\x1f\"'<>|,;:]+"
)
HOME_PATH_RE = re.compile(r"(?<![a-zA-Z0-9_])~/(?:[^\s\x00-\x1f\"'<>|]+)")
ACCOUNT_ID_RE = re.compile(
    r"(?i)\b(?:org|organization|acct|account|usr|user|workspace|team)[_-][a-z0-9][a-z0-9_-]{5,}\b"
)
SECRET_PREFIX_RE = re.compile(
    r"(?i)\b(?:sk-ant|sk-proj|sk|ghp|github_pat|xox[baprs]|AKIA)[-_a-z0-9]{8,}\b"
)
JWT_RE = re.compile(
    r"\beyJ[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\.[a-zA-Z0-9_-]{8,}\b"
)
BEARER_RE = re.compile(r"(?i)(\bbearer\s+)(?!\[REDACTED_)[^\s\"',;}]+")
OPAQUE_RE = re.compile(
    r"\b(?=[a-zA-Z0-9_+=.-]{32,}\b)(?=[a-zA-Z0-9_+=.-]*[a-zA-Z])(?=[a-zA-Z0-9_+=.-]*[0-9])[a-zA-Z0-9_+=.-]{32,}\b"
)

SENSITIVE_KEY_FRAGMENT = (
    r"(?:token|secret|password|passwd|credential|cookie|authorization|api[_-]?key|"
    r"(?:account|organization|org|user|workspace|team)[_-]?(?:id|uuid|name)?|"
    r"email|e-mail|username|user[_-]?name|display[_-]?name)"
)
SENSITIVE_JSON_STRING_RE = re.compile(
    rf"(?i)(?P<prefix>\"[^\"]*{SENSITIVE_KEY_FRAGMENT}[^\"]*\"\s*:\s*\")"
    r"(?P<value>[^\"]*)(?P<suffix>\")"
)
SENSITIVE_ASSIGNMENT_RE = re.compile(
    rf"(?i)(?P<prefix>\b[a-z0-9_.-]*{SENSITIVE_KEY_FRAGMENT}[a-z0-9_.-]*\s*[:=]\s*[\"']?)"
    r"(?P<value>(?!\[REDACTED_)[^\s\"',;}\]]+)(?P<suffix>[\"']?)"
)
SENSITIVE_LABEL_RE = re.compile(
    rf"(?im)(?P<prefix>^\s*{SENSITIVE_KEY_FRAGMENT}\s*:\s*)(?P<value>(?!\[REDACTED_)[^\r\n]+)$"
)
SENSITIVE_KEY_NAME_RE = re.compile(rf"(?i){SENSITIVE_KEY_FRAGMENT}")
WELCOME_NAME_RE = re.compile(
    r"(?im)(?P<prefix>^Welcome back\s+)(?P<value>[^!\r\n]+)(?P<suffix>!)"
)
MCP_QUOTED_NAME_RE = re.compile(
    r'(?i)(?P<prefix>\bMCP server\s+")(?P<value>[^"\r\n]+)(?P<suffix>")'
)
MCP_TABLE_BLOCK_RE = re.compile(
    r"(?im)(?P<prefix>^MCP servers % of usage\r?\n)"
    r"(?P<rows>(?:^[^\r\n]+\s+\d{1,3}%\r?\n?)+)"
)
MCP_TABLE_NAME_RE = re.compile(r"(?im)^[^\r\n%]+?(?=\s+\d{1,3}%\r?$)")


class SanitizationError(RuntimeError):
    """Raised when a capture cannot be sanitized with high confidence."""


@dataclass(frozen=True)
class SanitizationReport:
    input_bytes: int
    output_bytes: int
    replacements: dict[str, int]

    def as_dict(self) -> dict[str, object]:
        return {
            "inputBytes": self.input_bytes,
            "outputBytes": self.output_bytes,
            "replacements": self.replacements,
        }


def _local_usernames() -> tuple[str, ...]:
    values = {getpass.getuser(), os.environ.get("USER", ""), os.environ.get("LOGNAME", "")}
    return tuple(sorted(value for value in values if len(value) >= 3 and value != "root"))


def _replace(
    pattern: re.Pattern[str],
    text: str,
    replacement: str | Callable[[re.Match[str]], str],
    category: str,
    counts: Counter[str],
) -> str:
    def counted(match: re.Match[str]) -> str:
        counts[category] += 1
        if callable(replacement):
            return replacement(match)
        return replacement

    return pattern.sub(counted, text)


def _replace_grouped_value(placeholder: str):
    def replacement(match: re.Match[str]) -> str:
        suffix = match.groupdict().get("suffix") or ""
        return f"{match.group('prefix')}{placeholder}{suffix}"

    return replacement


def sanitize_text(text: str, usernames: Iterable[str] | None = None) -> tuple[str, Counter[str]]:
    """Redact shaped sensitive values while retaining terminal structure and control bytes."""
    counts: Counter[str] = Counter()
    sanitized = text

    sanitized = _replace(
        SENSITIVE_JSON_STRING_RE,
        sanitized,
        _replace_grouped_value("[REDACTED_FIELD]"),
        "sensitive-field",
        counts,
    )
    sanitized = _replace(
        WELCOME_NAME_RE,
        sanitized,
        _replace_grouped_value("[REDACTED_USERNAME]"),
        "username",
        counts,
    )
    sanitized = _replace(
        MCP_QUOTED_NAME_RE,
        sanitized,
        _replace_grouped_value("[REDACTED_MCP_NAME]"),
        "mcp-name",
        counts,
    )
    def redact_mcp_table(match: re.Match[str]) -> str:
        def redact_name(_: re.Match[str]) -> str:
            counts["mcp-name"] += 1
            return "[REDACTED_MCP_NAME]"

        return match.group("prefix") + MCP_TABLE_NAME_RE.sub(redact_name, match.group("rows"))

    sanitized = MCP_TABLE_BLOCK_RE.sub(redact_mcp_table, sanitized)
    sanitized = _replace(
        SENSITIVE_LABEL_RE,
        sanitized,
        _replace_grouped_value("[REDACTED_FIELD]"),
        "sensitive-label",
        counts,
    )
    sanitized = _replace(
        SENSITIVE_ASSIGNMENT_RE,
        sanitized,
        _replace_grouped_value("[REDACTED_CREDENTIAL]"),
        "credential",
        counts,
    )
    sanitized = _replace(
        BEARER_RE,
        sanitized,
        lambda match: f"{match.group(1)}[REDACTED_CREDENTIAL]",
        "credential",
        counts,
    )
    sanitized = _replace(EMAIL_RE, sanitized, "[REDACTED_EMAIL]", "email", counts)
    sanitized = _replace(UUID_RE, sanitized, "[REDACTED_UUID]", "uuid", counts)
    sanitized = _replace(ACCOUNT_ID_RE, sanitized, "[REDACTED_ACCOUNT_ID]", "account-id", counts)
    sanitized = _replace(SECRET_PREFIX_RE, sanitized, "[REDACTED_CREDENTIAL]", "credential", counts)
    sanitized = _replace(JWT_RE, sanitized, "[REDACTED_CREDENTIAL]", "credential", counts)
    sanitized = _replace(ABSOLUTE_PATH_RE, sanitized, "[REDACTED_PATH]", "absolute-path", counts)
    sanitized = _replace(HOME_PATH_RE, sanitized, "[REDACTED_PATH]", "home-path", counts)

    for username in usernames if usernames is not None else _local_usernames():
        username_re = re.compile(rf"(?i)(?<![a-z0-9_.-]){re.escape(username)}(?![a-z0-9_.-])")
        sanitized = _replace(username_re, sanitized, "[REDACTED_USERNAME]", "username", counts)

    sanitized = _replace(OPAQUE_RE, sanitized, "[REDACTED_OPAQUE]", "opaque-value", counts)
    return sanitized, counts


def _unexpected_structured_sensitive_fields(text: str) -> list[str]:
    """Reject sensitive JSON containers whose unknown contents cannot be safely preserved."""
    try:
        value = json.loads(text)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return []

    findings: list[str] = []

    def visit(node: object) -> None:
        if isinstance(node, dict):
            for key, child in node.items():
                if SENSITIVE_KEY_NAME_RE.search(str(key)) and isinstance(child, (dict, list)):
                    findings.append("structured-sensitive-field")
                visit(child)
        elif isinstance(node, list):
            for child in node:
                visit(child)

    visit(value)
    return sorted(set(findings))


def sensitive_findings(text: str, usernames: Iterable[str] | None = None) -> list[str]:
    """Return residual sensitive-shape categories without returning matched values."""
    findings: list[str] = []
    checks = (
        ("email", EMAIL_RE),
        ("uuid", UUID_RE),
        ("account-id", ACCOUNT_ID_RE),
        ("credential-prefix", SECRET_PREFIX_RE),
        ("jwt", JWT_RE),
        ("bearer-credential", BEARER_RE),
        ("absolute-path", ABSOLUTE_PATH_RE),
        ("home-path", HOME_PATH_RE),
        ("opaque-value", OPAQUE_RE),
    )
    for category, pattern in checks:
        if pattern.search(text):
            findings.append(category)

    for match in SENSITIVE_JSON_STRING_RE.finditer(text):
        if not match.group("value").strip().startswith("[REDACTED_"):
            findings.append("sensitive-json-field")
            break
    for match in SENSITIVE_ASSIGNMENT_RE.finditer(text):
        if not match.group("value").strip().startswith("[REDACTED_"):
            findings.append("sensitive-assignment")
            break
    for match in SENSITIVE_LABEL_RE.finditer(text):
        if not match.group("value").strip().startswith("[REDACTED_"):
            findings.append("sensitive-label")
            break
    for match in WELCOME_NAME_RE.finditer(text):
        if not match.group("value").strip().startswith("[REDACTED_"):
            findings.append("welcome-username")
            break
    for match in MCP_QUOTED_NAME_RE.finditer(text):
        if not match.group("value").strip().startswith("[REDACTED_"):
            findings.append("mcp-name")
            break

    for username in usernames if usernames is not None else _local_usernames():
        if re.search(rf"(?i)(?<![a-z0-9_.-]){re.escape(username)}(?![a-z0-9_.-])", text):
            findings.append("username")
            break

    return sorted(set(findings))


def sanitize_bytes(data: bytes, usernames: Iterable[str] | None = None) -> tuple[bytes, SanitizationReport]:
    if len(data) > MAX_CAPTURE_BYTES:
        raise SanitizationError("capture exceeds the sanitizer size limit")
    text = data.decode("utf-8", errors="surrogateescape")
    unexpected = _unexpected_structured_sensitive_fields(text)
    if unexpected:
        raise SanitizationError("unexpected sensitive structure: " + ", ".join(unexpected))
    sanitized, counts = sanitize_text(text, usernames=usernames)
    residual = sensitive_findings(sanitized, usernames=usernames)
    if residual:
        raise SanitizationError("residual sensitive shapes: " + ", ".join(residual))
    encoded = sanitized.encode("utf-8", errors="surrogateescape")
    return encoded, SanitizationReport(
        input_bytes=len(data),
        output_bytes=len(encoded),
        replacements=dict(sorted(counts.items())),
    )


def _read_regular_private_candidate(path: Path) -> bytes:
    metadata = path.lstat()
    if not stat.S_ISREG(metadata.st_mode):
        raise SanitizationError("capture input must be a regular file")
    if metadata.st_size > MAX_CAPTURE_BYTES:
        raise SanitizationError("capture exceeds the sanitizer size limit")
    return path.read_bytes()


def _write_private(path: Path, data: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags, 0o600)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb", closefd=False) as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
    finally:
        os.close(descriptor)


def sanitize_file(input_path: Path, output_path: Path) -> SanitizationReport:
    data = _read_regular_private_candidate(input_path)
    sanitized, report = sanitize_bytes(data)
    _write_private(output_path, sanitized)
    return report


def check_file(path: Path) -> SanitizationReport:
    data = _read_regular_private_candidate(path)
    text = data.decode("utf-8", errors="surrogateescape")
    findings = sensitive_findings(text)
    if findings:
        raise SanitizationError("residual sensitive shapes: " + ", ".join(findings))
    return SanitizationReport(input_bytes=len(data), output_bytes=len(data), replacements={})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="operation", required=True)

    sanitize_parser = subparsers.add_parser("sanitize")
    sanitize_parser.add_argument("input", type=Path)
    sanitize_parser.add_argument("output", type=Path)

    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("input", type=Path)

    arguments = parser.parse_args()
    try:
        if arguments.operation == "sanitize":
            report = sanitize_file(arguments.input, arguments.output)
        else:
            report = check_file(arguments.input)
    except (OSError, SanitizationError) as error:
        print(json.dumps({"status": "rejected", "reason": str(error)}, sort_keys=True), file=sys.stderr)
        return 1

    print(json.dumps({"status": "safe", **report.as_dict()}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
