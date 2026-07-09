# PromptJuice — States & Colors Reference

Canonical reference for every Juicebar state, its trigger, and its color. Kept for
tracking and future work. Reflects the implementation on main (PR #13).

A row's appearance is the product of **two independent axes**:

- **Severity (the situation)** → drives color. One-alert model: only the orange
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
| `orange` | 0.941, 0.639, 0.165 | `#F0A32A` | the use-soon nudge (the only alert) |
| `muted` | 0.590, 0.610, 0.650 | `#969CA6` | calm low / empty / unavailable |

Provider identity dots are SwiftUI system colors (not `JuicePalette`):

| Provider | Dot | Approx hex |
|---|---|---|
| Claude | system `.orange` | ~`#FF9F0A` |
| Codex | system `.cyan` | ~`#32ADE6` |

---

## 2. Severity axis — the situation (drives color)

Source: [`UsageSeverity.swift`](../../app/PromptJuice/Models/UsageSeverity.swift) · [`AlertEngine.severity`](../../app/PromptJuice/Services/AlertEngine.swift)

Evaluated per provider, in this order. `session remaining` drives visible
percentages, droplet fill, and low/empty severity. `effective remaining` =
`min(session remaining, weekly remaining ?? 100)` is retained in the data layer
for future weekly UI.
`session reset` = minutes until the current session window resets. Thresholds
default **60 min / 40%** (see §3).

| Severity | Trigger | Panel tint | Hex | Chip | Notification candidate? | Menu-bar tint | Rank |
|---|---|---|---|---|---|---|---|
| `empty` | `session remaining ≤ 0` | muted | `#969CA6` | — | no | plain | 3 |
| `useSoon` | `session reset ≤ TimeThreshold` **and** `session remaining ≥ JuiceThreshold` | orange | `#F0A32A` | **Use soon** | **yes** | orange | 4 |
| `low` | `session remaining < 15` | muted | `#969CA6` | — | no | plain | 2 |
| `healthy` | otherwise | green | `#5FD11F` | — | no | plain | 0 |
| `unavailable` | no usable reading | muted | `#969CA6` | — | no | plain | 1 |

Notes:
- **Only `useSoon` gets a chip and can create a macOS notification.** `low`/`empty` are calm — the short bar communicates "low" without an alarm.
- **Rank** is the worst-wins order for the aggregate; `useSoon` (4) outranks everything so the nudge always wins the header/glyph over a calm low.
- **Menu-bar tint** is `nil` ("plain template") for everything except `useSoon` — the glyph only lights up (orange) when there's something to do.

---

## 3. Thresholds — what drives the nudge

Source: [`AlertThresholds.swift`](../../app/PromptJuice/Models/AlertThresholds.swift) · Settings UI in [`SettingsView.swift`](../../app/PromptJuice/UI/SettingsView.swift)

| Setting | Default | Options | Drives |
|---|---|---|---|
| Time (reset is within) | 60 min | 30 / 45 / 60 / 90 | the `≤ TimeThreshold` half of `useSoon` |
| Juice (still have at least) | 40% | 25 / 40 / 50 / 60 | the `≥ JuiceThreshold` half of `useSoon` |

Read as one sentence: *"When reset is within [60 min] and I still have at least [40%]."*
The `low` boundary (`< 15%`) is a fixed constant (`UsageSeverity.lowRemainingFloor`), not a user threshold — it only controls the calm "running low" look, not an alert.

The **Notify me** toggle gates macOS banners. The orange droplet, row chip, and panel color still follow `useSoon` when notifications are off.

---

## 4. Rows, header detail, and fetch/trust

Source: [`SnapshotConfidence.swift`](../../app/PromptJuice/Models/SnapshotConfidence.swift) · row in [`PromptJuicePanelView.swift`](../../app/PromptJuice/UI/PromptJuicePanelView.swift) · tooltip in [`PromptJuiceViewModel.sourceTooltip`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

Rows are 48 pt single-line session rows. Each row shows the session remaining
number, session bar, and a grouped trailing cluster such as
`85% · resets in 4h 33m`. Provider rows are display-only. The manual header
keeps the verdict headline and names the visible provider or providers driving
the reset, such as `Claude and Codex reset in 4h 33m` or
`Claude resets in 42m`.

Codex is normally exact/Live; it can be stale or unavailable, but never estimated.
The fetch/trust matrix below is Claude-specific.
"Bridge current" means `statusLine.command` points at the installed Application Support
script, that file exists, and `statusLine.refreshInterval` is `10`.

| # | Condition | Settings status | Settings affordance | Juicebar # | Juicebar tooltip | Row click |
|---|---|---|---|---|---|---|
| 1 | exact (fresh from terminal) | Live + ⓘ | — | 41% | Read from Claude Code | no action |
| 2 | estimated, bridge missing/stale | Estimate + ⓘ | Set up live readings | ~41% | Estimated from local Claude Code activity · open Settings to set up live | no action |
| 3 | estimated, bridge current | Estimate + ⓘ | — | ~41% | Estimated from local Claude Code activity | no action |
| 4 | stale | Read earlier · 9:46 + ⓘ | as #2/#3 by bridge status | 41% | Read from Claude Code · 9:46 | no action |
| 5 | fresh session window | Fresh window + ⓘ | — | Fresh window, 100% session remaining; no reset countdown | Fresh window · starts with your next Claude Code message | no action |
| 6 | provider has a valid weekly window | same as session state | same as session state | same session row; weekly retained for future UI | session tooltip | no action |
| 7 | provider has a fresh weekly window | same as session state | same as session state | same session row; weekly retained for future UI | session tooltip | no action |
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
- Rows, header/menu-bar fill, and low/empty severity use session remaining. The orange use-soon nudge uses session reset timing.

## 5. Use-soon notifications

Source: [`PromptJuiceNotificationService.swift`](../../app/PromptJuice/Services/PromptJuiceNotificationService.swift) · [`PromptJuiceViewModel.pendingUseSoonNotifications`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

When **Notify me** is on, each visible available provider at `useSoon` severity can deliver one macOS banner per active reset window. The latch key is provider raw value plus the provider's current reset-window id, and it is recorded when the banner is dispatched. A window is withdrawn only after its encoded reset time has passed, or when the provider reports a valid newer reset window.

The Juicebar panel stays user-summoned from the menu-bar droplet. Tapping a use-soon notification opens the Juicebar.

---

## 6. Menu-bar glyph

Source: [`AppDelegate.updateStatusItemGlyph`](../../app/PromptJuice/App/AppDelegate.swift) · [`PromptJuiceViewModel.menuBar*`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

| Property | Rule |
|---|---|
| Tint | orange if any provider is `useSoon`, else plain (uncolored) |
| Fill | the `useSoon` provider's session remaining when a nudge is active, else the lowest available provider session remaining |
| Redraw | every ~1s, deduped on `"percent-severity"` |

---

## 7. Enabled providers

Source: [`PromptJuiceSettingsStore.swift`](../../app/PromptJuice/Services/PromptJuiceSettingsStore.swift) · [`PromptJuiceViewModel.visibleSnapshots`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

The enabled provider set is the boundary for downstream state. Rows, header verdict,
aggregate severity, menu-bar glyph, notification latch, and click routing all use enabled
providers only.

Rules:
- Hidden providers leave no Juicebar row, no header contribution, no glyph contribution,
  and no setup nudge.
- Hiding a provider keeps its bridge/install state intact; re-enabling resumes from the
  latest fetch state.
- At least one provider is always enabled. The store clamps empty writes, so zero-provider
  panel and glyph states are unrepresentable.

## 8. Aggregate / multi-provider (header verdict + droplet)

Rows are always independent; clashes only affect the **header** and the **menu-bar glyph**.
Symmetric — swap the two providers and it holds.
The matrix applies after the enabled-provider filter.

| Provider A | Provider B | Header verdict | Droplet |
|---|---|---|---|
| healthy | healthy | "Plenty of prompt juice left" | green, lower % |
| useSoon | healthy | "Use [A] before it resets" | orange, A's % |
| useSoon | useSoon | "Use prompt juice soon" | orange, lower % |
| **useSoon** | **low** | "Use [A] before it resets" | **orange, A's session remaining** |
| low | healthy | "[low one] is running low" | muted, low % |
| low | low | "Running low on both" | muted, lower % |
| not-measured | healthy | "Plenty of prompt juice left" | green, B's % |
| not-measured | useSoon | "Use [B] before it resets" | orange, B's % |
| not-measured | not-measured | "Not measured yet" | muted / ghost |

**Clash rule (use-soon + low):** the orange nudge wins the header, and the droplet fill
follows the *nudged* provider's session remaining. The low provider stays calm in its own row.

---

## Quick map of state → color

| State | Color | Hex |
|---|---|---|
| Healthy / Live | green | `#5FD11F` |
| Use soon (the nudge) | orange | `#F0A32A` |
| Low / Empty | muted | `#969CA6` |
| Not measured / unavailable | muted | `#969CA6` |
