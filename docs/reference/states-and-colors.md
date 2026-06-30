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
| `red` | 0.941, 0.271, 0.224 | `#F04539` | **retired** — no longer mapped to any state |
| `muted` | 0.590, 0.610, 0.650 | `#969CA6` | calm low / empty / unavailable |

Provider identity dots are SwiftUI system colors (not `JuicePalette`):

| Provider | Dot | Approx hex |
|---|---|---|
| Claude | system `.orange` | ~`#FF9F0A` |
| Codex | system `.cyan` | ~`#32ADE6` |

---

## 2. Severity axis — the situation (drives color)

Source: [`UsageSeverity.swift`](../../app/PromptJuice/Models/UsageSeverity.swift) · [`AlertEngine.severity`](../../app/PromptJuice/Services/AlertEngine.swift)

Evaluated per provider, in this order. `remaining` = remaining %, `reset` = minutes
until reset. Thresholds default **60 min / 40%** (see §3).

| Severity | Trigger | Panel tint | Hex | Chip | Raises alert? | Menu-bar tint | Rank |
|---|---|---|---|---|---|---|---|
| `empty` | `remaining ≤ 0` | muted | `#969CA6` | — | no | plain | 3 |
| `useSoon` | `reset ≤ TimeThreshold` **and** `remaining ≥ JuiceThreshold` | amber | `#F0A32A` | **Use soon** | **yes** | amber | 4 |
| `low` | `remaining < 15` | muted | `#969CA6` | — | no | plain | 2 |
| `healthy` | otherwise | green | `#5FD11F` | — | no | plain | 0 |
| `unavailable` | no usable reading | muted | `#969CA6` | — | no | plain | 1 |

Notes:
- **Only `useSoon` gets a chip and counts as alerting.** `low`/`empty` are calm — the short bar communicates "low" without an alarm. Red is no longer used.
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

## 4. Fetch / trust axis — Claude data freshness (drives the number)

Source: [`SnapshotConfidence.swift`](../../app/PromptJuice/Models/SnapshotConfidence.swift) · row in [`PromptJuicePanelView.swift`](../../app/PromptJuice/UI/PromptJuicePanelView.swift) · tooltip in [`PromptJuiceViewModel.sourceTooltip`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

Codex is normally exact/Live; it can be stale or unavailable, but never estimated.
The matrix below is Claude-only.
"Bridge current" means `statusLine.command` points at the installed Application Support
script, that file exists, and `statusLine.refreshInterval` is `10`.

| # | Condition | Settings status | Settings affordance | Juicebar # | Juicebar tooltip | Row click |
|---|---|---|---|---|---|---|
| 1 | exact (fresh from terminal) | Live + ⓘ | — | 41% | Read from Claude Code | open Settings |
| 2 | estimated, bridge missing/stale | Estimate + ⓘ | Set up live readings | ~41% | Estimated from local Claude Code activity · open Settings to set up live | open Settings + consent sheet |
| 3 | estimated, bridge current | Estimate + ⓘ | — | ~41% | Estimated from local Claude Code activity | open Settings |
| 4 | stale | Read earlier · 9:46 + ⓘ | as #2/#3 by bridge status | 41% | Read from Claude Code · 9:46 | open Settings (+sheet if #2) |
| 5 | unavailable, bridge missing | Not set up yet + ⓘ | Set Up… | — ghost | (existing status detail) | open Settings + consent sheet |
| 6 | unavailable, bridge current | Waiting for Claude statusline + ⓘ | — | Waiting for terminal ghost row, no Set up cue | You're set up · waiting for Claude Code usage | open Settings |
| 7 | refreshing | Checking… | — | Checking… ghost row; header "Checking usage…" / "Just a moment…" while every visible provider is still loading | — | — |

On apply, the setup sheet shows a success + next-step confirmation ("You're almost set") before the user returns to Settings.

Root cause: Live needs Claude Code's status line, terminal CLI only; desktop app ignores
`statusLine` ([anthropics/claude-code#41456](https://github.com/anthropics/claude-code/issues/41456)).
Desktop-only users stay on Estimate by design.

Notes:
- The fetch axis only changes the **number presentation + hover**, never the color (that's the severity axis).
- The only at-rest visible tell of a guess is the `~`. Source/age live in the hover tooltip only — facts, never promises.

---

## 5. Menu-bar glyph

Source: [`AppDelegate.updateStatusItemGlyph`](../../app/PromptJuice/App/AppDelegate.swift) · [`PromptJuiceViewModel.menuBar*`](../../app/PromptJuice/Services/PromptJuiceViewModel.swift)

| Property | Rule |
|---|---|
| Tint | amber if any provider is `useSoon`, else plain (uncolored) |
| Fill | the `useSoon` provider's % when a nudge is active, else the lowest available % (binding constraint), else 100 |
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
| **useSoon** | **low** | "Use [A] before it resets" | **amber, A's %** (not B's low %) |
| low | healthy | "[low one] is running low" | muted, low % |
| low | low | "Running low on both" | muted, lower % |
| not-measured | healthy | "Plenty of prompt juice left" | green, B's % |
| not-measured | useSoon | "Use [B] before it resets" | amber, B's % |
| not-measured | not-measured | "Not measured yet" | muted / ghost |

**Clash rule (use-soon + low):** the amber nudge wins the header, and the droplet fill
follows the *nudged* provider (e.g. 78%), not the lowest (8%) — an 8% amber droplet under a
"Use [provider]" headline would contradict itself. The low provider stays calm in its own row.

---

## Quick map of state → color

| State | Color | Hex |
|---|---|---|
| Healthy / Live | green | `#5FD11F` |
| Use soon (the nudge) | amber | `#F0A32A` |
| Low / Empty | muted | `#969CA6` |
| Not measured / unavailable | muted | `#969CA6` |
| (Red) | — | retired |
