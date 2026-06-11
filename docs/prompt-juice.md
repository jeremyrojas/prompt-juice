# PromptJuice

PromptJuice is a tiny macOS menu-bar app with a top-center Juicebar that shows how much Claude and Codex usage is left before the current limit window resets. It gives a well-timed nudge when valuable AI capacity is about to expire.

Tagline:

> See how much AI usage you have left before it resets.

## Product Idea

Prompt juice means remaining AI capacity: the Claude/Codex usage still available in the current reset window.

The app watches usage windows, reset times, and current usage. When the user has meaningful capacity left near the end of a window, PromptJuice drops a small Juicebar alert with a Snooze action.

Example:

```text
Codex resets in 52m
You have used 38%

Snooze
```

## Core Use Case

The user is deep in work and may forget to use available Claude or Codex limits. PromptJuice acts like a gentle capacity coach:

- "You have useful AI capacity left."
- "The reset window is close."
- "This is a good moment to use Claude or Codex."

## MVP Direction

The first MVP should focus on proving the feel of the Juicebar interaction.

### ✅ Phase 0: Static Juicebar Prototype

Goal: make the product feel real on macOS with simulated usage data.

Status: ✅ implemented and verified in the native prototype.

Features:

- Native macOS menu-bar app.
- Top-center Juicebar floating panel.
- Expanded alert state.
- Static Claude and Codex usage values.
- Static reset countdown.
- Manual trigger for alert states.
- Snooze button.
- Simple settings for thresholds.
- Optional demo mode that cycles through alert examples.

This phase validates:

- Does the Juicebar shape feel good?
- Does the alert appear at the right size and location?
- Does the product feel useful with minimal information?
- Does Snooze feel obvious?
- Does the app stay out of the way?

### Phase 1: Local State and Alert Logic

Goal: make the static prototype behave like a real usage assistant with local data.

Features:

- Local SQLite or JSON store.
- Usage window model.
- Alert rule engine.
- Snooze and quiet hours.
- Menu-bar quick view.
- Configurable alert thresholds.
- Demo providers with scripted data.

Core alert rule:

```text
remaining_minutes <= 60
and remaining_percent >= 40
and alert_pending_for_window
```

Better pacing rule:

```text
elapsed_percent = elapsed_window_minutes / total_window_minutes
underuse_gap = elapsed_percent - used_percent

show "Use soon" when:
remaining_minutes <= 60
and remaining_percent >= 40
```

### Phase 2: Codex Connection

Goal: read real Codex rate-limit state.

Likely integration path:

- Start or connect to local `codex app-server`.
- Use account/rate-limit methods exposed by the Codex app-server.
- Subscribe to rate-limit updates when available.
- Store minimal connection state locally.
- Use macOS Keychain for sensitive credentials or tokens.

Expected data:

- Remaining percent or remaining units.
- Reset time.
- Model or window type.
- Account/workspace identity where available.

### Phase 3: Claude Connection

Goal: read real Claude usage state.

Possible integration paths:

- Browser/session-based Claude usage endpoint, similar to existing OSS apps.
- Claude Code local status or hooks.
- `ccusage` as a local helper for CLI-derived usage history.
- macOS Keychain for sensitive session data.

Expected data:

- Current 5-hour usage window.
- Weekly or model-specific windows when available.
- Reset time.
- Account/org identity where available.

## UI/UX Notes

PromptJuice should feel like a native macOS utility from the first prototype. The interaction should feel calm, fast, and system-level: a small menu-bar presence, a top-center Juicebar surface, native notifications, native typography, subtle materials, and very little visual noise.

Design principles:

- Use macOS-native controls and spacing.
- Keep the default state tiny.
- Favor glanceable usage and reset time over charts.
- Make alerts useful in under two seconds.
- Make snooze easy.
- Keep actions optional and configurable.
- Preserve focus while the user is working.

Liquid-glass direction:

