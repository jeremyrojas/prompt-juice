# Juicebar States Redesign — v1 Implementation Plan

Consolidates the 2026-06-12 UX decisions into an ordered, file-level build plan.
Each slice is tagged **[context-heavy]** (best done with full design context) or
**[self-contained]** (safe to hand to Codex from this doc).

## Status (built 2026-06-12, branch `juicebar-states-redesign`)

All six slices implemented; 49 tests pass; the `.app` builds + codesigns with the
bridge script bundled. Verified visually via offscreen snapshot renders of the real
`PromptJuicePanelView` (healthy, use-soon, calm low, estimate `~`, not-measured + Set up,
and the use-soon/low clash).

Known follow-ups: (1) source-on-hover uses `.help()`, but the panel's AppKit click-capture
(`ClickReadyHostingView.hitTest` returns self) may suppress tooltips — needs a live check /
a small hosting-view tweak. (2) The not-measured subtitle reads "Claude n/a"; could be
"Claude not set up". (3) Setup approval is a native `NSAlert` with the exact change.

## Design in one paragraph

**One-alert model.** The amber **Use soon** nudge — reset is near *and* you still
have at least the Juice Threshold left — is the *only* thing that raises its voice.
**Low goes calm** (short bar, no chip, no red); the short fill speaks for itself.
**Red retires** (reserved at most for truly blocked/0% later). **Claude fetch states
collapse to two:** *Measured* (the number shows; source/freshness on hover only, as
facts not promises) and *Not measured yet* (calm gray + a consent-based "Set up Claude"
install). Severity is **provider-agnostic**, so everything is symmetric for Claude or
Codex; the `~`/estimate is Claude-only (logs fallback). Defaults: **60 min / 40%**.

## Build order

### Slice 1 — Calm `low` + fix the aggregate/clash ranking  [context-heavy]
Files: `Models/UsageSeverity.swift`, `UI/SeverityAppearance.swift`, `Services/AlertEngine.swift`, `Services/PromptJuiceViewModel.swift`
- `UsageSeverity`: `low`/`empty` → `isAlerting = false`, `chipText = nil`; `rank` so `useSoon` outranks `low`.
- `SeverityAppearance`: `tint` for `low`/`empty` → neutral/calm (not red); `menuBarTint` for `low` → `nil`.
- Aggregation rule (header verdict + menu-bar glyph; rows always stay independent):
  - Either provider `useSoon` → amber nudge wins. One → "Use [provider] before it resets"; both → "Use prompt juice soon."
  - Else → calm; droplet fill = lower provider; verdict factual ("Running low on both", "Plenty of prompt juice left").
  - not-measured never overrides the other provider's real reading; both not-measured → "Not measured yet."
  - **Clash (use-soon + low):** nudge wins AND `headerRemainingPercent`/`menuBarRemainingPercent` follow the alert (preferred) snapshot's %, NOT the global min.
- Accept: 8% renders a calm short bar (no chip/red); use-soon(78%) + low(8%) shows the amber nudge with a 78% droplet.

### Slice 2 — Relabel the threshold menus  [self-contained]
File: `App/AppDelegate.swift` (`addThresholdMenus`)
- Reframe the two controls as one use-juice sentence ("When reset is within [60m] and I still have at least [40%]"). Logic is already correct (`shouldUseSoon`); only labels change. Keep defaults 60m / 40%.
- Accept: the menu reads as nudge configuration, not a low-alarm.

### Slice 3 — Cleanups  [self-contained]
Files: `Services/PromptJuiceViewModel.swift`, `Models/UsageSeverity.swift`, `Services/AlertEngine.swift`
- Remove the debug `"Alerts: 60m / 40%"` string written to the subtitle (`refreshModeForThresholds`).
- Retire scattered magic numbers: `UsageSeverity.lowRemainingFloor = 15` and the hardcoded bands in `AlertEngine.statusText` (largely dead once `low` isn't a special colored state).

### Slice 4 — Two-state fetch + source on hover  [context-heavy]
Files: `UI/PromptJuicePanelView.swift` (`ProviderUsageRow`), `Services/PromptJuiceViewModel.swift`
- Render: Live = silent; estimate = `~` prefix + `.help()` tooltip "Estimated from local Claude Code activity"; stale = normal number + tooltip "Read from Claude Code · 9:46"; not-measured = calm gray + "Set up Claude" CTA.
- Retire the tap-to-rewrite-header source path: `selectProvider`/`selectedProvider`, `sourceText`, and the provenance branch of `detail` in the view model; the selection handling in `ProviderUsageRow`. Source lives in hover tooltips only.
- Tooltips state facts, never promises (no "updates when you use Claude Code").
- Accept: rows show number + hover tooltip; tapping a row no longer rewrites the header.

### Slice 5 — Bundle the bridge script  [self-contained]
- Add `scripts/claude-statusline-bridge.sh` to the app bundle Resources (build step; Resources currently holds only `Info.plist`). It must be present at `PromptJuice.app/Contents/Resources/claude-statusline-bridge.sh`.

### Slice 6 — "Set up Claude" consent-install flow  [context-heavy]
New setup UI + a settings.json writer.
- Approval sheet shows the **exact** change before writing:
  - No existing `statusLine` → additive (add the whole block).
  - Existing `statusLine` → **wrap** it (rewrite command so the bridge runs first, then delegates to theirs via `PROMPTJUICE_CLAUDE_STATUSLINE_COMMAND='<their cmd>'`); show a real before→after diff.
- On approve: copy the bundled script to `~/Library/Application Support/PromptJuice/claude-statusline-bridge.sh`; write the **full absolute** path into `~/.claude/settings.json` (not `~`); merge, don't clobber.
- Use macOS `/usr/bin/plutil` for statusline JSON parsing. Keep the `jq` parser available behind `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=jq` as a rollback path.
- Low-emphasis "View the script" link (read-only) for the curious. Remove option in Settings.
- Accept: a user with/without an existing status line gets a correct, approved write; existing status line still renders.

## Open copy / decisions (non-blocking)
- Exact calm "running low" verdict wording.
- Clash droplet default = follows the nudge (78%); confirm vs. always-lowest.

## Provenance
Full rationale in working memory: `point1-threshold-severity-tasks`, `point2-fetch-states-and-bridge`.
Key facts: severity is provider-agnostic (symmetric); estimate/`~` is Claude-only; Refresh re-reads files (real for Codex, no-op for Claude unless Claude Code wrote a new reading); the bridge is the real "Not measured" cause and is not auto-installed today.
