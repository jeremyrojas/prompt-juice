# Icon System + Juicebar Refinement Plan

Scope: the icon system (menu-bar glyph + app icon) and a pass on the Juicebar
panel for hierarchy, semantics, and material. Also locks the menu-bar
interaction model after a quick look at macOS conventions.

This is a design/implementation plan only. No code yet. It references real
symbols so the work is unambiguous when we start.

Related docs: [`PLAN.md`](../PLAN.md) (master roadmap), [`docs/prompt-juice.md`](prompt-juice.md).

---

## North star (unchanged)

> How much useful AI capacity is left, and should I use it before reset?

Every change below is judged against one test: does it make that answer faster
to read at a glance?

## Cross-cutting principle: native macOS Liquid Glass

The app should feel **first-party Apple**, not a themed web panel. Prefer native
materials and system Liquid Glass over hand-rolled gradients:

- **Panel material**: baseline `NSVisualEffectView` (works on every supported
  macOS), with SwiftUI `.glassEffect()` layered on **only when running macOS 26**.
  This gets the native feel broadly and real Liquid Glass on Tahoe without
  hard-blocking on the OS version.
- Follow Apple design principles: real vibrancy, automatic light/dark, system
  accent + SF Symbols, standard control metrics, full keyboard/accessibility
  support.
- Replace the bespoke `glassPanel`/`glassInset` gradient stacks where a native
  material gives the same look with correct behavior for free.

Scope notes:

- **The menu-bar glyph is always a flat monochrome template image** on every
  macOS version. Liquid Glass / Icon Composer never applies to it. The "Tahoe vs
  flat" question is **app-icon only**.
- The native Settings window + onboarding are **out of scope here** — see
  "Out of scope (separate plan)" below.

---

## Decision locked: one mark, three renderings — the "gauge droplet"

We keep the existing droplet, but the droplet stops being decoration and
**becomes a gauge**: its juice fill level encodes remaining capacity.

- **Full = the droplet we already ship.** A solid `drop.fill` is just the 100%
  state. As capacity drains, a waterline appears and recedes.
- **Low = a literal last drop.** Because the teardrop is widest at the bottom
  bulb, the final juice pools into a small bead — the metaphor and the data
  agree.
- The cup/"juicebar" silhouette is **rejected** for the glyph: at 18 pt it reads
  as a pill/dash and collides with the battery icon a few slots away. (It also
  reads as a pint glass.) Kept only as an explored alternate.

The same droplet renders three ways:

| Surface | Rendering | Color |
| --- | --- | --- |
| Menu bar | Monochrome **template** glyph, fill = live level | System-tinted (white/black), amber only when low |
| Panel header | Small colored droplet, fill = aggregate level | Lime→green juice, tinted by judgment |
| Dock / Spotlight / app icon | Full hero render | Lime→green juice on dark squircle |

Uniformity comes from the shared silhouette + wave + palette, not from using one
rendering everywhere. Splitting template glyph from hero icon is the native
pattern (battery glyph vs. app icons), so app icon and menu-bar glyph differing
is correct, not a compromise.

### Design assets

- Chosen hero: [`design/assets/promptjuice-gauge-droplet-appicon.svg`](../design/assets/promptjuice-gauge-droplet-appicon.svg)
  (+ `-preview.png`).
- Rejected cup alternates (keep for reference):
  `promptjuice-gauge-glass-appicon.svg`, `promptjuice-gauge-glass-concept.svg`.
- Interactive gauge demos were used to validate 18 pt legibility across fill
  levels and both bar appearances.

---

## Work area 1 — Menu-bar gauge glyph

Goal: replace the static `drop.fill` with a live droplet gauge whose fill =
remaining capacity, behaving like the battery icon.

Touch points: [`PromptJuiceIcon.statusBarImage()`](../app/PromptJuice/UI/PromptJuiceIcon.swift),
[`AppDelegate.configureStatusItem()` / `startTicker()`](../app/PromptJuice/App/AppDelegate.swift).

### Behavior

- Glyph = droplet **outline** + a **clipped juice fill** at a waterline derived
  from a 0–100 value. Outline and fill use the **same template color** (level is
  shown by filled-vs-empty area, exactly like the battery).
- Keep `isTemplate = true` so the system tints it for light/dark/active bars.
- **Amber low state**: when any provider is "use soon" / nearly empty, swap the
  template for an amber-tinted image (the battery turns yellow/red the same way).
  Off above the low threshold.
