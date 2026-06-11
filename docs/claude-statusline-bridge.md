# Claude Statusline Bridge

PromptJuice reads exact Claude usage from:

```text
~/Library/Application Support/PromptJuice/ClaudeStatus/latest.json
```

Claude Code exposes exact usage to a configured `statusLine.command`. The bridge
script reads that statusline JSON, writes a sanitized PromptJuice cache, then
runs the existing custom statusline command with the original JSON.

## Local Setup

Your current Claude setting can keep its custom statusline script as the
delegate:

```json
{
  "statusLine": {
    "type": "command",
    "command": "PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='bash ~/.claude/statusline-command.sh' bash /absolute/path/to/prompt-juice/scripts/claude-statusline-bridge.sh"
  }
}
```

Claude Code reloads statusline changes on the next interaction. After a Claude
assistant response, verify the cache:

```bash
stat "$HOME/Library/Application Support/PromptJuice/ClaudeStatus/latest.json"
jq . "$HOME/Library/Application Support/PromptJuice/ClaudeStatus/latest.json"
```

Then use PromptJuice -> Refresh Usage. The Claude row should read from
`.claudeStatusline` with exact confidence.

## Cache Shape

The bridge writes only the fields PromptJuice needs:

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

`resets_at` is normalized to text so PromptJuice can parse epoch timestamps and
ISO-8601 timestamps through the same reader.

## Safety

- The bridge runs locally through Claude Code statusline.
- It writes only sanitized rate-limit fields.
- It leaves OAuth tokens, auth files, cookies, transcripts, cwd/project names,
  and raw statusline JSON out of the PromptJuice cache.
- Cache writes are atomic.
- Cache write failures still allow the existing statusline command to render.
