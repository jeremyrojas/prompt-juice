# PromptJuice — States & Colors Reference

Canonical reference for every Juicebar state, its trigger, and its color. Kept for
tracking and future work. Reflects the implementation on main (PR #13).

A row's appearance is the product of **two independent axes**:

- **Severity (the situation)** → drives color. One-alert model: only the amber
  *Use soon* nudge raises its voice; everything else is calm.
- **Fetch / trust (Claude data freshness)** → drives how the number is shown.

They compose: e.g. a reading can be an `~Estimate` (fetch axis) that is also `Use soon`
(severity axis).

---

## 1. Color palette — `JuicePalette`

Source: [`SeverityAppearance.swift`](../../app/PromptJuice/UI/SeverityAppearance.swift)

| Token | RGB (0–1) | Hex | Used for |
|---|---|---|---|
| `green` | 0.373, 0.820, 0.122 | `#5FD11F` | healthy |
| `amber` | 0.941, 0.639, 0.165 | `#F0A32A` | the use-soon nudge (the only alert) |
| `muted` | 0.590, 0.610, 0.650 | `#969CA6` | calm low / empty / unavailable |

Provider identity dots are SwiftUI system colors (not `JuicePalette`):

| Provider | Dot | Approx hex |
|---|---|---|
| Claude | system `.orange` | ~`#FF9F0A` |
| Codex | system `.cyan` | ~`#32ADE6` |

---

## 2. Severity axis — the situation (drives color)

Source: [`UsageSeverity.swift`](../../app/PromptJuice/Models/UsageSeverity.swift) · [`AlertEngine.severity`](../../app/PromptJuice/Services/AlertEngine.swift)

Evaluated per provider, in this order. `effective remaining` =
`min(session remaining, weekly remaining ?? 100)` for both Claude and Codex.
`session reset` = minutes until the current session window resets. Thresholds
default **60 min / 40%** (see §3).

| Severity | Trigger | Panel tint | Hex | Chip | Raises alert? | Menu-bar tint | Rank |
|---|---|---|---|---|---|---|---|
| `empty` | `effective remaining ≤ 0` | muted | `#969CA6` | — | no | plain | 3 |
| `useSoon` | `session reset ≤ TimeThreshold` **and** `session remaining ≥ JuiceThreshold` | amber | `#F0A32A` | **Use soon** | **yes** | amber | 4 |
| `low` | `effective remaining < 15` | muted | `#969CA6` | — | no | plain | 2 |
| `healthy` | otherwise | green | `#5FD11F` | — | no | plain | 0 |
| `unavailable` | no usable reading | muted | `#969CA6` | — | no | plain | 1 |

Notes:
- **Only `useSoon` gets a chip and counts as alerting.** `low`/`empty` are calm — the short bar communicates "low" without an alarm.
- **Rank** is the worst-wins order for the aggregate; `useSoon` (4) outranks everything so the nudge always wins the header/glyph over a calm low.
- **Menu-bar tint** is `nil` ("plain template") for everything except `useSoon` — the glyph only lights up (amber) when there's something to do.

---

## 3. Thresholds — what drives the nudge

Source: [`AlertThresholds.swift`](../../app/PromptJuice/Models/AlertThresholds.swift) · Settings UI in [`SettingsView.swift`](../../app/PromptJuice/UI/SettingsView.swift)

| Setting | Default | Options | Drives |
|---|---|---|---|
| Time (reset is within) | 60 min | 30 / 45 / 60 / 90 | the `≤ TimeThreshold` half of `useSoon` |
| Juice (still have at least) | 40% | 25 / 40 / 50 / 60 | the `≥ JuiceThreshold` half of `useSoon` |

Read as one sentence: *"Nudge me when reset is within [60 min] and I still have at least [40%]."*
The `low` boundary (`< 15%`) is a fixed constant (`UsageSeverity.lowRemainingFloor`), not a user threshold — it only controls the calm "running low" look, not an alert.

---

## 4. Rows, header detail, and fetch/trust

Source: [`SnapshotConfidence.swift`](../../app/PromptJuice/Models/SnapshotConfidence.swift) · row in [`PromptJuicePanelView.swift`](../../app/PromptJuice/UI/PromptJuicePanelView.swift) · tooltip in [`PromptJuiceViewModel.sourceTooltip`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

Rows are 48 pt single-line session rows. Each row shows the session remaining
number and session bar. Tapping a measured row scopes the header to that provider.
When the selected provider has a weekly window, the scoped header detail appends
the weekly summary after the session reset text. Tapping the same row again or
dismissing the panel clears selection and returns to the overview header.

Codex is normally exact/Live; it can be stale or unavailable, but never estimated.
The fetch/trust matrix below is Claude-specific.
"Bridge current" means `statusLine.command` points at the installed Application Support
script, that file exists, and `statusLine.refreshInterval` is `10`.

| # | Condition | Settings status | Settings affordance | Juicebar # | Juicebar tooltip | Row click |
|---|---|---|---|---|---|---|
| 1 | exact (fresh from terminal) | Live + ⓘ | — | 41% | Read from Claude Code | scope header |
| 2 | estimated, bridge missing/stale | Estimate + ⓘ | Set up live readings | ~41% | Estimated from local Claude Code activity · open Settings to set up live | scope header |
| 3 | estimated, bridge current | Estimate + ⓘ | — | ~41% | Estimated from local Claude Code activity | scope header |
| 4 | stale | Read earlier · 9:46 + ⓘ | as #2/#3 by bridge status | 41% | Read from Claude Code · 9:46 | scope header |
| 5 | fresh session window | Fresh window + ⓘ | — | Fresh window, 100% session remaining; no reset countdown | Fresh window · starts with your next Claude Code message | scope header |
| 6 | selected provider has a valid weekly window | same as session state | same as session state | scoped header: `Week: N% left · resets in 4d`; `as of 9:46` when older than 30 min; rows keep plain hourly text such as `resets in 3h 0m` | session tooltip | clear scope |
| 7 | selected provider has a fresh weekly window | same as session state | same as session state | scoped header: `Week: 100% left · fresh week`; rows keep plain hourly text such as `resets in 3h 0m` | session tooltip | clear scope |
| 8 | unavailable, bridge missing | Not set up yet + ⓘ | Set Up… | — ghost | (existing status detail) | open Settings + consent sheet |
| 9 | unavailable, bridge current | Waiting for Claude statusline + ⓘ | — | Waiting for terminal ghost row, no Set up cue | You're set up · waiting for Claude Code usage | no action |
| 10 | refreshing | Checking… | — | Checking… ghost row; header "Checking usage…" / "Just a moment…" while every visible provider is still loading | — | — |

On apply, the setup sheet shows a success + next-step confirmation ("You're almost set") before the user returns to Settings.

Root cause: Live needs Claude Code's status line, terminal CLI only; desktop app ignores
`statusLine` ([anthropics/claude-code#41456](https://github.com/anthropics/claude-code/issues/41456)).
Desktop-only users stay on Estimate by design.

Notes:
- The fetch axis only changes the **number presentation + hover**, never the color (that's the severity axis).
- The only at-rest visible tell of a guess is the `~`. Source/age live in the hover tooltip only — facts, never promises.
- Fresh session windows are presentation-only: they carry no reset timestamp and wait behind any valid real reading.
- Last-good provider cache is used only while the cached session or weekly reset is still ahead. After both pass reset, the provider returns to the waiting/setup path.
- Rows use session remaining. Header/menu-bar fill and low/empty severity use `min(session remaining, weekly remaining ?? 100)`. The amber use-soon nudge still uses session reset timing.

---

## 5. Menu-bar glyph

Source: [`AppDelegate.updateStatusItemGlyph`](../../app/PromptJuice/App/AppDelegate.swift) · [`PromptJuiceViewModel.menuBar*`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

| Property | Rule |
|---|---|
| Tint | amber if any provider is `useSoon`, else plain (uncolored) |
| Fill | the `useSoon` provider's effective remaining when a nudge is active, else the lowest available provider effective remaining |
| Redraw | every ~1s, deduped on `"percent-severity"` |

---

## 6. Enabled providers

Source: [`PromptJuiceSettingsStore.swift`](../../app/PromptJuice/Services/PromptJuiceSettingsStore.swift) · [`PromptJuiceViewModel.visibleSnapshots`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

The enabled provider set is the boundary for downstream state. Rows, header verdict,
aggregate severity, menu-bar glyph, snooze identity, and click routing all use enabled
providers only.

Rules:
- Hidden providers leave no Juicebar row, no header contribution, no glyph contribution,
  and no setup nudge.
- Hiding a provider keeps its bridge/install state intact; re-enabling resumes from the
  latest fetch state.
- At least one provider is always enabled. The store clamps empty writes, so zero-provider
  panel and glyph states are unrepresentable.

## 7. Aggregate / multi-provider (header verdict + droplet)

Rows are always independent; clashes only affect the **header** and the **menu-bar glyph**.
Symmetric — swap the two providers and it holds.
The matrix applies after the enabled-provider filter.

| Provider A | Provider B | Header verdict | Droplet |
|---|---|---|---|
| healthy | healthy | "Plenty of prompt juice left" | green, lower % |
| useSoon | healthy | "Use [A] before it resets" | amber, A's % |
| useSoon | useSoon | "Use prompt juice soon" | amber, lower % |
| **useSoon** | **low** | "Use [A] before it resets" | **amber, A's effective remaining** |
| low | healthy | "[low one] is running low" | muted, low % |
| low | low | "Running low on both" | muted, lower % |
| not-measured | healthy | "Plenty of prompt juice left" | green, B's % |
| not-measured | useSoon | "Use [B] before it resets" | amber, B's % |
| not-measured | not-measured | "Not measured yet" | muted / ghost |

**Clash rule (use-soon + low):** the amber nudge wins the header, and the droplet fill
follows the *nudged* provider's effective remaining. The low provider stays calm in its own row.

---

## Quick map of state → color

| State | Color | Hex |
|---|---|---|
| Healthy / Live | green | `#5FD11F` |
| Use soon (the nudge) | amber | `#F0A32A` |
| Low / Empty | muted | `#969CA6` |
| Not measured / unavailable | muted | `#969CA6` |
