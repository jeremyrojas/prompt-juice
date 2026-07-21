# Claude `/usage` Integration and Bridge Retirement Plan

> [!IMPORTANT]
> **Superseded decisions.** The binding implementation specification is
> `docs/claude-usage-ui-implementation.md`, with the goal prompt taking precedence where it
> differs. It retires the earlier minimum Claude Code 2.1.181 decision in favor of 2.1.208,
> the classic-TUI fallback, the v1 Advanced source/cadence controls, `updateRecommended`,
> bridge `needsReview`, and the earlier connection/state models. Implementation follows the
> binding access/refresh/snapshot/migration axes and the capture and reference policies recorded
> in that specification.

Status: implementation plan only  
Worktree: `/Users/jeremyrojas/worktrees/prompt-juice/claude-usage`  
Branch: `codex/claude-usage`  
Base: `origin/main` at `4d349d1`  
Last reviewed: 2026-07-19

## Mandatory UI verification with Computer Use

Every implementation slice that changes user-visible SwiftUI or AppKit behavior must be tested
in the running PromptJuice macOS app with the `@Computer` Computer Use plugin. Exercise every
affected state, action, transition, sheet, popover, tooltip, and Settings row that the slice
changes. Verify the rendered copy, layout, button behavior, focus/activation behavior, and the
specified normal and enlarged-text presentation.

Record the states exercised and retain screenshot or app-state evidence in the slice report.
Automated unit, matrix, and snapshot tests remain required. A UI-changing slice is complete
only after its automated checks pass and Computer Use verification passes. When an account,
permission, login, or other consequential user action is required, stop at the handoff point
and follow the Computer Use confirmation policy; use deterministic fixtures or preview/test
states for the remaining visual coverage.

## Decision

Make the official Claude Code `/usage` command PromptJuice's primary source for Claude subscription quota. Stop offering the status-line bridge to new users. Retain the bridge reader temporarily as a dogfood fallback, provide a safe removal path for existing installations, then delete the bridge implementation before the first broadly downloadable release if the `/usage` gates pass.

The bridge's remaining benefit is structured, near-real-time data during active Claude Code sessions. PromptJuice's product requirements are satisfied by a real launch/manual refresh, a smart 5–15 minute background cadence, last-good data, and local estimates. `/usage` removes the required `~/.claude/settings.json` mutation and the requirement to send a Claude Code message before PromptJuice can initialize.

## Product behavior

### Subscription users

- Claude Code installed and signed in: PromptJuice works automatically.
- Claude Desktop activity counts toward the same Claude subscription allowance; `/usage` reads that shared allowance through the separately installed Claude Code CLI.
- Claude Desktop with no macOS Claude Code CLI: PromptJuice shows one clear enablement action for installing and signing in to Claude Code.
- Signed-out Claude Code: PromptJuice shows a sign-in action and keeps any valid last-good reading visible.

### API/Console-billed users

- `/usage` reports current-session token/cost information for API users; it is not an organization-wide API spend report.
- Anthropic documents possible background request/token consumption from commands such as `/usage`. Automatic plan-quota polling must remain disabled for API-billed authentication.
- PromptJuice continues to use local Claude activity/cost information where available.
- Organization-wide Anthropic API usage is a separate future integration through Anthropic's Admin Usage API and a user-provided Admin API key.

### Explicit exclusions

- Never send `hi` or any other synthetic model prompt.
- Never collect, copy, display, or log OAuth tokens, browser cookies, API keys, prompts, code, or raw transcripts.
- Never perform Claude login inside PromptJuice. Hand authentication to the official Claude Code CLI.
- Defer direct calls to the internal `api/oauth/usage` and Claude web-session endpoints.
- Defer Mac App Store sandbox accommodation; this implementation targets the direct signed/notarized build.

## Target source ladder

During dogfooding:

1. Fresh Claude CLI `/usage` snapshot.
2. Fresh legacy bridge snapshot when the PTY probe fails.
3. Last-good exact Claude snapshot that remains inside its reset window.
4. Local Claude project-log estimate.
5. An unavailable snapshot with a precise connection, compatibility, rate-limit, or execution reason.

After bridge retirement:

1. Fresh Claude CLI `/usage` snapshot.
2. Last-good exact Claude snapshot that remains inside its reset window.
3. Local Claude project-log estimate.
4. Precise unavailable state.

## Proposed domain model

