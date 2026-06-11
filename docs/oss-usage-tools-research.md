# OSS Usage Tools Research

Research thread: PromptJuice OSS usage research (`019eb2ba-7f77-7f40-8ac0-36ea43cd1341`)

Sources reviewed:

- [ccusage](https://github.com/ccusage/ccusage)
- [ccusage Claude guide](https://github.com/ccusage/ccusage/blob/main/docs/guide/claude/index.md)
- [ccusage Codex guide](https://github.com/ccusage/ccusage/blob/main/docs/guide/codex/index.md)
- [CodexBar](https://github.com/steipete/CodexBar)
- [CodexBar Claude docs](https://github.com/steipete/CodexBar/blob/main/docs/claude.md)
- [CodexBar Codex docs](https://github.com/steipete/CodexBar/blob/main/docs/codex.md)
- [CodexBar Cursor docs](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md)
- [CodexBar provider docs](https://github.com/steipete/CodexBar/blob/main/docs/provider.md)

## Summary

PromptJuice should stay focused on one high-value question:

> How much useful AI capacity is left, and should I use it before reset?

The strongest product angle is a Mac-native Juicebar that surfaces remaining usage, reset urgency, and a quiet nudge at the right moment. The app should keep charts and long usage reports behind a detail view, while the default experience stays fast, tiny, and action-oriented.

ccusage proves there is demand for local usage analytics. It gives us patterns for reading local Claude/Codex logs, reconstructing token usage, modeling Claude 5-hour blocks, and producing reliable summaries.

CodexBar proves the menu-bar quota/status category. It gives us patterns for provider abstractions, reset windows, source freshness, credentials, notifications, and multi-provider UI. Its breadth is also a warning: provider integrations can consume the whole product if we chase every source early.

## What ccusage Gives Us

ccusage is a local-first CLI analyzer for coding-agent usage. It reads provider logs and generates daily, weekly, monthly, session, and block reports.

Useful takeaways:

- Local logs are valuable for history, cost, and session reconstruction.
- Claude usage can be grouped into 5-hour blocks, which maps well to our alert window idea.
- Claude paths include `~/.config/claude/projects`, `~/.claude/projects`, and `CLAUDE_CONFIG_DIR`.
- Codex usage can be reconstructed from `CODEX_HOME` session JSONL under `sessions/` and `archived_sessions/`.
- Codex token counts need careful event parsing, model attribution, and deduping.
- A CLI-style JSON output mode is useful for future automation and testing.

Limit:

- Local logs can show what happened, active windows, and estimated cost. Provider-side hidden quotas and exact remaining allowance need provider-reported data.

## What CodexBar Gives Us

CodexBar is a native macOS menu-bar app for AI provider limits, quota windows, reset times, credits, incidents, account identity, and optional cost scans.

Useful takeaways:

- A provider should expose normalized rate windows instead of app-specific fields.
- Each snapshot needs source metadata: provider-reported, local-log-derived, web-derived, estimated, stale, or failed.
- Menu-bar apps need strong stale/error states because users trust them as ambient instrumentation.
- Notifications should fire on threshold crossing, respect snooze, and avoid repeated nudges in the same reset window.
- Provider bridges need bounded timeouts, cached last-good snapshots, and clear diagnostics.
- Credential-adjacent integrations need local-first behavior, Keychain, explicit setup, and inspectable connection state.

Limit:

- Broad provider support creates significant maintenance drag. PromptJuice should make Claude and Codex excellent before Cursor or other tools.

## Product Bet

People will use PromptJuice if it prevents two annoying situations:

- Starting a long agent run when the current window is almost depleted.
- Wasting a large usable window because reset is close and they forgot to use it.

The Juicebar should lead with:

- Provider.
- Percent left or percent to use.
- Reset countdown.
- Stale/source state.
- Snooze.

Useful stats for stickiness:

- Last updated.
- Account/provider identity.
- Today and 7-day spend or token estimate.
- Alert history.
- Source confidence.

Charts can wait. The main value is timing and trust.

## Technical Direction

Use a shared provider model:

```swift
struct ProviderSnapshot {
    let provider: UsageProviderID
    let identity: ProviderIdentity?
    let primaryWindow: RateWindow
    let secondaryWindows: [RateWindow]
    let costSummary: CostSummary?
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
    let staleAfter: Date
    let error: ProviderError?
}

struct RateWindow {
    let usedPercent: Double
    let remainingPercent: Double
    let resetAt: Date
    let durationMinutes: Int
    let label: String
}
```

Provider adapters should use ordered strategies:

1. Provider-reported quota or app-server data.
2. Local CLI/session state.
3. Local log-derived estimate.
4. Last-good cached snapshot with stale label.

Polling:

- Default: every 5 minutes.
- Near reset or alert threshold: every 1 minute.
- Manual refresh: on menu-bar click.
- Local cost/history scans: hourly or on demand.

Alerts:

- Trigger on threshold crossing.
- Store alert state per provider and reset window.
- Snooze per window.
- Suppress alerts when data is stale or low confidence.
- Include provider and reset countdown in copy.

## Provider Roadmap

### First Real Provider: Codex

Codex is a good first live integration because it may expose true rate windows through local Codex app-server/account state. Local `CODEX_HOME` JSONL can supplement usage history and cost.

Implementation path:

- Detect `CODEX_HOME`.
- Read local session history for cost/history only.
- Investigate `codex app-server` for current quota/reset data.
- Store source confidence and last-good snapshot.

### Second Provider: Claude

Claude should use a confidence ladder:

- Provider-reported usage when available.
- Claude Code CLI usage/status path when available.
- ccusage-style local project logs for active blocks, history, and estimates.

The UI should label estimates clearly.

### Later Provider: Cursor

Cursor can come after the provider system is stable. It likely involves cookies/session APIs, so the setup UX and privacy story need to be mature first.

## Business And OSS

Open source fits PromptJuice because the app may touch local agent logs and credentials. Trust is part of the product.

Realistic monetization:

- GitHub Sponsors.
- Paid signed/notarized convenience build.
- Paid early builds or sponsorware.
- Optional Pro features: multi-account, advanced quiet rules, widgets, team presets, and richer history.
- Homebrew distribution for free/self-built users.

The business upside is modest. The strategic upside is reputation, community trust, and a useful personal tool that could grow into a small sponsor-supported utility.

## Plan Changes

Add to the current PromptJuice plan:

- Treat `RateWindow` as the core internal abstraction.
- Add `source`, `confidence`, `updatedAt`, and `staleAfter` to snapshots early.
- Store snooze/alert state per provider reset window.
- Add a tiny details view before charts: source freshness, identity, last update, and recent cost estimate.
- Make Codex the first real provider candidate.
- Make Claude second, with local-log estimates clearly labeled.
- Defer Cursor until the setup/privacy model feels solid.

## What To Avoid

- Provider sprawl before Claude and Codex are trustworthy.
- Dashboard-first UX.
- Silent web scraping or hidden cookie use.
- Quota guesses presented as exact usage.
- Repeated alerts inside the same reset window.
- Setup flows that require many choices before the first useful alert.
