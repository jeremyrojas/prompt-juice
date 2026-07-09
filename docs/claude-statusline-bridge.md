# Claude Statusline Bridge

PromptJuice can read exact Claude usage from a local cache written by Claude Code's statusline command.

Default cache directory:

```text
~/Library/Application Support/PromptJuice/ClaudeStatus/
```

Claude Code sends statusline JSON to a configured `statusLine.command`. The PromptJuice bridge script reads that JSON, writes sanitized cache files for PromptJuice, then runs the user's existing statusline command when one is configured. PromptJuice sets `statusLine.refreshInterval` to `10` so Claude Code refreshes the bridge every 10 seconds while Claude Code is open.

## Setup

Configure Claude Code to run the bridge and delegate to your existing statusline command:

```json
{
  "statusLine": {
    "type": "command",
    "command": "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/statusline-command.sh' bash /absolute/path/to/prompt-juice/scripts/claude-statusline-bridge.sh",
    "refreshInterval": 10
  }
}
```

Users without an existing statusline command can run only the bridge:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /absolute/path/to/prompt-juice/scripts/claude-statusline-bridge.sh",
    "refreshInterval": 10
  }
}
```

If you create `~/.claude/statusline-command.sh` after PromptJuice setup, the bridge will automatically delegate to it after writing PromptJuice's usage cache.

Claude Code reloads statusline changes on the next interaction. After Claude Code refreshes the status line, verify the cache:

```bash
ls -lt "$HOME/Library/Application Support/PromptJuice/ClaudeStatus"
/usr/bin/plutil -p "$HOME/Library/Application Support/PromptJuice/ClaudeStatus/session-"*.json
```

Then open the Juice Bar from the PromptJuice menu-bar droplet. The panel refreshes its local readings when it opens, and the Claude row should show `claudeStatusline` with `exact` confidence when a session cache contains a complete active five-hour window.

## Cache Shape

Bridge v2 writes one per-session cache file per Claude Code `session_id`, flat in the existing directory:

```text
ClaudeStatus/session-<session_id>.json
```

The `session_id` keeps only `A-Z`, `a-z`, `0-9`, `.`, `_`, and `-`, capped at 64 characters. Missing or empty ids become `unknown`.

Per-session files include the five-hour session window and the seven-day weekly window when Claude Code supplies them:

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

The bridge also keeps writing legacy `latest.json` for older PromptJuice builds:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 12.5,
      "resets_at": "1800001800",
      "duration_minutes": 300
    }
  }
}
```

`latest.json` remains five-hour only. The unavailable marker is still `{"rate_limits":{}}`.

`resets_at` is normalized to text so PromptJuice can parse epoch timestamps and ISO-8601 timestamps through the same reader.

## Merge Rule

PromptJuice reads up to 64 newest `session-*.json` files and merges each window kind separately:

1. Drop expired candidates where `resets_at <= now`.
2. Pick the maximum surviving `resets_at`, treating values within 90 seconds as the same server window.
3. Inside that same-window group, pick the highest `used_percentage`.
4. Mark the chosen window `exact` when its file mtime is within 2 minutes, otherwise carry it forward as `stale`.

Expired files therefore cannot poison a fresh session. Long-idle Claude Code processes can keep rewriting old windows, but those windows are ignored after their reset time.

When every known five-hour window has expired while some rate-limit data is still present, PromptJuice shows **Fresh window** with 100% session remaining. Fresh window is presentation-only: it carries no reset timestamp or countdown. When every known weekly window has expired, PromptJuice shows a fresh week. A weekly reading older than 30 minutes displays an `as of` time.

## Garbage Collection

Cache cleanup uses a `.gc-marker` file inside `ClaudeStatus/`. The bridge runs cleanup when the marker is missing or older than one hour, then touches the marker. Cleanup rules:

- delete `session-*.json` files whose mtime is older than 7 days;
- if more than 64 session files remain, delete the oldest by mtime down to 64;
- leave non-matching names untouched.

Delete or pre-age `.gc-marker` to force cleanup on the next bridge invocation.

## Environment

- `PROMPTJUICE_CLAUDE_STATUS_CACHE` overrides the cache path.
- `PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND` delegates rendering to an existing statusline command.
- `PROMPTJUICE_CLAUDE_STATUS_DEBUG=0` disables `debug-latest.json`.
- `PROMPTJUICE_CLAUDE_STATUS_DEBUG_PATH` overrides the debug file path.

## Safety

- The bridge runs locally through Claude Code statusline.
- It writes sanitized rate-limit fields.
- It leaves OAuth tokens, auth files, cookies, transcripts, project paths, and raw statusline JSON out of the PromptJuice cache.
- Cache writes are atomic.
- Cache write failures still allow the existing statusline command to render.
