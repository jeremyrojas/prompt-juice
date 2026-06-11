# PromptJuice Plan

This plan starts after the first GitHub push of the working prototype.

## North Star

PromptJuice is a tiny Mac-native Juicebar that answers one question:

> How much useful AI capacity is left, and should I use it before reset?

The product surface should stay small. The internals should be ready for real providers, trustworthy alerts, and future Claude, Codex, Cursor, and agent-tool integrations.

## Immediate Goal

Preserve the current prototype as the baseline, then build a principled foundation before live provider work.

Recommended branch after push:

```bash
codex/architecture-foundation
```

## Phase 0: Baseline Push

Status: current prototype baseline.

Checklist:

- Push current app, docs, design board, and build scripts.
- Confirm `README.md` explains how to run the prototype.
- Keep screenshots and design artifacts in `design/assets/`.
- Capture known rough edges in GitHub issues after the repo exists.

Acceptance criteria:

- A fresh clone can build and run the demo Juicebar.
- Product direction is readable from `README.md`, `PLAN.md`, and `docs/`.
- The current visual prototype is preserved before major refactors.

## ✅ Phase 0.5: MVP Closeout

Goal: finish the static prototype so it feels complete enough to preserve as the baseline.

Status: ✅ implemented and verified in the prototype.

Keep:

- Menu-bar app.
- Top-center Juicebar.
- Expanded alert state.
- Static Claude and Codex values.
- Static reset countdown.
- Manual menu-bar trigger.
- Demo state cycling.
- Minimal threshold settings.
- Native notification permission and one demo notification.
- Real Snooze behavior.
- App icon and control accessibility polish.

Defer:

- Collapsed pill state.
- Charts and history.
- Workflow buttons.
- Full settings window.
- Real provider connections.
- Source freshness/details UI.
- Provider architecture refactor.

Acceptance criteria:

- Clicking Claude/Codex updates the title and detail.
- Clicking Snooze shows brief confirmation, hides the Juicebar, and keeps the demo window quiet.
- Clicking X closes the Juicebar.
- Basic threshold settings affect demo alert behavior.
- Demo notification path works after permission.
- Computer Use verifies live Juicebar state; macOS Accessibility/CoreGraphics operate and verify Juicebar and menu-bar controls.
- `swift build` and `xcodebuild -scheme PromptJuice -destination 'platform=macOS' build` pass.

## Phase 1: Architecture Foundation

Goal: make the app ready for real providers while preserving the current UI.

Phase 1A status on `codex/architecture-foundation`: the small provider boundary,
domain snapshot model, and alert engine are in place. Demo behavior still drives
the Juicebar while Codex live access remains a follow-up spike.

Core model work:

- ✅ Add `RateWindow`.
- ✅ Add `ProviderSnapshot`.
- ✅ Add `ProviderIdentity`.
- ✅ Add `SnapshotSource`.
- ✅ Add `SnapshotConfidence`.
- ✅ Represent exact, estimated, stale, and unavailable snapshot states.
- ✅ Keep reset-window tracking through normalized snapshot window IDs.

Provider layer:

- ✅ Define `UsageProviderClient`.
- ✅ Move demo data behind `DemoProviderClient`.
- ✅ Prepare safe shell for `CodexProviderClient`.
- Make provider clients async when live reads need it.
- Make every provider return normalized snapshots.
- Add `ClaudeProviderClient` with the Claude phase.

Alert layer:

- ✅ Move alert decisions out of `PromptJuiceViewModel`.
- ✅ Add `AlertEngine`.
- ✅ Add threshold rules.
- ✅ Add stale-data suppression.
- Preserve current demo-window Snooze behavior.
- Add snooze per provider reset window once live providers ship.
- Add quiet-hours shape, even if the setting ships later.

State layer:

- ✅ Keep the existing small settings store for thresholds and demo snooze state.
- ✅ Persist snooze and dismiss state for the current demo reset window.
- Cache last-good provider snapshots.
- Keep the storage format simple until live providers prove the final shape.

