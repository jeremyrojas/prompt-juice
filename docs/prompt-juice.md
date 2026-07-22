# PromptJuice Overview

PromptJuice is a native macOS menu-bar utility for keeping Claude and Codex
usage windows visible at the moment they matter.

The menu-bar droplet shows remaining session capacity. Opening it reveals the
Juice Bar with provider percentages, reset countdowns, and reading confidence.
The panel opens near the top of the current display and can be pinned, dragged,
and restored to its saved position.

## Core Experience

PromptJuice follows one small loop:

1. Read provider usage state on the user's Mac.
2. Normalize each provider into a `ProviderSnapshot`.
3. Label the snapshot with its source and confidence.
4. Present the active session windows in a native macOS panel.
5. Nudge the user when meaningful capacity remains close to reset.

The app refreshes on launch, activation, wake, panel open, and provider-window
expiry. Configurable thresholds control the orange use-soon state. When several
providers qualify together, PromptJuice combines them into one macOS
notification and records one notification latch per provider reset window.

## Usage Model

Provider data flows through a shared model:

```swift
struct ProviderSnapshot {
    let identity: ProviderIdentity
    let rateWindow: RateWindow
    let weeklyWindow: RateWindow?
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
    let weeklyUpdatedAt: Date?
    let statusDetail: String?
    let isFreshSessionWindow: Bool
    let isFreshWeeklyWindow: Bool
}
```

`RateWindow` carries the used percentage, reset time, duration, and derived
remaining percentage. The active session window drives the visible row and
droplet. Weekly windows are retained in the data and cache layers for future UI.

## Source And Confidence

PromptJuice uses these snapshot sources:

- `fixture`: built-in test and preview values.
- `codexAppServer`: live Codex data from `codex app-server`.
- `codexCache`: cached last-good Codex windows.
- `claudeUsageCLI`: direct Claude Code `/usage` data.
- `claudeLocalLogs`: local Claude activity estimate.
- `claudeCache`: cached last-good Claude windows.

The UI maps four confidence states to human-readable labels:

- `exact` -> **Live**
- `stale` -> **Earlier**
- `estimated` -> **Estimate**
- `unavailable` -> **Not set up** or a provider diagnostic

Alert rules use exact and estimated session windows. Stale and unavailable
snapshots remain visible for context and troubleshooting.

## Codex Integration

PromptJuice launches the local `codex app-server` over stdio, completes its
initialization handshake, and calls `account/rateLimits/read`.

The response maps into PromptJuice as follows:

- `rateLimitsByLimitId["codex"]` supplies the preferred bucket when present.
- `rateLimits` supplies the compatible single-bucket fallback.
- `primary` becomes the displayed session window.
- A valid `secondary` bucket becomes the retained weekly window.
- `rateLimitReachedType` is preserved as status detail.

The last-good normalized session and weekly windows are cached in local user
defaults until their respective reset times.

## Claude Integration

PromptJuice reads Claude through two local paths:

- Claude Code's built-in `/usage` screen for exact plan windows.
- Local Claude activity metadata under `CLAUDE_CONFIG_DIR`,
  `~/.config/claude/projects`, or `~/.claude/projects` for estimates.

The direct path verifies the Claude Code version and subscription authentication,
then uses a bounded pseudo-terminal session in a dedicated empty workspace. The
probe sends `/usage`, parses quota rows, sends zero model prompts, and records
typed lifecycle outcomes. A persisted scheduler controls freshness, coalescing,
attempt budgets, and rate-limit cooldowns.

The local-log reader decodes a narrow usage-only projection, groups activity into
five-hour blocks, and marks the result as an estimate.

The last-good normalized Claude windows are cached in local user defaults until
their reset times.

## Privacy Posture

All PromptJuice processing and caches live on the user's Mac:

- Codex rate limits come from the local Codex app-server process.
- Claude exact windows are derived from the transient `/usage` parser boundary.
- Claude estimates read activity metadata needed for the active window.
- Cached snapshots contain normalized usage windows and update times.
- PromptJuice includes zero analytics and zero hosted backend.

## Current Preview Behavior

- Runs as a macOS accessory app with a menu-bar droplet.
- Shows Claude and Codex session rows in the Juice Bar.
- Uses live providers in the app and fixture providers in tests and previews.
- Displays source confidence through row details and tooltips.
- Opens the Juice Bar from the menu-bar droplet or a notification tap.
- Supports anchored, pinned, and draggable panel behavior.
- Uses native notifications for the orange use-soon window.

## Development

Build and run:

```bash
./scripts/run_app.sh
```

Run tests:

```bash
swift test
```
