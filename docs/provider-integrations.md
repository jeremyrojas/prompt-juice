# Provider Integrations

PromptJuice uses local provider adapters that return normalized snapshots for the UI and alert engine. Each snapshot includes the provider identity, rate window, source, confidence, update time, and optional status detail.

## Codex

PromptJuice reads Codex usage through the local Codex app-server.

Current path:

1. Locate the Codex executable.
2. Launch `codex app-server` over stdio.
3. Send `initialize` with PromptJuice client metadata and experimental API capability.
4. Send `initialized`.
5. Call `account/rateLimits/read`.
6. Decode the preferred Codex bucket from `rateLimitsByLimitId["codex"]`, then `rateLimits`.
7. Map the primary rate-limit window into a `ProviderSnapshot`.

PromptJuice looks for Codex in this order:

1. `PROMPTJUICE_CODEX_PATH`
2. `/Applications/Codex.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. `which codex`

### Codex Source Labels

- `codexAppServer` + `exact`: `account/rateLimits/read` returned a complete primary window.
- `codexCache` + `stale`: live read failed and a last-good window is still before reset.
- `codexAppServer` + `unavailable`: the executable, launch, initialization, read, timeout, or parser step failed.

### Codex Troubleshooting

Check that Codex is installed and reachable:

```bash
codex --help
codex app-server --help
```

Run Codex diagnostics:

```bash
codex doctor
```

Set an explicit executable path when automatic lookup misses Codex:

```bash
export PROMPTJUICE_CODEX_PATH="/Applications/Codex.app/Contents/Resources/codex"
```

The app detail line includes the source and confidence label. Unavailable Codex reads include a short status detail such as launch failure, timeout, server error, or unreadable rate-limit response.

## Claude

PromptJuice reads Claude usage through a confidence ladder:

1. Claude Code per-session statusline cache.
2. Last-good Claude statusline cache before each window's reset.
3. Local Claude project-log estimate.
4. Unavailable snapshot.

### Claude Code Statusline Cache

The cache directory is:

```text
~/Library/Application Support/PromptJuice/ClaudeStatus/
```

The bridge script at `scripts/claude-statusline-bridge.sh` reads Claude Code statusline JSON from stdin, writes sanitized per-session rate-limit fields to the PromptJuice cache, then delegates to the user's existing statusline command when configured. PromptJuice sets Claude Code's `statusLine.refreshInterval` to `10`, which refreshes the bridge every 10 seconds while Claude Code is open.

New builds read flat `session-*.json` files first:

```text
ClaudeStatus/session-<session_id>.json
```

Expected per-session cache shape:

```json
{
  "observed_at": "2026-07-02T12:38:45Z",
  "session_id": "c0df7847-af35-48ab-a021-bac2dcdeee88",
  "rate_limits": {
    "five_hour": {
      "used_percentage": 12.5,
      "resets_at": "1800001800",
      "duration_minutes": 300
    },
    "seven_day": {
      "used_percentage": 33,
      "resets_at": "1800345600",
      "duration_minutes": 10080
    }
  }
}
```

The bridge also writes legacy `latest.json` with the five-hour window only so older PromptJuice builds keep working. New builds fall back to `latest.json` when no session files exist.

`resets_at` may be an epoch timestamp string or an ISO-8601 timestamp.

PromptJuice merges session files by dropping expired windows, choosing the greatest surviving `resets_at`, grouping reset times within 90 seconds, then picking the highest `used_percentage` in that group. This makes old idle Claude Code sessions harmless even when they keep rewriting expired windows.

When every known five-hour window has expired, Claude shows **Fresh window** at 100% session remaining. When the weekly window is still valid, the Claude row also shows `Week: N% left` and can constrain the row/header/menu-bar fill. Weekly readings older than 30 minutes include an `as of` time.

Setup details live in [claude-statusline-bridge.md](claude-statusline-bridge.md).

### Claude Local-Log Estimate

When the statusline cache is unavailable, PromptJuice scans local Claude project logs from:

- `CLAUDE_CONFIG_DIR`
- `~/.config/claude/projects`
- `~/.claude/projects`

The reader groups assistant messages into five-hour blocks, deduplicates repeated usage entries when message and request ids are present, and estimates the active block's used percentage from local token counts. The UI labels this path as `claudeLocalLogs` with `estimated` confidence.

### Claude Source Labels

- `claudeStatusline` + `exact`: statusline cache contains a complete active five-hour window.
- `claudeStatusline` + `stale`: statusline cache contains a valid carry-forward window from an earlier file mtime.
- `claudeCache` + `stale`: statusline read failed and a last-good session or weekly window is still usable.
- `claudeLocalLogs` + `estimated`: local logs produced an active five-hour block estimate.
- `claudeStatusline` + `unavailable`: statusline cache and local-log estimate both failed. This is the waiting-for-terminal path when the bridge is installed and no rate-limit data has ever been seen.

### Claude Troubleshooting

Verify the bridge cache exists:

```bash
ls -lt "$HOME/Library/Application Support/PromptJuice/ClaudeStatus"
/usr/bin/plutil -p "$HOME/Library/Application Support/PromptJuice/ClaudeStatus/session-"*.json
```

Check the statusline bridge directly with sample input:

```bash
printf '%s\n' '{"session_id":"demo","rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":"1800001800","duration_minutes":300},"seven_day":{"used_percentage":33,"resets_at":"1800345600","duration_minutes":10080}}}' \
  | bash scripts/claude-statusline-bridge.sh
```

Then refresh PromptJuice from the menu-bar item.
