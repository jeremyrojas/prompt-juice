# PromptJuice Overview

PromptJuice is a small Mac utility for keeping Claude and Codex usage windows visible at the moment they matter.

The app lives in the menu bar. When you open it, a compact Juicebar appears near the top of the current display with provider rows, reset countdowns, remaining capacity, source labels, and Snooze.

## Core Experience

PromptJuice focuses on a simple workflow:

1. Read local provider usage state.
2. Normalize each provider into a `ProviderSnapshot`.
3. Label every snapshot with source and confidence.
4. Show the current Claude and Codex windows in a native macOS panel.
5. Nudge the user when meaningful capacity remains close to reset.

The current app supports manual refresh, live provider reads, fixture-backed tests and previews, threshold controls, native notifications, and one-window Snooze behavior.

## Usage Model

Provider data flows through a small shared model:

```swift
struct ProviderSnapshot {
    let identity: ProviderIdentity
    let rateWindow: RateWindow
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
    let statusDetail: String?
}
```

`RateWindow` carries the current used percentage, reset time, duration, remaining percentage, and a stable window id. The UI uses that normalized shape for Claude, Codex, and fixture data.

## Source And Confidence

PromptJuice shows provider data with explicit source labels:

- `fixture`: built-in test and preview values.
- `codexAppServer`: live Codex data from `codex app-server`.
- `codexCache`: cached last-good Codex window.
- `claudeStatusline`: live Claude Code statusline cache.
- `claudeLocalLogs`: local Claude log estimate.
- `claudeCache`: cached last-good Claude statusline window.

PromptJuice uses four confidence states:

- `exact`: provider-reported or provider-supplied window data.
- `estimated`: local-log-derived usage approximation.
- `stale`: cached last-good provider data before its reset time.
- `unavailable`: readable failure state with a short diagnostic.

Alert rules can use `exact` and `estimated` snapshots. Stale and unavailable snapshots stay visible for diagnostics and manual checks.

## Codex Integration

PromptJuice reads Codex through the local Codex app-server. The client launches `codex app-server` over stdio, sends `initialize` and `initialized`, then calls `account/rateLimits/read`.

The Codex rate-limit response maps to PromptJuice like this:

- `rateLimitsByLimitId["codex"]` supplies the preferred Codex bucket when present.
- `rateLimits` supplies the backward-compatible single-bucket fallback.
- `primary.usedPercent` becomes the displayed used percentage.
- `primary.resetsAt` becomes the reset time.
- `primary.windowDurationMins` becomes the window duration.
- `rateLimitReachedType` is preserved as status detail.

PromptJuice stores only the last-good normalized Codex window and freshness metadata in local user defaults.

## Claude Integration

PromptJuice reads Claude through two local paths:

- Claude Code statusline bridge cache at `~/Library/Application Support/PromptJuice/ClaudeStatus/latest.json`.
- Local Claude project logs under `CLAUDE_CONFIG_DIR`, `~/.config/claude/projects`, or `~/.claude/projects`.

The statusline bridge produces exact five-hour window data when Claude Code provides `rate_limits.five_hour`. The local-log reader groups assistant usage into five-hour blocks and marks the result as an estimate.

PromptJuice stores only the last-good normalized Claude statusline window and freshness metadata in local user defaults.

## Privacy Posture

PromptJuice is local-first:

- Provider reads happen on the user's Mac.
- The Codex path reads rate-limit state through the local Codex app-server.
- The Claude bridge writes sanitized rate-limit fields into the PromptJuice cache.
- Local-log estimates read usage metadata needed for the active window calculation.
- Cached provider snapshots store normalized usage windows and update times.

## Current Prototype Behavior

- Launches as a macOS accessory app.
- Shows a droplet in the menu bar.
- Opens a rounded Juicebar panel with Claude and Codex rows.
- Uses live usage in production and fixture usage in tests/previews.
- Lets users refresh usage from the menu.
- Displays source and confidence in the detail line.
- Uses native notifications for use-soon alerts.
- Lets users Snooze the current alert window.

## Development

Build and run:

```bash
./scripts/run_app.sh
```

Run tests:

```bash
swift test
```
