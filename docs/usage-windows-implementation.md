# Usage windows — implementation plan

Companion to [`usage-windows-ui-spec.html`](usage-windows-ui-spec.html) (the mockups). This file is
the single source for *what we are building and in what order*. It replaces the four separate mock
pages that lived in `design/mocks/` and the scattered design notes.

Status: **design approved, implementation not started.** Code facts below were re-verified against
`main` (`fc7796f`) on 2026-09-18.

## 1. Why

Providers no longer have one usage window each.

| Provider | Windows today | Notes |
|---|---|---|
| Claude | 5-hour, Weekly (all models), Weekly · Fable | Fable is the scarce one; it can run dry while the other two look healthy. |
| Codex, higher tiers (Pro) | Weekly only | OpenAI removed the 5-hour limit on these plans. |
| Codex, lower tiers | 5-hour + Weekly | The 5-hour limit still exists here. |

The app still assumes one 5-hour window per provider, so on Codex Pro the weekly is pushed through
the session formatter and renders as `resets in 146h 4m`, and Claude's Weekly and Fable are not
shown at all.

## 2. What changed since the design sessions (July–August)

1. **Claude data path was replaced.** The statusline bridge is retired (`7204c67`). Claude usage now
   comes from Claude Code's `/usage` screen via a PTY (`ClaudePTYSession` → `ClaudeUsageParser` →
   `ClaudeUsageCoordinator`). Every plan step that mentioned the bridge script or "confirm the Fable
   statusline key" is dead.
2. **Fable is already parsed — and then dropped.** `ClaudeUsageParser` models `.session`,
   `.weeklyAllModels` and `.weeklyModel(String)`; `ClaudeUsageReading.modelSpecificWeekly` carries
   Fable. `ClaudeUsageCoordinator.snapshot(from:)` maps `session` and `weekly` only, so
   `modelSpecificWeekly` has no consumer. Plumbing it through is small.
3. **Codex recon is done.** Live `account/rateLimits/read` on a Pro plan returns the weekly *in the
   `primary` slot* (`windowDurationMins: 10080`) with `secondary: null`, and only a `codex` bucket
   (no Spark bucket). The lower-tier shape is **inferred, not captured**: the existing mapper
   implies `primary` = 300 and `secondary` = 10080, but no real payload has been seen. Jeremy has a
   non-Pro account and can run the capture — ask him for it during slice 2 and add it as a fixture.
   **Rule: classify a window by its duration, never by its slot**, so either slot order works.
   Known durations get canonical labels (300 min → `5-hour limit`, 10080 min → `Weekly`). Any other
   duration is still a valid row, labelled from its real length with the same single-unit rule
   (`24-hour limit`, `3-day limit`) and logged once — never an error state and never mislabelled
   `Weekly`. Thresholds follow cadence class: under 1 day uses the 5-hour pair, 1 day and up uses
   the weekly pair. Providers change limits without notice; the row set must survive that.
4. **Codex's 5-hour is real, not hypothetical.** The mockups previously labelled that state
   "hypothetical"; it is the lower-tier reality and must be built and tested as a first-class case.
5. **Claude non-measured states exist now** (`ClaudeGuidanceView`, `ClaudeUsagePresentation`:
   signed out, CLI missing, update required, workspace trust…). This plan governs *measured* rows
   only; those guidance states are unchanged.

Unchanged, so the plan still applies: `ProviderSnapshot` is still `rateWindow` + optional
`weeklyWindow`; `resetText` still emits compound `2h 1m`; the panel is still fixed 48 pt single rows;
`AlertEngine` and Settings still know one threshold pair and one window.

## 3. The spec in brief (full detail and visuals in the HTML spec)

**Rows.** Provider card = small header (dot + name + chevron) and one row per visible window: label
left (`5-hour limit`, `Weekly`, `Fable`), values right (`83% left · resets in 2h`), thin flat bar
below (4 px main, 3 px secondary). No chips. Layout is identical across states; only colour changes.

**Colour grammar.** Green = healthy main bar. Grey = healthy secondary bar. Muted `#969CA6` = low
(< 15 %), never an alert. Amber `#F0A32A` = use-soon only; on an amber row the reset text and bar
turn amber, the percent stays white.