- **Quantize the fill to ~8–10 discrete steps** so the level reads as deliberate
  jumps, not sub-pixel jitter on every tick. This also fixes the droplet's one
  weakness: the 90–100% range is visually subtle because the teardrop narrows to
  a point at the top.
- Accessibility label carries the live value, e.g. "PromptJuice: 43% left"
  (replaces the static "PromptJuice menu").

### Plumbing

- `statusBarImage()` gains parameters: a remaining value and a low/normal flag.
  Drawn with `NSImage(size:flipped:)` (vector path each render) rather than an SF
  Symbol.
- `AppDelegate` updates `button.image` when snapshots change. The 1 s `ticker`
  already exists; recompute the glyph there (cheap; only redraw when the
  quantized step or low-state flips).
- **Which number drives the glyph (decided)** — the menu-bar glyph has **no
  selection state**: when the bar is visible the panel is closed, so it always
  shows one stable aggregate = the **minimum remaining % among available
  providers**, amber when any provider is `shouldUseSoon`. Rationale: it answers
  "how much capacity is left" and the lowest provider runs out first.
- Provider rows are display-only. The panel header and menu-bar glyph both show
  the aggregate across visible session readings.

### Checklist

- [ ] Add a parameterized droplet-gauge template renderer in `PromptJuiceIcon`.
- [ ] Quantize fill to N steps; tune N for 18 pt legibility.
- [ ] Add amber low-state variant.
- [ ] Drive glyph from aggregate snapshot value; update on ticker.
- [ ] Live accessibility label with the current value.
- [ ] Verify on light bar, dark bar, and in the active/highlighted state.

---

## Work area 2 — App icon hero (droplet)

Goal: ship the hero droplet as the Dock/Spotlight/app icon, replacing the
landscape cup currently drawn in code.

Touch points: [`scripts/generate_app_icon.swift`](../scripts/generate_app_icon.swift),
[`PromptJuiceIcon.appIconImage()` / `drawAppIcon()`](../app/PromptJuice/UI/PromptJuiceIcon.swift).
Note: `drawAppIcon` is currently **duplicated** between the app and the script.

### Changes

- Redraw as the **vertical droplet** (lime→green juice, wave meniscus, `>_`
  prompt cursor in the juice, soft specular highlight). Reference SVG:
  `promptjuice-gauge-droplet-appicon.svg`.
- **Size-based detail cutoff**: drop the `>_` cursor and highlight below ~64 px
  so the 16/32 px icns renders stay clean. The generator renders one drawing at
  all ten sizes today — add the cutoff there.
- **Collapse the duplication**: one source of truth for `drawAppIcon` so the
  in-app icon and the generated `.icns` can't drift.
- Fix two artifacts from the current cup icon: the lime glow ellipse has a hard
  edge (needs real blur or removal); the self-drawn 22%-radius squircle risks
  double-rounding on macOS 26.
### Format: flat `.icns` now, Icon Composer later (decided)

- **Now**: ship the flat `.icns` droplet via the existing script. It works on
  every macOS version and already looks good. The app icon is lower-leverage than
  the panel + live glyph, so it should not block them.
- **Later (polish pass)**: re-author as a layered Icon Composer `.icon`
  (background / glass / juice / cursor) for Tahoe's Liquid Glass — system
  specular highlights + automatic light/dark/tinted/clear. Authored in the Icon
  Composer GUI (a workflow change, not a script tweak); keep the `.icns` as the
  pre-26 fallback. This is an upgrade that *adds* glass on 26 without losing
  older-OS support.

### Checklist

- [ ] Rewrite `drawAppIcon` to the vertical droplet.
- [ ] Add size-based detail cutoff.
- [ ] De-duplicate `drawAppIcon` (shared source).
- [ ] Fix glow edge + corner double-rounding.
- [ ] Regenerate `.icns`; verify 16→1024.

---

## Work area 3 — Juicebar panel refinements

Goal: tighten hierarchy and semantics so the panel answers the question, not
just reports numbers. Touch points:
[`PromptJuicePanelView`](../app/PromptJuice/UI/PromptJuicePanelView.swift),
[`PromptJuiceViewModel`](../app/PromptJuice/Services/PromptJuiceViewModel.swift),
[`AlertEngine`](../app/PromptJuice/Services/AlertEngine.swift).

### 3.1 Title = the verdict

- The panel uses one user-summoned surface. The header headline is the verdict
  ("Plenty of prompt juice left" / "Use prompt juice soon").
- Subtitle (`detail`) names the visible provider or providers driving the reset,
  e.g. "Claude and Codex reset in 4h 5m".

### 3.2 Label the countdown

