# Security boundaries and local validation

PromptJuice is a local macOS application. Its Swift package currently has no external
package dependencies. Usage comes from installed Codex and Claude executables, which
run with the user's permissions and can use their existing account sessions. Enable
only providers whose local usage data you want PromptJuice to read. Automatic usage
refreshes begin after the first-run provider selection is saved.

Provider selection prevents new disabled-provider refresh tasks. A read already in
progress when a provider is disabled may finish. Codex app-server reads cap total
stdout at 1 MiB and stderr at 64 KiB, poll cancellation, and allow 200 ms for termination
before sending SIGKILL to the launched child, with a further bounded wait. Cleanup
only targets that child; it does not enumerate other CLI instances or promise to
terminate arbitrary independently spawned descendants.

The capture sanitizer decodes JSON before redacting sensitive field values of every
type, including nested containers. It analyzes ANSI-normalized text and rejects
malformed JSON. Plaintext assignments are redacted through the end of the line.
Sanitization is based on recognized shapes: arbitrary prose can still contain private
information. Keep raw captures private and inspect sanitized captures before sharing.

## Runtime maintenance

Keep installed provider CLIs and any runtime used by their launchers supported and
patched. For npm-installed Codex, `command -v codex` and `node --version` help identify
the launcher/runtime in use; an executable's resolved path and PATH can differ from
those in a terminal. Node 20 is end of life as of this review (2026-10-23); use a
supported LTS release or a supported native CLI distribution. See the official
[Node release status](https://nodejs.org/en/about/previous-releases).
PromptJuice does not update global runtimes, CLI installations, or account credentials.

## Offline regression checks

Run `swift test` and
`python3 -m unittest discover -s scripts/claude-usage-capture/tests -p 'test_*.py'`.
The default tests use fixtures and synthetic local processes. Live account checks
remain opt-in and are skipped without their explicit environment flags. AppKit window
tests need a normal macOS desktop session. CI also checks shell scripts and metadata,
and builds and verifies the release app bundle; no app installation is needed.