### Snapshot source

Add `SnapshotSource.claudeCLIUsage`. Keep `.claudeStatusline` only through the transition. Rename the cache implementation from bridge-specific naming to source-neutral Claude exact-usage naming so the last-good cache accepts exact CLI snapshots.

### User preference

Add a Claude-specific preference:

```swift
enum ClaudeUsageSourcePreference: String, CaseIterable {
    case automatic
    case cliUsage
    case localOnly
    case disabled
}
```

`automatic` is the default. During the transition it may consume bridge data as a fallback. `cliUsage` forces the official CLI path. `localOnly` avoids background Claude launches. The existing provider toggle remains the top-level on/off control; the `disabled` enum case may be omitted if that duplication makes Settings less clear.

Add a refresh preference:

```swift
enum ClaudeRefreshCadence: String, CaseIterable {
    case smart
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case manualOnly
}
```

`smart` is the default and uses a 15-minute normal TTL with event-driven checks and adaptive cooldown.

### Connection state

Model connection/setup separately from snapshot confidence:

```swift
enum ClaudeConnectionState: Equatable {
    case checking
    case connectedSubscription(accountLabel: String?)
    case connectedAPIBilling(accountLabel: String?)
    case cliMissing
    case signedOut
    case updateRecommended(installed: String, minimum: String)
    case rateLimited(retryAt: Date?)
    case failed(message: String)
}
```

This replaces the bridge-specific `ClaudeLiveUpgrade` state machine. Snapshot confidence continues to describe exact, stale, estimated, and unavailable data.

## Technical architecture

### New components

Prefer small files with pure parsing separated from process control:

- `app/PromptJuice/Providers/ClaudeExecutableLocator.swift`
  - Resolve `PROMPTJUICE_CLAUDE_PATH` for tests/advanced overrides.
  - Reuse or extract the safe PATH enrichment logic currently embedded in `CodexExecutableLocator`.
  - Reject directories and non-executable files.
- `app/PromptJuice/Providers/ClaudeAuthProbe.swift`
  - Run `claude auth status` and decode the current JSON schema.
  - Return connection state without exposing secrets.
  - Distinguish subscription, API/Console billing, and signed-out states using verified fixture fields.
- `app/PromptJuice/Providers/ClaudeCLIVersion.swift`
  - Parse `claude --version` semantically.
  - Use `--safe-mode` from its supported version onward.
  - Use `--ax-screen-reader` from Claude Code 2.1.181 onward.
  - Use a regular PTY renderer on older supported builds.
- `app/PromptJuice/Providers/ClaudePTYSession.swift`
  - Own `openpty`, process group, bounded reads, timeout, cancellation, terminal-size responses, and cleanup.
  - Use a dedicated PromptJuice probe directory with mode `0700`.
  - Persist one stable probe session UUID with mode `0600` so repeated launches avoid registering fresh empty sessions.
  - Set `DISABLE_AUTOUPDATER=1` in the child environment.
  - Start with `--allowed-tools ""` and a stable `--session-id`.
  - Add `--safe-mode` and `--ax-screen-reader` when supported.
  - Send the built-in `/usage` command only.
  - Cap captured output and kill the entire process group on timeout or app termination.
- `app/PromptJuice/Providers/ClaudeUsageOutputParser.swift`
  - Pure, fixture-driven parser.
  - Strip ANSI/control sequences and tolerate flat or fullscreen TUI rendering.
  - Parse the five-hour session window, seven-day window, model-specific weekly windows when present, reset times, plan/account labels, last-known `as of` timestamps, subscription-only notices, loading states, and rate-limit messages.
  - Choose the latest complete Usage panel when startup fragments or repeated redraws appear.
  - Return typed parse failures rather than user-facing strings.
- `app/PromptJuice/Providers/ClaudeUsageProbe.swift`
  - Resolve executable, check version/authentication, run `/usage`, retry once after startup-only output, parse the result, and map it to `ProviderSnapshot`.
  - Avoid `/statusline` and synthetic prompts.
- `app/PromptJuice/Providers/ClaudeUsageCoordinator.swift`
  - Actor that owns coalescing, cache TTL, cooldown, last attempt/success, session reuse, and connection state.
  - Expose an async `snapshot(now:reason:force:)` entry point.
  - Keep PTY work away from the main actor.