- Rounded all-corners Juicebar surface with a compact top-center footprint.
- Translucent material layers, soft edge highlights, and a subtle top-left sheen.
- Provider rows as glass insets with a thin capacity bar instead of charts.
- Status chips for quick scanning: `Use soon`, `Lots left`, `Some left`, `Low`, `Empty`.
- Monospaced countdown digits so usage values stay steady while ticking.
- Provider-aware header: clicking Claude or Codex updates the title and detail for that provider.

### Visibility Model

The Juicebar should be alert-only by default, with manual access from the menu bar.

- Quiet state: only the menu-bar icon is visible.
- Manual check: clicking the menu-bar icon opens the Juicebar with current Claude and Codex usage.
- Alert state: the Juicebar drops down automatically when the alert rule fires.
- Snooze or dismiss: the Juicebar hides and remembers the snooze for the current usage window.
- No charts in the MVP: show provider, percent used, reset countdown, remaining juice, and Snooze.

### Default State

The default experience should be very small.

```text
PromptJuice
Claude 47% · 48m
Codex 31% · 52m
```

### Juicebar Alert

The alert should feel like a native system surface:

- Top-center anchored panel.
- Rounded glass shape.
- Soft shadow.
- Light blur, vibrancy, and edge sheen.
- Small text.
- Clear green/yellow/red status color.
- Short copy.
- One-click Snooze.

Example alert copy:

```text
Codex: 69% to use
52m before reset

Snooze
```

### Tone

The app should feel playful and useful.

Possible strings:

- "Plenty of prompt juice left."
- "This window still has juice."
- "Use it before reset."
- "Good time to launch agents."
- "Codex has room for more work."
- "Claude still has capacity."

## Technical Recommendation

Recommended stack:

- Swift.
- AppKit for the Juicebar panel and window behavior.
- SwiftUI for simple settings and preference panes.
- `NSStatusItem` for menu-bar presence.
- Borderless floating `NSWindow` for the Juicebar UI.
- `UserNotifications` for system notifications.
- Keychain for secrets.
- SQLite or a small local JSON store for early prototypes.

Research note:

- OSS usage tools synthesis: [oss-usage-tools-research.md](oss-usage-tools-research.md)

Why Swift/AppKit:

- Best fit for native Juicebar/menu-bar UX.
- Precise control over top-level panels.
- Lower idle overhead.
- Easy access to macOS notifications, Keychain, accessibility, and launch-at-login APIs.
- Strong path to a polished Mac utility.

## App Architecture

Suggested modules:

- `PromptJuiceApp`: app entry point and menu-bar setup.
- `JuicebarPanelController`: floating panel placement and presentation.
- `UsageProviderClient`: provider boundary for normalized Claude, Codex, and demo snapshots.
- `RateWindow`: shared model for percent used, percent left, reset time, duration, and window label.
- `ProviderSnapshot`: normalized provider state with identity, source, confidence, freshness, and error state.
- `AlertEngine`: pacing and threshold logic.
- `ActionLauncher`: launches user-configured workflows.
- `SettingsStore`: local preferences.
- `CredentialStore`: Keychain wrapper.

Provider protocol sketch:

```swift
protocol UsageProviderClient {
    var source: SnapshotSource { get }
    func snapshots(now: Date) -> [ProviderSnapshot]
}
```

Usage model sketch:

```swift
struct ProviderSnapshot {
    let identity: ProviderIdentity
    let rateWindow: RateWindow
    let source: SnapshotSource
    let confidence: SnapshotConfidence
    let updatedAt: Date
}

enum SnapshotConfidence {
    case exact
    case estimated
    case stale
    case unavailable
}
```

### Phase 1A Implementation

The architecture branch adds the first provider-ready slice while keeping the
Juicebar UI visually stable:

- `RateWindow`, `ProviderIdentity`, `ProviderSnapshot`, `SnapshotSource`, and `SnapshotConfidence` model normalized provider state.
- `UsageProviderClient` defines the provider boundary.
- `DemoProviderClient` supplies the existing static Claude and Codex rows through that boundary.
- `CodexProviderClient` is a safe shell that returns an unavailable Codex snapshot. It performs zero token refresh, auth-file mutation, browser-cookie reads, secret storage, or live account access.
- `AlertEngine` owns current `Use soon` threshold decisions and suppresses stale or unavailable snapshots.
- `PromptJuiceViewModel` keeps presentation state, formatting, selection, Snooze, and threshold actions.

