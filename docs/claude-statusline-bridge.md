# Claude Statusline Bridge

PromptJuice can read exact Claude usage from a local cache written by Claude Code's statusline command.

Default cache path:

```text
~/Library/Application Support/PromptJuice/ClaudeStatus/latest.json
```

Claude Code sends statusline JSON to a configured `statusLine.command`. The PromptJuice bridge script reads that JSON, writes a sanitized cache for PromptJuice, then runs the user's existing statusline command when one is configured.

## Setup

Configure Claude Code to run the bridge and delegate to your existing statusline command:

```json
{
  "statusLine": {
    "type": "command",
    "command": "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/statusline-command.sh' bash /absolute/path/to/prompt-juice/scripts/claude-statusline-bridge.sh"
  }
}
```

Users without an existing statusline command can run only the bridge:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /absolute/path/to/prompt-juice/scripts/claude-statusline-bridge.sh"
  }
}
```

If you create `~/.claude/statusline-command.sh` after PromptJuice setup, the bridge will automatically delegate to it after writing PromptJuice's usage cache.

Claude Code reloads statusline changes on the next interaction. After a Claude assistant response, verify the cache:

```bash
stat "$HOME/Library/Application Support/PromptJuice/ClaudeStatus/latest.json"
jq . "$HOME/Library/Application Support/PromptJuice/ClaudeStatus/latest.json"
```

Then use PromptJuice -> Refresh Usage. The Claude row should show `claudeStatusline` with `exact` confidence when the cache contains a complete active five-hour window.

## Cache Shape

The bridge writes the fields PromptJuice needs:

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

`resets_at` is normalized to text so PromptJuice can parse epoch timestamps and ISO-8601 timestamps through the same reader.

## Environment

- `PROMPTJUICE_CLAUDE_STATUS_CACHE` overrides the cache path.
- `PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND` delegates rendering to an existing statusline command.

## Safety

- The bridge runs locally through Claude Code statusline.
- It writes sanitized rate-limit fields.
- It leaves OAuth tokens, auth files, cookies, transcripts, project paths, and raw statusline JSON out of the PromptJuice cache.
- Cache writes are atomic.
- Cache write failures still allow the existing statusline command to render.