- `app/PromptJuice/Providers/ClaudeUsageSchedule.swift`
  - Pure policy for deterministic scheduler tests.
  - Decide when launch, wake, foreground, panel-open, manual, reset-boundary, and timer events should probe.

### Concurrency integration

Keep the existing synchronous `UsageProviderClient` protocol for fixture/local/cache readers. Add an async Claude-specific protocol rather than blocking an actor behind a semaphore:

```swift
protocol ClaudeUsageSnapshotProviding: Sendable {
    func snapshot(now: Date, reason: ClaudeRefreshReason, force: Bool) async -> ProviderSnapshot
}
```

Update `PromptJuiceViewModel.startLiveProviderRefresh` to await the Claude coordinator while the existing Codex client runs in the sibling task-group entry. Preserve the current behavior where Codex can merge before a slower Claude refresh finishes. Inject a stub async Claude provider in tests.

Use the current synchronous `ClaudeProviderClient` as the transition fallback aggregator, or split its statusline and local-log readers into reusable fallback components. Remove `ClaudeLiveUsageProviderClient` once the view model owns concurrent Claude/Codex refresh directly.

### Launch arguments and compatibility

Preferred current invocation shape:

```text
claude --safe-mode --ax-screen-reader --allowed-tools "" --session-id <stable-uuid>
```

The command remains interactive because `/usage` is an interactive built-in. PromptJuice writes `/usage` after the prompt is ready. Version checks come from `claude --version`; the official documentation warns that `claude --help` omits some supported flags.

For versions below the flat-renderer minimum, use the regular PTY capture and terminal normalization. A later implementation spike may set a higher minimum if maintaining both renderers proves disproportionate.

### Probe working directory and artifacts

Use `~/Library/Application Support/PromptJuice/ClaudeProbe/` for the stable session ID and probe-owned files. Use a neutral empty working directory so repository trust prompts and project configuration stay outside the probe. Clean only artifacts whose paths and session IDs PromptJuice owns.

The probe should avoid polluting Claude's prompt history where a verified official environment setting supports that behavior. Verify the installed Claude Code behavior before relying on the setting.

### Logging and privacy

Log:

- executable resolution outcome;
- Claude version and selected compatibility flags;
- normalized auth category;
- refresh reason;
- cache hit/miss;
- probe duration;
- parse result category;
- cooldown start/end;
- snapshot source/confidence.

Exclude raw PTY output in production logs. Permit an explicit debug-only redacted dump to a PromptJuice-owned path for parser troubleshooting. Apply a size limit and remove email/account labels from dumps.

## Smart refresh and cooldown policy

### Success TTL

- Default automatic TTL: 15 minutes.
- Manual refresh performs a real probe when the last attempt is older than 60 seconds and no cooldown is active.
- Panel open, app foreground, and wake probe only when the successful reading is stale.
- Reset-boundary events may probe after the prior window expires.
- Fresh transition bridge data suppresses a scheduled PTY probe during dogfooding only when explicitly testing fallback behavior; normal dogfood builds should prefer the CLI so it receives real coverage.

### Global limits

- One in-flight Claude probe.
- Coalesce all pending refresh reasons.
- Persist the last attempt time so rapid app relaunches cannot hammer Claude.
- Smart automatic budget: approximately four probes per hour.
- Combined automatic/manual safety budget: approximately six probes per hour.
- Sleep, offline, disabled-provider, API-billing, and manual-only modes skip automatic probes.

### Rate limiting

- Detect HTTP/usage rate-limit language rendered by `/usage`.
- Honor a visible retry time or `Retry-After` equivalent when Claude exposes one.
- Fallback cooldown sequence: 5, 15, 30, then 60 minutes.
- Keep showing last-good data with its source time.
- Reset cooldown after a successful probe or authentication change.
- Manual refresh during cooldown shows the cached reading and retry time.
- Parse Claude's last-known `/usage` bars and `as of` timestamp as stale exact data when available.

### API-billing guard

When authentication resolves to API/Console billing:

- skip scheduled `/usage` probes;
- retain local estimates/costs;
- explain that organization totals live in the Claude Console;
- reserve an explicit future Admin API connection for organization-wide usage.

## Implementation slices

Each slice should remain independently testable and reviewable.

### Slice 0 — Baseline and safe fixtures