Next Codex spike:

- Use `codex app-server` as the primary read-only integration path.
- Prefer `account/rateLimits/read` provider data for reset and
  remaining-capacity state.
- Label estimates and stale data clearly.
- Cache the last good snapshot after the live source shape is proven.

### Phase 1B Codex Integration Plan

Official Codex docs describe `codex app-server` as the interface for deep
product integrations. The rate-limit method returns `usedPercent`,
`windowDurationMins`, `resetsAt`, `rateLimitReachedType`, and optional
`rateLimitsByLimitId` buckets. That maps directly onto the Phase 1A
`RateWindow` and `ProviderSnapshot` types.

Primary source:

- `codex app-server` over local stdio or a local Unix socket.
- JSON-RPC handshake: `initialize`, `initialized`.
- Read method: `account/rateLimits/read`.
- Bucket priority: `rateLimitsByLimitId["codex"]`, then `rateLimits`.
- Snapshot confidence: `.exact` for complete provider fields,
  `.unavailable` for absent/unreadable app-server state, `.stale` for cached
  last-good data after freshness expires.

Implementation slices:

1. `CodexAppServerClient`
   - Launch or connect to app-server.
   - Send the initialization handshake with PromptJuice client metadata.
   - Send `account/rateLimits/read`.
   - Handle request IDs, response matching, timeout, process cleanup, and
     structured provider errors.
2. `CodexRateLimitResponse`
   - Decode single-bucket and multi-bucket responses.
   - Map `primary.usedPercent`, `primary.windowDurationMins`, and
     `primary.resetsAt` into `RateWindow`.
   - Preserve `rateLimitReachedType` for future UI detail.
3. `CodexProviderClient`
   - Return normalized Codex snapshots from the app-server client.
   - Keep current unavailable shell behavior as the fallback.
   - Add last-good snapshot caching after the exact path is verified.
4. UI/settings
   - Add a small source selector or developer toggle for Demo vs Live Codex.
   - Surface source/confidence/freshness in compact detail text.
   - Keep provider row interactions, Snooze, thresholds, and alert copy stable.
5. Tests and smoke
   - Parser fixture tests for backward-compatible and multi-bucket payloads.
   - Provider tests for exact, unavailable, stale, malformed, and timeout paths.
   - View-model tests for live Codex display and fallback behavior.
   - Manual smoke with app-server available, absent, and timing out.

Safety rules:

- Read rate-limit state only.
- Skip login/logout, auth mutation, token refresh, browser cookies, and secret
  storage.
- Treat `CODEX_HOME` JSONL history as optional estimated context.
- Store last-good snapshots and freshness metadata only.
- Keep live Codex behind an explicit local setting until the smoke path feels
  reliable.

Provider strategy:

- Use provider-reported quota/reset data when available.
- Use local CLI/session state as a fallback.
- Use local log-derived estimates for history and low-confidence usage context.
- Cache the last good snapshot and label stale data clearly.

Provider order:

1. Codex first: investigate local `codex app-server` for current quota/reset state, with `CODEX_HOME` JSONL for history and cost context.
2. Claude second: use provider/CLI usage when available, with ccusage-style local logs for 5-hour block context and estimates.
3. Cursor later: defer until the privacy and setup flow for cookie/session-style integrations feels mature.

## Initial Prototype Behavior

The first build can use demo data:

```text
Claude: 44% used, resets in 58m
Codex: 31% used, resets in 52m
```

Demo alert examples:

- Codex underused near reset.
- Claude underused near reset.
- Both providers healthy.
- Quiet state.
- Snoozed state.

Manual controls:

- Show alert.
- Hide alert.
- Cycle provider state.
- Toggle demo mode.

## Snooze and Clicks

Initial MVP actions:

- X closes the visible Juicebar.
- Snooze pauses reminders for the current usage window.
- Provider rows are clickable and update the title/detail.
- Juice bars are clickable and update the title/detail.

Later configurable shortcuts can live in settings after the core usage check feels clear.