- Rows use `fullResetText` as plain trailing text, e.g. "resets in 4h 5m".
  The header and row countdowns now share the same phrase.

### 3.3 Quiet chips in the healthy state

- Each healthy row currently says the same thing three times: a status chip,
  "92% left", and a 92% bar (`statusChip` + `percentText` + `CapacityBar`).
- **Only render the chip when it adds a judgment the number doesn't** ("Use
  soon", "Last drop"). Healthy rows show no chip. Silence in the healthy state is
  what makes the amber state loud.
- Drop the repeated word "left": "92%" alone reads fine next to the bar.
- This is a rule change in how `statusText` / the chip is gated, not new copy.

### 3.4 Rebrand the header icon

- The header icon is a **blue** `drop.fill` (`iconName`/`iconColor`, manual
  case). Blue is off-brand (juice is lime green) and collides with Codex's dot
  color (`providerColor` = cyan for Codex), so it weakly reads as a Codex glyph.
- Replace with the **gauge droplet**, fill = aggregate level, tinted by the same
  judgment color as the chips. Then menu bar, panel header, and app icon are one
  mark.
- The header droplet shows the aggregate across visible session readings, and
  the menu-bar glyph uses the same fill/tint.

### 3.5 Fix the color semantics (two failure modes, two colors)

- Today `capacityColor` returns **red** for both `shouldUseSoon` (which can fire
  at high remaining % when reset is near) and for `< 15%` remaining. Result: red
  "Use soon" at 69% left — crying wolf.
- Split severity:
  - **Amber = use-it-or-lose-it** (plenty remaining, reset imminent →
    `shouldUseSoon`).
  - **Red = nearly empty / about to be blocked** (low remaining %).
- The **menu-bar glyph tint follows the same judgment**, so all three surfaces
  agree. Best done by giving `AlertEngine` a single severity/status enum that the
  row chip, the row color, and the glyph all read from.

### 3.6 Panel material

- The panel is a borderless window with a hand-built dark glass gradient
  (`glassPanel` / `glassInset`). Move to **native Liquid Glass**: back it with
  `NSVisualEffectView` (popover/HUD material) or SwiftUI `.glassEffect()` on
  macOS 26 for real vibrancy, free light-mode support, and the first-party feel.
  Retire the bespoke gradient stacks where the native material matches.
- The `✕` close button and click-outside dismissal close the user-summoned
  panel. Use-soon interruptions arrive as macOS notifications, with the Juicebar
  opened from the banner tap or the menu-bar droplet.

### Checklist

- [ ] Verdict headline + provider-named reset subtitle.
- [ ] Labeled reset countdown in rows.
- [ ] Gate the status chip; hide in healthy state; drop redundant "left".
- [ ] Gauge-droplet header icon, judgment-tinted.
- [ ] Single severity enum → amber (use-soon) vs red (nearly empty), shared by
      chip/row/glyph.
- [ ] Evaluate `NSVisualEffectView` panel backing.

---

## Work area 4 — Menu-bar interaction model

Question: is "one click opens the bar" right? Should settings be a second click /
right-click? What's the macOS standard?

### What macOS apps actually do (research)

- **Apple HIG / menu bar extras**: a menu bar extra displays status and has a
  menu to change settings — the battery icon shows live state and its menu holds
  battery settings. The native expectation is **single click → reveal the thing**
  (menu or popover).
- **De-facto standard for apps with a rich panel** (the common `NSStatusItem`
  pattern): **left-click toggles the popover/panel; right-click (and
  Control-click) shows an `NSMenu`** with settings/quit. Implemented by sending
  the button action on both `.leftMouseUp` and `.rightMouseUp` and branching on
  the event.
- **Modifier idiom**: Option-click reveals advanced/detailed info on many system
  extras (e.g. Option-click Wi-Fi/volume). A natural home for a detailed
  breakdown later.
- **Double-click is essentially unused** in the menu bar — undiscoverable and
  not expected. Not a place to hang settings.