1. Run the full Swift test suite and ShellCheck from the fresh worktree.
2. Record the exact current test count.
3. Add sanitized fixtures for current flat `/usage`, classic TUI `/usage`, cached/rate-limited `/usage`, subscription notice, API-billing session view, signed-out startup, trust/onboarding prompt, and malformed/partial output.
4. Obtain any live fixture only with Jeremy's explicit approval because Anthropic documents possible background request/token use.
5. Keep real account identifiers and reset timestamps out of committed fixtures.

Gate: fixture provenance is documented and contains no credentials or personal identifiers.

### Slice 1 — Models, preferences, and exact-cache generalization

Files:

- `app/PromptJuice/Models/SnapshotSource.swift`
- new Claude preference/connection-state files under `Models/`
- `app/PromptJuice/Services/PromptJuiceSettingsStore.swift`
- `app/PromptJuice/Providers/ClaudeProviderClient.swift`
- provider/cache tests

Tasks:

- Add `.claudeCLIUsage`.
- Add source/cadence preferences with migrations/defaults.
- Generalize `ClaudeSnapshotCache` so exact CLI snapshots are saved.
- Preserve current bridge snapshot decoding during transition.
- Add deterministic settings migration tests.

Gate: existing bridge/local estimate behavior remains green and exact CLI snapshots round-trip through the cache.

### Slice 2 — Executable, version, and auth probes

Files:

- new locator/version/auth files
- extracted shared executable-location helper if warranted
- focused unit tests with fake executables and JSON fixtures

Tasks:

- Resolve the macOS Claude CLI independently of Claude Desktop's embedded Linux VM executable.
- Parse current and older supported version formats.
- Parse `claude auth status` output without retaining secrets.
- Map missing, signed-out, subscription, API billing, and malformed states.

Gate: no network/model call occurs in these tests; every state is fixture-driven.

### Slice 3 — PTY transport and `/usage` parser

Files:

- new PTY/session/parser/probe files
- parser fixtures and PTY fake-process tests

Tasks:

- Implement bounded PTY capture, prompt readiness, command-palette confirmation, cursor-position response, timeout, cancellation, and process-group cleanup.
- Implement pure output parsing.
- Add current safe/flat flags by version.
- Retry once when the first capture contains startup output only.
- Ensure the implementation sends exactly `/usage` and never a model prompt.

Gate: fake CLI integration tests prove launch arguments, one slash command, bounded output, timeout cleanup, and parser behavior.

### Slice 4 — Coordinator, cooldown, and provider ladder

Files:

- new coordinator/schedule files
- `app/PromptJuice/Providers/ClaudeProviderClient.swift`
- `app/PromptJuice/Services/PromptJuiceViewModel.swift`
- `app/PromptJuice/App/AppDelegate.swift`
- scheduler/provider/view-model tests

Tasks:

- Add async Claude coordination to the existing parallel live-provider refresh.
- Coalesce launch, wake, foreground, panel-open, manual, timer, and reset refreshes.
- Persist cooldown and last-attempt metadata.
- Implement transition source ladder.
- Preserve Codex's independent early merge.
- Replace the status-cache watcher as the normal trigger with a Claude refresh scheduler; keep the watcher only for transition bridge fallback.

Gate: deterministic clock tests cover every trigger and cooldown transition; slow Claude never blocks Codex UI updates.

### Slice 5 — UI and Settings migration

Files:

- `app/PromptJuice/Services/PromptJuiceViewModel.swift`
- `app/PromptJuice/UI/PromptJuicePanelView.swift`
- `app/PromptJuice/UI/JuicebarPanelController.swift`
- `app/PromptJuice/UI/SettingsView.swift`
- `app/PromptJuice/UI/SettingsWindowController.swift`
- presentation, click-routing, accessibility, and snapshot tests

Tasks:

- Remove bridge setup as a normal user journey.
- Replace `ClaudeLiveUpgrade` with connection state plus snapshot confidence.
- Make manual Refresh invoke the coordinator.
- Add missing-CLI, signed-out, API-billing, update-recommended, rate-limited, stale, estimated, and exact presentation states.
- Add Claude source and refresh preferences under a compact Advanced disclosure.
- Retain a measurement popover with accurate `/usage`, shared-subscription, local-estimate, and privacy explanations.
- Remove terminal-message/statusline instructions.
- Preserve keyboard navigation, VoiceOver labels, hover behavior, click routing, and the panel's fixed visual rhythm.

Gate: the approved before/after copy matrix is fully represented in unit/snapshot tests and every visible action performs the behavior its label promises.