UI boundary:

- Keep `PromptJuiceViewModel` focused on presentation state.
- Keep `JuicebarPanelController` focused on window placement and visibility.
- Keep `PromptJuicePanelView` focused on rendering and user actions.
- Move business rules into domain services.

Tests:

- ✅ Alert threshold tests.
- ✅ Snooze-window tests.
- ✅ Snapshot stale/confidence tests.
- ✅ Demo provider tests.
- ✅ Codex shell tests.
- Reset countdown tests.

Acceptance criteria:

- ✅ The current demo UI behaves the same after the refactor.
- ✅ Alert rules can be tested in pure XCTest.
- ✅ Provider snapshots can represent exact, estimated, stale, and unavailable states.
- ✅ Real Codex work can start from `CodexProviderClient`.

## Phase 2: Local Behavior

Goal: make the demo app behave like a real assistant before account integration.

Features:

- Real snooze timer for the current reset window.
- Native notification permission flow.
- Local alert persistence.
- Manual refresh state.
- Source freshness display.
- Last updated text in a small details view.
- Basic settings for threshold and quiet hours.

Acceptance criteria:

- Dismissed or snoozed alerts stay quiet for the intended window.
- Alerts fire once per threshold crossing.
- The user can see whether data is fresh, stale, estimated, or unavailable.

## Phase 3: Codex Provider Spike

Goal: find the cleanest path to real Codex usage and reset data.

Investigation:

- Detect `CODEX_HOME`.
- Inspect local Codex auth/session files.
- Investigate `codex app-server` for account and rate-limit data.
- Read local Codex JSONL sessions for history and cost context.
- Document which fields are exact provider data and which fields are estimates.

Implementation:

- Add `CodexProviderClient`.
- Return normalized `ProviderSnapshot`.
- Cache last-good Codex snapshot.
- Surface source and confidence in the UI.

Acceptance criteria:

- PromptJuice can show a real Codex reset window or clearly labeled fallback.
- Local history/cost data never pretends to be exact remaining quota.
- Provider failure produces a calm, inspectable state.

## Phase 4: Claude Provider

Goal: add Claude usage with a clear confidence ladder.

Investigation:

- Identify provider-reported usage options.
- Inspect Claude Code local usage/status paths.
- Evaluate ccusage-style local logs for 5-hour block context.
- Define exact versus estimated usage states.

Implementation:

- Add `ClaudeProviderClient`.
- Add 5-hour window support.
- Add source confidence labels.
- Keep credentials in Keychain when credentials are required.

Acceptance criteria:

- Claude appears in the Juicebar with trustworthy source labeling.
- Local-log estimates are visibly marked as estimates.
- Alert behavior matches Codex behavior.

## Phase 5: Distribution And OSS

Goal: make the project useful and trustworthy for other users.

Work:

- Add license.
- Add contribution notes.
- Add privacy/local-first docs.
- Add Homebrew cask plan.
- Add signed/notarized build plan.
- Add GitHub Sponsors link when ready.
- Add issue templates for provider bugs and quota-source reports.

Business stance:

- Open source for trust and adoption.
- Monetize convenience and support: signed builds, sponsors, sponsorware, or optional Pro features.
- Keep the core local engine auditable.

## What To Avoid

- Provider sprawl before Claude and Codex are solid.
- Dashboard-first UI.
- Hidden web scraping.
- Quota guesses displayed as facts.
- Repeated alerts inside the same reset window.
- Large abstractions before the second real provider proves the need.

## Next Action After GitHub Push

Create the architecture branch and start with model extraction:

1. Add `RateWindow` and snapshot source/confidence types.
2. Update demo snapshots to use the new model.
3. Add `AlertEngine` with tests.
4. Add local alert-window persistence.
5. Keep the Juicebar UI visually stable throughout.