**Reset format.** Always `resets in <t>`, single largest unit, floored: under 1 h → minutes
(`33m`), 1–24 h → hours (`23h`), 24 h and up → days (`5d`). No compound units, weekday names or
dates. One pure function shared by rows, header, notifications and the Settings status line.

**Disclosure.** Collapsed by default: each provider shows its shortest-cadence window (Claude
5-hour; Codex 5-hour where the plan has one, otherwise Weekly). Chevron expands/collapses; the
choice is remembered per provider. An amber window surfaces through a collapsed card — also live,
while the panel is open — without expanding the rest or overwriting the saved choice. Low never
surfaces. Hidden windows are still measured: they can go amber, notify and surface.

**Droplet and verdict.** Both follow each provider's *main* window, exactly as today
(`headerRemainingPercent`, `headerSeverity`, `headline`). Amber from any window turns them amber.
One exception, **lockout**: when a limit that blocks the whole provider is exhausted — the
all-models Weekly at 0 % — that provider reads as empty, because "Plenty of prompt juice left" while
locked out would be false. A model-specific weekly (Fable) running out only mutes its own row; other
models still work. Do not take the minimum across windows: a nearly-spent Fable must not make the
whole app look empty (PR #38 tried `effectiveRemainingPercent = min(session, weekly)` and backed it
out for this reason).

**Alerts.** Use-soon is the only alert, evaluated per window with per-cadence thresholds:
5-hour `reset ≤ 60 min AND ≥ 40 % left`; weekly `reset ≤ 1 day AND ≥ 40 % left`. In-use guard: a
window fires only if it was actually used this cycle (≥ 5 % used), so an untouched limit never nags.

**Header (one voice).** Rank amber windows by soonest reset (tie → more remaining). Title = the
narrowest scope covering all of them: one window → name it (`Use your Fable juice`, subtitle drops
the name: `62% left · resets in 23h`); several in one provider → `Use your Claude juice`; across
providers → `Use your juice`. Subtitle lists soonest first, coalesces same-reset windows in row
order (`Weekly & Fable reset in 23h`), every group keeps its verb. If more than two groups, or the
line would not fit, use the count form: `5 limits reset soon · Claude 5-hour resets in 33m`. Never
ellipsize. Low states get no header mention. Simultaneous ambers produce one notification.

**Settings.** `Use the juice` has two groups named by cadence — **5-hour limits** (60 minutes /
40 %) and **Weekly limits** (1 day / 40 %). No per-window visibility toggles; disclosure owns that.
Provider status line uses the reset format (`Live · resets in 4d`).

**Deliberate divergence.** Claude's own menu colours a heavily-used bar amber. We do not: amber
means "expiring with juice unused — use it", and the app never tells anyone to use less.

**Defaults Codex should not re-litigate.** In-use guard = at least 5 % used this cycle. Weekly
threshold picker offers 12 hours / 1 day / 2 days / 3 days (default 1 day); the 5-hour picker keeps
its current options. One pull request per slice, with slice 7 (docs) folded into the last one.

**Out of scope.** Codex Spark (no longer in the payload; revisit if users ask). Per-provider
threshold UI (store supports it, UI does not). Click-through on rows.

## 4. Slices

Serial, because nearly every slice touches `PromptJuicePanelView.swift`,
`PromptJuiceViewModel.swift` and `ProviderSnapshot.swift`. Each ships green on its own.