## Important Considerations

- Credentials must live in Keychain.
- Account connection should be explicit and inspectable.
- The UI should reveal only the minimum useful data.
- Every snapshot should show freshness and source confidence somewhere in the details view.
- Provider failures should degrade gracefully.
- Alert frequency needs strong anti-spam behavior.
- Quiet hours and snooze are core quality-of-life features.
- Snooze and alert history should be tracked per provider reset window.
- The app should make local-only behavior clear.
- Launch-at-login can come after the prototype feels right.
- Real account integration should follow the static prototype.

## Open Questions

- Should the app name stay PromptJuice?
- Should the icon look like a droplet, battery, prompt cursor, or Juicebar?
- What is the cleanest Codex connection path: `codex app-server`, local auth/session files, or a hybrid?
- Which Claude source should be treated as primary once provider-reported usage is available?
- Should future shortcuts launch terminal commands, Codex threads, or reusable workflow templates?
- Should the app support multiple accounts in v1?
- Should the Juicebar appear only on built-in displays, or also external monitors?

## ✅ Phase 0 MVP Closeout

Completed:

1. Stabilize click behavior and Juicebar sizing.
2. Make Snooze confirm briefly, hide the Juicebar, and stay quiet for the current demo reset window.
3. Add a minimal threshold settings surface for remaining minutes and remaining percent.
4. Add native notification permission flow and one demo notification path.
5. Add keyboard/accessibility labels for the primary controls.
6. Add a simple app icon and improve the menu-bar icon if needed.
7. Verify the real macOS app with Computer Use.

This is the clean prototype checkpoint before the architecture foundation work.

Deferred from Phase 0:

- Collapsed pill state.
- Charts and history views.
- Workflow launch buttons.
- Full settings/preferences window.
- Real Codex, Claude, or Cursor account connections.
- Source freshness and confidence details.
- `RateWindow`, `ProviderSnapshot`, and `AlertEngine` refactor.

Those belong in Phase 1 and later.

## Suggested Next Step

Start Phase 1 architecture foundation after the first GitHub push.

## Prototype Status

Current implementation:

- Swift package rooted at the project folder.
- Native macOS accessory app.
- Menu-bar droplet icon.
- Top-center borderless `NSWindow` rounded Juicebar surface.
- SwiftUI panel content inside native AppKit windowing.
- Static Claude and Codex demo usage values.
- Remaining-capacity bars with green/orange/red status color.
- Compact provider status chips (`Use soon`, `Lots left`, `Some left`, `Low`, `Empty`).
- Provider rows are clickable and update the panel headline/detail.
- Snooze briefly confirms, hides the Juicebar, and suppresses the current demo reset window.
- Liquid-glass panel treatment with translucent material, highlight strokes, and soft glow.
- Cursor-aware screen placement for multi-display setups.
- Demo alert on launch.
- Manual usage check from menu-bar click.
- Right-click menu-bar controls for demo state, thresholds, notifications, and quit.
- Minimal threshold settings for remaining minutes and remaining percent.
- Native notification permission and demo notification path.
- Accessibility labels for menu-bar, close, provider rows, and Snooze controls.
- Simple generated app icon included in bundle builds.
- Local app bundle build script at `scripts/build_app.sh`.
- Run script at `scripts/run_app.sh`.
- Current UI screenshot: `design/assets/prompt-juice-final-crop.png`.
- Imagegen mood mockup: `design/assets/prompt-juice-imagegen-mood.png`.
- Usage state board: `design/prompt-juice-states.html`.

Validated:

- `swift build`
- `swift test`
- `scripts/build_app.sh`
- `xcodebuild -scheme PromptJuice -destination 'platform=macOS' build`
- Computer Use readback for live Juicebar state.
- macOS Accessibility/CoreGraphics smoke tests for Juicebar and menu-bar controls.

Near-term polish:

- Tune Juicebar sizing against built-in and external displays.
- Add short screen recordings to `design/assets/`.

Deferred polish:

- Collapsed pill state.
- Source freshness and confidence fields.
- Tiny details view for source freshness and last update.
- Provider architecture refactor.