### Slice 6 — Legacy bridge removal migration

Files:

- replace or extend `app/PromptJuice/Services/ClaudeBridgeInstaller.swift`
- migration tests
- temporary legacy Settings row/sheet

Tasks:

- Detect only the exact PromptJuice-owned installed command/script.
- Parse and restore the delegated previous status-line command when present.
- Remove an additive PromptJuice-owned status-line configuration conservatively.
- Preserve unrelated settings and write atomically.
- Handle the overwritten `refreshInterval` conservatively; its prior value was never saved.
- Delete the installed script only after settings are repaired.
- Leave drifted/ambiguous configurations intact and show a preview/manual instruction.
- Offer cleanup to existing installations during the transition build.

Gate: tests cover additive install, wrapped install, quoted commands, drift, malformed JSON, write failure, missing script, and idempotent cleanup.

### Slice 7 — Dogfood

Run for 3–7 days with the CLI as the preferred source and bridge as fallback only.

Verify:

- launch, panel-open, manual, foreground, wake, reset-boundary, and repeated-relaunch behavior;
- Claude Desktop activity reflected through the same subscription allowance;
- no synthetic messages, unwanted conversations, tool calls, or user-project trust prompts;
- no repeated empty session registrations;
- source logs show real CLI coverage;
- stale/last-good presentation during network errors;
- simulated and real rate-limit handling;
- signed-out and CLI-missing recovery;
- current custom status-line continues working during the transition;
- CPU, memory, process, and wake impact remain appropriate for a menu-bar utility.

Go gate:

- exact reading succeeds reliably on launch/manual refresh;
- parser covers every observed current output;
- cooldown prevents loops;
- process cleanup is reliable;
- the UI never asks the user to send a Claude message;
- existing bridge users have a safe cleanup path.

Fallback gate: retain the bridge as an optional advanced fallback for one transition release if PTY reliability or rate limiting misses the go criteria.

### Slice 8 — Bridge code deletion

After the dogfood go gate:

- remove `ClaudeBridgeInstaller` installation behavior;
- remove `ClaudeStatusCachePoller` and bridge cache watcher paths;
- remove bridge setup/success/disclosure UI and previews;
- remove `scripts/claude-statusline-bridge.sh`;
- remove its copy/chmod steps from `scripts/build_app.sh`;
- remove bridge smoke/installer tests;
- remove or archive `docs/claude-statusline-bridge.md` and the old plutil plan;
- rewrite README, provider integration docs, state/color references, and AI-agent install/update docs;
- rename bridge-specific sources/cache keys where migration compatibility permits;
- retain migration code for one release if external users have installed a bridge.

Gate: repository-wide searches for bridge/statusline user journeys return only intentional historical/migration references.

### Slice 9 — Final verification

- `swift test`
- ShellCheck for remaining shell scripts
- clean debug and release builds
- app bundle inspection confirms bridge script is absent
- manual VoiceOver pass
- screenshots for every Claude UI state
- first-run test with Claude enabled/disabled
- login/install recovery test
- sleep/wake and offline tests
- privacy review of logs, caches, file permissions, and process environment
- README and support troubleshooting validation

## Files expected to change

Core additions:

- `app/PromptJuice/Providers/ClaudeExecutableLocator.swift`
- `app/PromptJuice/Providers/ClaudeAuthProbe.swift`
- `app/PromptJuice/Providers/ClaudeCLIVersion.swift`
- `app/PromptJuice/Providers/ClaudePTYSession.swift`
- `app/PromptJuice/Providers/ClaudeUsageOutputParser.swift`
- `app/PromptJuice/Providers/ClaudeUsageProbe.swift`
- `app/PromptJuice/Providers/ClaudeUsageCoordinator.swift`
- `app/PromptJuice/Providers/ClaudeUsageSchedule.swift`
- corresponding focused test files and sanitized fixtures

Core modifications:

- `app/PromptJuice/Models/SnapshotSource.swift`
- `app/PromptJuice/Providers/ClaudeProviderClient.swift`
- `app/PromptJuice/Services/PromptJuiceSettingsStore.swift`
- `app/PromptJuice/Services/PromptJuiceViewModel.swift`
- `app/PromptJuice/App/AppDelegate.swift`
- `app/PromptJuice/UI/PromptJuicePanelView.swift`
- `app/PromptJuice/UI/JuicebarPanelController.swift`
- `app/PromptJuice/UI/SettingsView.swift`
- `app/PromptJuice/UI/SettingsWindowController.swift`
- presentation/provider/view-model/snapshot/click-routing tests
- `README.md`
- `docs/provider-integrations.md`
- `docs/prompt-juice.md`
- `docs/reference/states-and-colors.md`
- install/update documentation

