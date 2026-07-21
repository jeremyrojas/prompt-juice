# Claude `/usage` capture harness

This harness performs the three Phase 1 read-only captures approved by Jeremy:

1. `claude --version`
2. `claude auth status`
3. one controlled Claude Code process receiving exactly `/usage` over a PTY

The harness creates a new mode-`0700` scratch directory containing an empty controlled working
directory, mode-`0600` raw files, sanitized files, and metadata. Raw process output is written
directly to private files. The terminal process receives one allowlisted byte sequence,
`/usage\r`, and is terminated after the bounded capture interval.

The sanitizer redacts and checks credentials, tokens, emails, account and organization IDs,
UUIDs, usernames, home and absolute paths, sensitive labeled fields, and long opaque values.
It preserves ANSI/control bytes, timestamps, timezone spelling, labels, whitespace, and other
terminal structure. A residual sensitive shape rejects the capture.

Run the synthetic tests first:

```sh
python3 -m unittest discover -s scripts/claude-usage-capture/tests -p 'test_*.py'
```

The real capture command is:

```sh
python3 scripts/claude-usage-capture/capture_claude_usage.py
```

If a fresh private working directory is intercepted by Claude Code's project-trust prompt,
Jeremy may separately authorize one retry. That retry invokes only the interactive capture and
adds the nonpersistent trust-bypass flag:

```sh
python3 scripts/claude-usage-capture/capture_claude_usage.py \
  --usage-only-approved-retry
```

The retry path performs no version or auth-status invocation.

Claude Code 2.1.214 keeps workspace trust separate from permission mode, so a newly created
private cwd can still stop at the project-trust gate. With Jeremy's explicit approval, fixture
capture may use an existing trusted checkout as the Claude process cwd:

```sh
python3 scripts/claude-usage-capture/capture_claude_usage.py \
  --usage-only-approved-retry \
  --trusted-working-directory /absolute/path/to/approved/trusted/checkout
```

This exception exists only to capture a sanitized real fixture. It remains a specification
finding for the production probe architecture. Safe mode, the empty tool allowlist, the single
`/usage\r` PTY write, bounded cleanup, private raw output, and sanitizer still apply.

The command prints safe metadata and private artifact locations. It never prints captured
Claude output. Inspect only files in the reported `sanitizedDirectory`. Keep the reported raw
directory private and untracked until Jeremy gives deletion instructions.
