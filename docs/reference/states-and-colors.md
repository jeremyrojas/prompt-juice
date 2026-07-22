# PromptJuice — States & Colors Reference

Canonical reference for Juicebar severity, provider freshness, and aggregate presentation.

## 1. Color palette

Source: [`SeverityAppearance.swift`](../../app/PromptJuice/UI/SeverityAppearance.swift)

| Token | Hex | Use |
| --- | --- | --- |
| `green` | `#5FD11F` | healthy capacity |
| `orange` | `#F0A32A` | use-soon nudge |
| `muted` | `#969CA6` | calm low, empty, or unavailable |

Provider identity dots use system orange for Claude and system cyan for Codex.

## 2. Severity axis

Source: [`UsageSeverity.swift`](../../app/PromptJuice/Models/UsageSeverity.swift) and [`AlertEngine.swift`](../../app/PromptJuice/Services/AlertEngine.swift)

| Severity | Trigger | Color | Chip | Notification |
| --- | --- | --- | --- | --- |
| `empty` | session remaining is 0% | muted | — | — |
| `useSoon` | reset is within the time threshold and remaining capacity meets the juice threshold | orange | **Use soon** | eligible |
| `low` | session remaining is below 15% | muted | — | — |
| `healthy` | other usable session windows | green | — | — |
| `unavailable` | no usable reading | muted | — | — |

The default use-soon thresholds are 60 minutes and 40% remaining. Settings offers 30/45/60/90 minutes and 25/40/50/60%.

## 3. Confidence and source

Source: [`SnapshotConfidence.swift`](../../app/PromptJuice/Models/SnapshotConfidence.swift) and [`SnapshotSource.swift`](../../app/PromptJuice/Models/SnapshotSource.swift)

| Confidence | UI meaning |
| --- | --- |
| `exact` | current provider reading |
| `stale` | valid earlier exact window |
| `estimated` | local activity-based approximation |
| `unavailable` | no usable quota window |

Claude sources are `claudeUsageCLI`, `claudeCache`, and `claudeLocalLogs`. Codex sources are `codexAppServer` and `codexCache`.

## 4. Claude presentation state

Source: [`ClaudeUsagePresentation.swift`](../../app/PromptJuice/Models/ClaudeUsagePresentation.swift)

Claude presentation resolves account access, refresh state, reading availability, and provider enablement into one state:

| State | Row / Settings behavior | Action |
| --- | --- | --- |
| checking | shows cached reading when available; otherwise `Checking…` | — |
| current | exact value with freshness clock | — |
| saved | valid earlier value with freshness clock | — |
| out of quota | 0% until reset | — |
| backing off | carries reading when available and shows next-check time | — |
| CLI missing | direct reading unavailable; estimate may remain visible | Install |
| signed out | direct reading unavailable; estimate may remain visible | Sign In |
| update required | direct reading unavailable; estimate may remain visible | Update |
| workspace trust required | direct reading unavailable; estimate may remain visible | Trust |
| API billing | neutral, excluded from quota aggregate | — |
| external provider | neutral, excluded from quota aggregate | — |
| unsupported authentication | neutral, excluded from quota aggregate | — |
| failure | cached or estimated reading remains when usable | Retry |
| off | Claude row hidden from downstream aggregate state | — |

Freshness text has five tiers: just now, minutes ago, clock time today, yesterday with clock time, and month/day with clock time.

## 5. Rows and interaction

Rows are fixed-height session rows with provider identity, session bar, remaining percentage, and reset countdown. Claude prerequisite states can show a compact journey button. Available provider rows remain display-only. The settings row includes an information popover describing direct `/usage` reads, the local estimate, and the current state.

## 6. Notifications

When **Notify me** is on, each visible provider at `useSoon` severity can contribute one notice per reset window. PromptJuice merges simultaneous provider notices into one macOS banner and records a per-provider window latch.

## 7. Menu-bar glyph

| Property | Rule |
| --- | --- |
| Tint | orange when any visible provider is `useSoon`; plain otherwise |
| Fill | use-soon provider session remaining during a nudge; otherwise the lowest available visible session remaining |
| Redraw | approximately every second, deduplicated by percentage and severity |

## 8. Enabled providers and aggregates

Enabled providers define rows, headline, severity, glyph, notifications, and click routing. At least one provider remains enabled.

Available quota-bearing snapshots participate in the aggregate. Claude API-billing, external-provider, and unsupported-authentication categories are neutral and stay outside quota aggregation. Worst severity wins, with `useSoon` taking priority so the time-sensitive nudge remains visible.