Transition removals:

- `app/PromptJuice/Services/ClaudeBridgeInstaller.swift`
- `app/PromptJuice/Services/ClaudeStatusCacheChangeTracker.swift`
- `app/PromptJuiceTests/ClaudeBridgeInstallerTests.swift`
- `app/PromptJuiceTests/ClaudeStatusCacheChangeTrackerTests.swift`
- bridge sections of `app/PromptJuiceTests/ProviderClientTests.swift`
- `scripts/claude-statusline-bridge.sh`
- bridge bundling in `scripts/build_app.sh`
- `docs/claude-statusline-bridge.md`
- `docs/claude-statusline-plutil-plan.md`

## Test matrix

### Parser

- flat screen-reader output;
- classic fullscreen redraws;
- ANSI/control sequences split across reads;
- startup panel followed by Usage panel;
- five-hour and seven-day bars;
- model-specific weekly bars;
- decimal and integer percentages;
- reset times with and without fractional seconds;
- last-known bars with `as of`;
- loading then success;
- subscription-required/API view;
- signed-out/auth failure;
- rate limited;
- malformed and oversized output;
- Claude wording/layout evolution that retains semantic labels.

### Process

- executable override and PATH resolution;
- exact launch flags per version;
- one stable session ID;
- trust/onboarding prompt handling in the owned directory;
- command-palette confirmation;
- no model prompt bytes written;
- cursor query response;
- timeout and cancellation;
- child/process-group cleanup;
- output cap;
- app termination cleanup.

### Scheduling

- first launch with no cache;
- fresh cache suppression;
- stale launch/wake/foreground/panel open;
- manual 60-second debounce;
- concurrent refresh coalescing;
- persisted relaunch gate;
- 5/15/30/60 cooldown progression;
- success/auth-change cooldown reset;
- provider disabled;
- local-only/manual-only;
- API-billing auto-probe suppression;
- reset-boundary refresh;
- offline/sleep suppression.

### Presentation

- exact current;
- exact earlier;
- local estimate;
- checking;
- rate limited with retry time;
- CLI missing;
- signed out;
- update recommended;
- API billing;
- generic failure;
- disabled;
- legacy bridge detected and removable;
- VoiceOver labels and keyboard focus for every action.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Claude TUI copy/layout changes | Flat renderer, pure fixture parser, semantic labels, bounded retry, last-good/local fallback |
| `/usage` throttling | 15-minute TTL, persisted attempt gate, one in-flight request, exponential cooldown |
| Background token/request use for API accounts | Detect API billing and suppress automatic plan polling |
| Empty session/artifact pollution | Stable session ID, owned directory, verified history-suppression setting, owned-artifact cleanup |
| Hooks/plugins/MCP side effects | `--safe-mode`, owned directory, empty allowed-tools list, no model prompt |
| Older Claude versions | Semantic version gate and regular PTY fallback or explicit update guidance |
| Existing user status-line damage | Exact ownership check, previewable restoration, atomic write, delete script last |
| UI promises exceed behavior | Approved before/after copy matrix and presentation tests |
| Mac App Store sandbox | Direct distribution target; revisit architecture for a separate sandboxed product path |

## Implementation completion criteria

- A subscription-authenticated user with Claude Code installed gets an exact reading without bridge setup.
- Claude Desktop subscription activity appears in the shared quota reading when CLI and Desktop use the same account.
- Manual Refresh performs a real, rate-limited-safe check.
- API-billed users avoid scheduled plan probes and receive accurate scope guidance.
- PromptJuice sends no synthetic model message.
- Existing bridge users can restore their Claude settings safely.
- The first broad downloadable build contains no bridge installation journey or bundled bridge script once dogfood gates pass.
- Tests, build, privacy review, accessibility pass, and documentation are complete.

---

# Prompt for Claude: exhaustive UI copy and Settings revision

Copy and send the prompt below to Claude. This is a read-only design/copy assignment that should happen before implementation.