| # | Slice | Main files | Gate |
|---|---|---|---|
| 1 | **Reset formatter.** Pure `ResetFormatter`; replace `resetText` / `fullResetText` / `weeklyResetText`. Every surface already routes through these in the view model — rows, header detail (`:403–413`, which already coalesces providers that share a reset time), the Settings status line (`:1076`) and the use-soon notification copy (`:8–72`) — so this is one file plus tests. Fixes `146h 4m` immediately. | `PromptJuiceViewModel` | unit table |
| 2 | **Windows model.** `LimitWindow { kind: .fiveHour / .weekly / .weeklyModel(name) / .other(durationMinutes), rateWindow, updatedAt }`; `ProviderSnapshot.windows` ordered by cadence, `mainWindow` = first. Codex mapper classifies by `windowDurationMins` (300 → 5-hour, 10080 → weekly, anything else → a window labelled by its actual duration; see section 2 item 3) and stops requiring a session-shaped `primary`. Claude coordinator maps `modelSpecificWeekly`. Caches carry the list. Keep `rateWindow`/`weeklyWindow` as computed shims so untouched call sites compile; delete the "retained for future weekly UI" comments. `resetWindowID` becomes per-window. | `ProviderSnapshot`, `RateWindow`, `CodexRateLimitResponse`, `ClaudeUsageCoordinator`, `ProviderWindowSnapshotCache`, `CodexSnapshotCache`, fixtures | unit; no visible change except Codex Pro labelled Weekly |
| 3 | **Row anatomy.** Card header + labelled rows + flat bars; `PromptJuicePanelMetrics.height` becomes a function of visible rows. All windows rendered expanded in this slice. | `PromptJuicePanelView`, `SeverityAppearance` | snapshot PNGs |
| 4 | **Disclosure.** Chevron hit-rects in `PanelClickRouter`, per-provider expanded flag in `PromptJuiceSettingsStore`, panel resize in `JuicebarPanelController`, amber punch-through. | `JuicebarPanelController`, `PromptJuicePanelView`, `PromptJuiceSettingsStore` | router tests + snapshots + **computer use #1** |
| 5 | **Alerts.** Per-window use-soon with per-cadence thresholds and in-use guard; per-window severity; header cascade as a pure function; notification latch keyed by provider + window (today `notifiedUseSoonWindowIDs` is keyed by provider only, so a weekly alert would clobber the 5-hour latch); coalesced notification. | `AlertEngine`, `AlertThresholds`, `UsageSeverity`, `PromptJuiceViewModel` (header detail and notification copy live here; extend the existing shared-reset coalescing rather than rewriting it) | unit matrix (below) |
| 6 | **Settings.** Two cadence groups. Store thresholds keyed by `(provider, cadence)` with shared defaults; migrate the legacy `remainingMinutesThreshold` / `remainingPercentThreshold` into the 5-hour defaults; weekly defaults 1440 min / 40 %. | `SettingsView`, `PromptJuiceSettingsStore` | unit + **computer use #2** |
| 7 | **Docs.** `docs/reference/states-and-colors.md`, `docs/provider-integrations.md`, `README.md`. | docs | — |

Safe to run as side threads (disjoint files, no screen): the Codex mapper part of slice 2, and
slice 7 at the end.

## 5. Verification

Headless first. `PanelSnapshotTests` renders the real panel offscreen (`PROMPTJUICE_SNAPSHOT=1`);
add fixtures for: Claude three windows healthy · Codex weekly-only · Codex 5-hour + weekly ·
collapsed · Claude expanded · Fable amber while collapsed · Fable low while collapsed · the five
multi-amber cases. These PNGs are the visual gate for slices 3–5.

Computer use is serial and slow, so it is spent twice only:

1. **After slice 4** — click each chevron, relaunch and confirm the choice persisted per provider,
   watch a window cross into amber while the panel is open and confirm only that row appears.
2. **Final acceptance after slice 6** — Settings groups change behaviour for the right cadence,
   a coalesced notification arrives, and the real Claude and Codex readings match the providers'
   own usage screens.

Header cascade test matrix (slice 5, pure function, table-driven like `AlertEngineTests`):
single 5-hour · single weekly · single Fable (subtitle drops the name) · Claude ×2 coalesced ·
Claude ×3 (soonest leads, pair coalesces) · Codex ×2 on a 5-hour plan · one on each provider ·
all five → count form · three groups → count form · tie-break by remaining · enumeration that
would overflow → count form · low present alongside amber (ignored) · untouched window at 100 %
(in-use guard suppresses) · hidden/collapsed window amber (still counted) · nothing amber
(default header) · Fable at 0 % (verdict unchanged, row muted) · all-models Weekly at 0 % (provider reads empty — lockout).