Sources:
[Apple HIG — Menus](https://developer.apple.com/design/human-interface-guidelines/menus),
[Implementing left/right click for a status item](https://medium.com/@clyapp/implementing-left-click-and-right-click-for-menu-bar-status-button-in-macos-app-c3fc0b981cf0),
[Implementing right-click for NSButton — Jesse Squires](https://www.jessesquires.com/blog/2019/08/15/implementing-right-click-for-nsbutton/),
[How to support right-click menu to NSStatusItem](https://onmyway133.com/posts/how-to-support-right-click-menu-to-nsstatusitem/).

### Verdict: we are already on the standard

`AppDelegate` already does the right thing: `sendAction(on: [.leftMouseUp,
.rightMouseUp])`, then `statusItemClicked` routes right-click/Control-click to a
context menu and left-click to the panel. The accessibility help already says
"Left click to show usage. Right click for PromptJuice controls." **Keep this.**

### Changes (small, additive)

- **Do not** add double-click or two-click-to-settings — non-standard and
  undiscoverable.
- **Keep the current right-click menu as-is** (Show Usage, Refresh, Usage Source,
  thresholds, Request Notifications, Quit). A richer Settings window is a separate
  plan; don't rebuild it here.
- **Stretch**: Option-click the menu-bar icon → open the panel pre-expanded to
  the detailed per-provider breakdown (matches the macOS Option-click idiom).
- **Note (not a change now)**: the panel is positioned **top-center** rather than
  anchored under the icon like a standard `NSPopover`. That's a deliberate
  "Juicebar/HUD" identity from `PLAN.md`; fine to keep, just an intentional
  divergence to revisit if discoverability suffers.

> Deferred to the separate Settings/onboarding plan: the in-panel gear, a native
> Liquid Glass Settings window, "Launch at Login", and "Check for Updates…". When
> that lands, the gear opens the window and the threshold/usage-source controls
> move out of the menu.

### Checklist

- [ ] Keep left=panel / right=menu; no double-click. (Already implemented —
      verify only.)
- [ ] (Stretch) Option-click → detailed breakdown.

---

## Suggested sequencing

1. **Panel refinements (Work area 3)** — highest daily value, no new asset
   pipeline. The severity enum (3.5) unblocks the glyph tint in (1).
2. **Menu-bar gauge glyph (Work area 1)** — reuses the severity enum; the
   headline change to the icon.
3. **Interaction (Work area 4)** — mostly verify-only; current left/right model
   is already standard. Optional Option-click stretch.
4. **App icon hero (Work area 2)** — self-contained flat `.icns`; can land
   anytime. Icon Composer upgrade is a later polish pass.

---

## Acceptance criteria

- Menu-bar glyph is a droplet whose fill tracks remaining capacity, quantized,
  template-tinted, amber only when low; accessibility label states the value.
- App icon is the vertical droplet; clean from 16 px to 1024 px; one shared
  `drawAppIcon`.
- Panel headline is always a verdict; the reset countdown is unambiguous; healthy
  rows are quiet (no chip, no triple-repeat); header icon is the brand droplet.
- Amber and red mean two different things, consistently across chip, row, and
  glyph.
- Left-click opens the panel; right-click/Control-click opens the menu; no
  double-click behavior. (Settings window + gear are a separate plan.)
- `swift build`, `swift test`, and the macOS app build pass; reset-countdown
  tests added (the open TODO in `PLAN.md`).

---

## Out of scope (separate plan): Settings + onboarding

Pulled out of this doc to design on its own.

- **Today**: the only "settings" is the right-click menu — Usage Source
  (fixture / live Codex), Remaining-Time threshold (30/45/60/90m),
  Remaining-Juice threshold (25/40/50/60%), Request Notifications, plus Show
  Usage / Refresh / Quit. **No onboarding exists** (just a usage alert ~0.8 s
  after launch).
- **Future, separate plan**: a native SwiftUI `Settings` scene (Liquid Glass,
  `⌘,`) with General / Alerts / About sections; an in-panel gear that opens it;
  "Launch at Login" and "Check for Updates…"; and a first-run onboarding flow
  (permissions, provider connection, what the gauge means). The min-macOS target
  question lives with that plan.

## Resolved decisions

- **Glyph aggregate** → menu-bar glyph always shows one stable aggregate (lowest
  remaining provider); no selection state. Selection is panel-only. (Work area 1.)
- **Straw** → **strawless** droplet everywhere; the chosen hero asset is already
  strawless. Straw lives only in the rejected cup alternate.
- **Menu-bar glyph is always a flat template** on every macOS version; Liquid
  Glass / Icon Composer is app-icon-only.
- **App-icon format** → flat `.icns` now; Icon Composer (`.icon`) as a later
  polish pass. (Work area 2.)
- **Panel material** → `NSVisualEffectView` baseline + `.glassEffect()` on macOS
  26 only, so OS version doesn't block this work.
- **Settings + onboarding** → separate plan (see above).

## Open questions for you

- None blocking. When you're ready, the next decision is for the *separate*
  settings/onboarding plan: the minimum macOS version to support (decides how
  hard we lean on native Liquid Glass vs. a styled fallback).