```text
You are revising the PromptJuice macOS UI and product copy for a planned Claude usage-source migration.

Repository/worktree:
/Users/jeremyrojas/worktrees/prompt-juice/claude-usage

Product:
PromptJuice is a native Swift macOS menu-bar app. Its Juice Bar shows Claude and Codex quota windows, reset timing, confidence/source information, and optional “use your juice” notifications.

Important: work READ-ONLY. Do not edit files, run formatters, modify Claude settings, invoke `claude /usage`, send model prompts, commit, push, or install anything. Inspect source, tests, previews, snapshots, README, and docs only.

Confirmed product decision:

1. Claude Code’s built-in `/usage` command will become the primary exact Claude subscription-quota source through a background PTY.
2. The status-line bridge will stop being offered to new users.
3. Existing bridge data remains a temporary dogfood fallback, followed by a safe cleanup migration and code removal.
4. PromptJuice will never send `hi` or another synthetic model message.
5. Claude Desktop, Claude.ai, and Claude Code share the same subscription allowance. A user who primarily uses Claude Desktop can get that shared quota after installing/signing in to the macOS Claude Code CLI with the same account.
6. API/Console-billed Claude authentication is a separate state. `/usage` provides current-session token/cost information rather than organization-wide API spend. Automatic subscription-quota polling will be suppressed for API-billed users.
7. Default refresh will be Smart: roughly 15-minute successful-reading TTL, launch/wake/foreground/panel-open checks only when stale, manual refresh with debounce, last-good cache, and intelligent rate-limit cooldown.
8. The local Claude log estimate remains a fallback and must continue to be labeled as estimated.

Current bridge-oriented surfaces include:

- `app/PromptJuice/Services/PromptJuiceViewModel.swift`
  - `ClaudeLiveUpgrade`
  - `claudeRowOffersSetup`
  - `sourceTooltip(for:)`
  - `claudeSetupButtonTitle`
  - `claudeMeasurementPopoverDetail`
  - `settingsStatusText(for:)`
  - strings including “send any message in Claude Code to refresh,” “Waiting for Claude statusline,” “Set up live readings,” and terminal/statusline explanations
- `app/PromptJuice/UI/PromptJuicePanelView.swift`
  - “Waiting for terminal,” “Not measured yet,” and the “Set up” capsule
- `app/PromptJuice/UI/SettingsView.swift`
  - provider subtitles/status
  - Claude measurement popover
  - Claude setup button
  - the entire Claude bridge consent/success/disclosure UI
  - first-run provider flow and previews
- `app/PromptJuice/UI/JuicebarPanelController.swift`
  - row tooltip and click-routing behavior
- tests:
  - `ClaudePresentationMatrixTests.swift`
  - `PromptJuiceViewModelTests.swift`
  - `PanelSnapshotTests.swift`
  - `JuicebarPanelControllerTests.swift`
  - accessibility/tool-tip/click-router tests
- `README.md`, `docs/prompt-juice.md`, `docs/provider-integrations.md`, `docs/reference/states-and-colors.md`, bridge docs, and install/update docs

Your task:

## 1. Inventory every affected string and surface

Search the full repository for user-visible or accessibility copy that assumes any of these:

- bridge
- statusline/status line
- live readings
- terminal-only Claude tracking
- send/type a message to initialize or refresh
- setup required for exact readings
- manual refresh that only re-reads bridge files
- “Waiting for terminal”
- “Not set up yet”
- estimated/exact/earlier/stale source explanations
- Claude Desktop unsupported

Include literal strings, computed strings, accessibility labels/hints/values, tooltips, popovers, buttons, setup sheets, first run, Settings subtitles, Juice Bar row copy, notifications when relevant, previews, snapshot fixtures, expected test strings, README, troubleshooting, and AI-agent install/update instructions.

## 2. Produce a complete BEFORE → AFTER copy table

Use one row per distinct state/surface/string. Required columns:

| Surface/state | File and line | BEFORE exact copy | AFTER proposed copy | Action/behavior after click | Reason |

Quote the current copy exactly. Give polished replacement copy at the same level of brevity. Group by:

- Juice Bar row/trailing state
- Juice Bar tooltip
- measurement/source popover
- Settings provider subtitle/status
- Settings actions
- first run
- connection/setup guidance
- manual refresh/action messages
- stale/rate-limit states
- accessibility
- previews/tests
- README/docs/troubleshooting

## 3. Design the new Claude presentation matrix

Provide exact copy and actions for all of these states:

1. Checking usage
2. Exact current `/usage` reading
3. Exact last-good/earlier reading
4. Local-log estimate
5. Rate limited with known retry time
6. Rate limited with unknown retry time
7. Claude CLI missing
8. Claude CLI installed and signed out
9. Claude CLI version update recommended
10. Subscription account connected
11. API/Console billing detected
12. Generic PTY/parse failure with a valid cached reading
13. Generic failure with no reading
14. Claude provider disabled
15. Legacy PromptJuice bridge detected and eligible for cleanup
16. Legacy bridge cleanup needs manual review

For each state provide:

- Juice Bar trailing label
- tooltip
- Settings subtitle
- optional button label
- button action
- measurement popover detail
- accessibility label/value/hint
- whether the local estimate appears

Copy must tell the truth about freshness and source. Keep row labels compact enough for the current fixed Juice Bar geometry.

## 4. Revise Settings information architecture

Describe BEFORE and AFTER structure.

The intended AFTER direction is:

- retain the Claude provider toggle;
- remove the bridge setup consent/success/disclosure journey;
- attempt Automatic usage when Claude is enabled;
- show install/sign-in/update actions only when needed;
- retain the measurement information popover with new `/usage` and privacy explanations;
- add a compact Advanced disclosure for:
  - Usage source: Automatic, Claude Code `/usage`, Local activity only
  - Refresh: Smart, 5 minutes, 15 minutes, 30 minutes, Manual only
- expose legacy bridge cleanup only when detected;
- keep API usage scope separate and clearly explained;
- preserve the existing Settings window size if realistic, or identify the smallest justified layout change.

Explain what disappears, what moves, and what becomes conditional. Include a text wireframe for the Claude Settings row in healthy, missing-CLI, signed-out, API-billing, and legacy-bridge states.

## 5. Copy principles

- Use “Claude Code” for the official CLI and “Claude” for the provider/account quota.
- Explain that the reading comes from Claude Code’s built-in `/usage` command where detail is appropriate.
- Avoid internal implementation terms such as PTY in normal UI.
- Remove every instruction to send/type a Claude message for PromptJuice.
- Remove bridge/statusline language from normal UI.
- Preserve “Estimated” wherever local logs drive the number.
- Use “Earlier” or a timestamp when cached data drives the number.
- Keep “exact” out of prominent row copy unless it adds real user value; source/freshness belongs in tooltips and Settings.
- Avoid implying Claude Desktop is queried directly. Explain shared subscription usage and the one-time CLI prerequisite where necessary.
- Avoid implying API organization spend is included.
- A button label must describe the real action: install guide, sign in, update guide, retry, or remove legacy bridge.
- Maintain PromptJuice’s friendly, concise voice.

## 6. Identify implementation dependencies

For every proposed copy/action, state the connection state or data field engineering must expose. Flag copy that depends on account labels, auth category, retry time, CLI version, cache age, or legacy bridge ownership.

## 7. Deliverables

Return, in order:

1. Executive recommendation
2. Complete before/after copy table
3. Claude presentation matrix
4. Settings before/after information architecture
5. Text wireframes
6. Accessibility copy table
7. Tests/previews/docs that must change
8. Exact strings to delete repository-wide
9. Open product questions or blockers

Do not implement. If any current copy is generated indirectly or hidden behind a state you cannot fully trace, identify the uncertainty and cite the relevant source path/line.
```

## Open questions to resolve during implementation

1. Confirm the exact current JSON fields emitted by `claude auth status` for subscription and Console/API authentication using sanitized fixtures.
2. Confirm `/usage` works in one session with `--safe-mode` and `--ax-screen-reader` before depending on both flags.
3. Decide the oldest supported Claude Code version and whether classic TUI fallback remains worth maintaining.
4. Decide whether the Advanced source/cadence controls ship in the first release or remain hidden behind Automatic until user demand appears.
5. Confirm whether any PromptJuice builds have reached external users with the bridge installed. That determines whether migration code remains for one release or bridge code can disappear before the first signed download.
6. Choose the precise install/sign-in action: open official documentation, open Terminal, or provide a copyable command. Authentication stays in the official CLI.
7. Decide whether API-billed local cost should appear in the existing percentage-oriented Juice Bar or only in Settings/details until an Admin API integration exists.
