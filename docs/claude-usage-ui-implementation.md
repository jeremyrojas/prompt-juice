# Claude /usage UI implementation spec — v7 (adjudicated)

Companion to `claude-usage-ui-spec.html` (mockups + catalog). This version folds in all four
adjudication rounds with Codex (ledger D1–D19). It supersedes every earlier version.

Status: **B1, B2, B3 APPROVED · B5 DEFERRED (optional, not now)** — see section 9.
**Design ready. Execution awaits Jeremy's explicit start instruction.** B5 no longer gates
public release (optional courtesy + passive-data fallback ready).

**Slice 0 (Codex):** this file is the binding spec. Copy it into the worktree at
`docs/claude-usage-ui-implementation.md`, and add a banner to `claude-usage-plan.md` marking its
superseded decisions (minimum 2.1.181, classic-TUI fallback, Advanced pickers, updateRecommended,
bridge needsReview, the old state models) as replaced by this document.

Paths relative to worktree root `/Users/jeremyrojas/worktrees/prompt-juice/claude-usage`
(base `4d349d1`). Line numbers are anchors, not guarantees.

## Goal-level execution policies (binding overrides)

These policies come from the implementation goal and govern the conflicting capture and
third-party-fixture language later in this imported specification.

### Capture execution policy

Jeremy authorizes Codex to execute the prepared read-only capture harness during Phase 1. The
only authorized Claude Code invocations are:

- `claude --version`
- `claude auth status`
- one controlled `/usage` capture

No login, logout, account switching, installation, settings mutation, synthetic model prompt,
or other Claude command is authorized.

Before executing the harness:

- Author and test the sanitizer with synthetic fixtures.
- Create a private scratch directory with mode `0700`.
- Create a dedicated empty controlled working directory inside it.
- Run every Claude capture process from that controlled working directory.
- Store raw files with mode `0600`.
- Redirect raw output directly into private files.
- Keep raw capture output out of the Codex task, terminal transcript, test logs, Git history,
  and UI.
- Detect token-, secret-, credential-, email-, account-, organization-, UUID-, username-, and
  absolute-path-shaped data.
- Abort safely when sanitization cannot confidently remove unexpected sensitive fields.
- Preserve parser-relevant ANSI/control sequences, timestamp syntax, timezone form, labels,
  spacing, and surrounding terminal structure.
- Inspect only sanitized output.
- Commit only sanitized fixtures after automated privacy checks pass.
- Keep private raw files untracked, report their location, and wait for Jeremy's direction
  before deleting them.

The `/usage` capture sends no model prompt. Claude Code may perform its normal authenticated
usage-status request and update its own normal local cache.

### CodexBar reference-only policy

CodexBar may be consulted as a public architectural reference. Every PromptJuice fixture is
independently authored from this binding specification and PromptJuice's sanitized real
captures. CodexBar code, fixtures, parser strings, test cases, comments, and repository assets
remain outside PromptJuice. The Phase 1 report records that no third-party material was
imported. With zero imported material, a CodexBar license verdict, attribution file, and
third-party fixture inventory are unnecessary.

## Phase 1 captured evidence (2026-07-21)

Sanitized real captures from Claude Code 2.1.214 establish these implementation facts:

- `claude --version` emits `2.1.214 (Claude Code)`.
- Subscription `claude auth status` JSON contains `loggedIn`, `authMethod`, `apiProvider`,
  `email`, `orgId`, `orgName`, and `subscriptionType`. The captured subscription value for
  `authMethod` is `claude.ai`; `apiProvider` is `firstParty`; `subscriptionType` is `max`.
- The flat screen-reader Usage panel uses the tab row `Settings  Status   Config   Usage
  Stats`, includes session-local cost/duration/change counters, and then presents `Current
  session`, `Current week (all models)`, and model-specific weekly windows when applicable.
- Observed bars use duplicated accessible text such as `100% 100% used`. Observed reset labels
  include `Resets 11am (America/New_York)` and `Resets Jul 21 at 7pm (America/New_York)`.
- A single capture can contain incomplete and complete redraws. The observed session value
  advanced from 99% to 100%, the all-models weekly value advanced from 38% to 39%, and the
  later complete screen added a model-specific weekly window. The parser must select the latest
  complete panel.
- The Usage screen can append local contribution analysis and usage-credit copy after the quota
  windows. Those sections stay outside quota parsing.

### Workspace-trust architecture finding

Claude Code's project-trust gate appears for a new private empty working directory under both
the normal safe-mode invocation and `--dangerously-skip-permissions`. Permission bypass does
not bypass workspace trust. The real Usage fixture therefore used Jeremy's explicitly approved
existing trusted checkout as a fixture-only working-directory exception, while retaining safe
mode, the empty tool allowlist, one `/usage` input, private raw output, and sanitization.

This finding invalidates the unattended fresh-probe-directory assumption for the production
transport. Phase 2 architecture review must select a workflow that satisfies workspace trust,
authentication, zero model prompts, and the no-settings-mutation product requirement before
the production PTY transport proceeds.

---

## 1. State model (three axes + one migration axis)

Replaces `ClaudeLiveUpgrade` (`app/PromptJuice/Services/PromptJuiceViewModel.swift:4-8`, computed
`:195-202`). The 13-state catalog below is a **presentation test catalog**, not a state machine.

```swift
enum ClaudeAccessState {
    case checking
    case cliMissing
    case updateRequired(installed: Version, minimum: Version)   // minimum 2.1.208 (B2)
    case signedOut(reason: ClaudeSignInReason)   // initial | reauthenticationRequired
    case subscription(plan: String?)
    case apiBilling            // first-party Console/API only
    case externalProvider(ExternalProvider)   // bedrock, vertex, foundry, gateway
    case unsupportedAuth
    case authCheckFailed
}
enum ClaudeSignInReason { case initial, reauthenticationRequired }  // expired/revoked OAuth,
                                                                    // missing scope → reauth
enum ClaudeRefreshState {
    case idle
    case refreshing
    case backingOff(nextAttemptAt: Date)   // ALWAYS valid; client-owned 5→15→30→60m ladder
    case failed(ClaudeProbeFailure)        // timeout, offline, parse, process — distinct causes
}
// Snapshot (existing) carries source, confidence, updatedAt, session/weekly windows.
// LegacyBridgeStatus { none, removable } is an independent fourth axis (needsReview deleted
// with the review journey — unprovable ownership means leave untouched, show nothing).
```

Invariants:
- `.backingOff` never lacks a date. Corrupt/expired persisted dates are repaired by the
  coordinator (schedule fresh attempt) or degrade to a generic refresh failure. No
  unknown-retry UI state exists.
- `/usage` runs ONLY for confirmed `subscription`. All other categories skip it.
- `isFreshSessionWindow` becomes provider-evidence-gated: only the Codex app-server signal can
  set it. Claude at 0% used can never produce "Fresh window" anywhere, including
  `manualSubtitle` (`PromptJuiceViewModel.swift:312`).
- Never surface `statusDetail` verbatim (leak at `PromptJuiceViewModel.swift:968`).
- Snapshot sources: add `claudeUsageCLI`; keep `.claudeStatusline` alive through the
  transition (plan wins) — both coexist until the dogfood gate.

### 2.1.208 cached-bars rule (D13)
When `/usage` renders last-known bars with an "as of" note (endpoint rate-limited):
- Parse values + "as of" timestamp → emit a **saved reading** with `updatedAt` = the "as of"
  time (never probe time). Not a failed probe.
- Coordinator schedules cooldown from the observed outcome. `.backingOff` with no snapshot
  only when zero usable values were recovered.
- "As of" is a measurement timestamp, not a retry time — `nextAttemptAt` stays client-owned.
- Edge: values parse, timestamp doesn't → keep prior snapshot if any, else parse-failure path.
  Never fabricate freshness.

### Auth classification (policy D strengthened — B1 APPROVED)
No environment mutation. Enumerate the known, documented billing-affecting credential sources
for supported Claude Code versions, as visible to the exact child process (not "every source" —
future releases may add sources; unknown combinations already fail closed):
app-visible env (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`,
`ANTHROPIC_BASE_URL`, Bedrock/Vertex/Foundry flags, gateway/proxy vars), `~/.claude/settings.json`
(`apiKeyHelper`, env block, provider/base-URL settings), managed settings, plus
`claude auth status` (EXPECTED/PROVISIONAL field names — `loggedIn`, `authMethod`,
`apiProvider`, `subscriptionType` — unconfirmed until Jeremy's sanitized capture lands) as
corroborating evidence — never sole proof of effective billing.

Forward-compat rule (D14): additive unrelated JSON fields are IGNORED. Unknown values of
billing-relevant discriminators, or missing required billing evidence, fail closed to
`unsupportedAuth` (skips /usage). Subscription requires auth-status agreement AND no overriding
credential source. No separate `/status` probe in v1; use in-band plan labels on the /usage
screen as confirmation when present.

Reauthentication: expired/revoked OAuth or missing scope classifies as
`signedOut(reason: .reauthenticationRequired)`. `ClaudeSignInReason` and the snapshot are
independent axes, so state 7 is a four-way cross-product, each its own presentation scenario
with its own test:

| Variant | Juice Bar | Settings subtitle | Footnote |
|---|---|---|---|
| initial + estimate | `~42% left` | `Estimate · signed out of Claude Code` | sign-in footnote below |
| initial + none | `Sign in needed` + Sign in capsule | `Signed out of Claude Code` | — |
| reauth + estimate | `~42% left` | `Signed out of Claude Code · sign in again · showing local estimate` | reauth footnote below |
| reauth + none | `Sign in needed` + Sign in capsule | `Signed out of Claude Code · sign in again` | — |

Popover status line is cause-matched — never "sign in once" for an expired session:
initial → `Claude Code is signed out. Sign in once and PromptJuice takes it from there.`
reauth → `Claude Code's sign-in has expired. Sign in again and PromptJuice takes it from there.`
The Sign In sheet and button are identical for both causes. Fixtures: an expired/revoked-OAuth
auth-status shape; transition test valid session → reauth-required → Sign In journey →
connected.

---

## 2. Copy conventions

- Freshness formatter: `Updated just now` / `Updated 12 min ago` / `Updated at 3:14 PM` /
  `Updated yesterday at 3:14 PM` / `Updated Jul 18 at 3:14 PM` (relative < 1h). Tooltips use the
  lowercase clause form (`· updated at 3:14 PM`).
- Backoff: `next check at 3:45 PM` (row: `Next check 3:45 PM`). "Rate limited" only ever with
  "usage checks" as subject, never on a row.
- Failure: `having trouble updating` / `having trouble checking`. Estimate keeps `~` + the word.
- "Claude Code" = CLI, "Claude" = account. No bridge/statusline/PTY/terminal-dependency
  language; `/usage` only in the popover body. Buttons Title Case (spelled-out "and"); prose
  sentence case; no em dashes; `·` separator; SF Symbols only (`info.circle`, `clock`,
  `doc.on.doc`).
- "Set up" survives only as an umbrella concept; never a state-specific action label (D18).
- WITHDRAWN, banned everywhere: "Nothing is sent to Claude" · "Your Claude quota is fine." ·
  "never reads your conversation text" · "PromptJuice itself makes no network calls".

---

## 3. Catalog — 13 states / 22 scenarios (+1 legacy)

| # | State | Variants | Row trailing | Tooltip | Settings subtitle | Button | Popover status line |
|---|---|---|---|---|---|---|---|
| 1 | Checking | none / cached shown (2) | `Checking…` or number | `Checking usage with Claude Code` | `Checking…` | — | `Checking usage with Claude Code now.` |
| 2 | Current | (1) | `42% left` | `From Claude Code · updated just now` | `Updated just now` | — | `Right now it's current, read a moment ago.` |
| 3 | Saved (incl. cached bars) | (1) | `42% left` + clock | `From Claude Code · updated at 3:14 PM` | `Updated at 3:14 PM` | — | `Showing your last reading from 3:14 PM. PromptJuice refreshes it automatically.` |
| 4 | Out of quota | (1) | `0% left` | `Claude is out until reset · updated at 3:14 PM` | `Updated at 3:14 PM` | — | as 3 |
| 5 | Backing off | cached / none (2) | number+clock / `Next check 3:45 PM` | `… · next check at 3:45 PM` / `Usage check paused · next check at 3:45 PM` | `Updated at 3:14 PM · next check at 3:45 PM` / `Next check at 3:45 PM` | — | `The last usage check was rate limited. PromptJuice tries again at 3:45 PM.` (+ `Showing your 3:14 PM reading in the meantime.`) |
| 6 | CLI missing | estimate / none (2) | `~42% left` / `Claude Code needed` + **Install** capsule | `Install Claude Code to read your plan usage` (est: `Estimated from Claude Code's activity logs on this Mac`) | `Claude Code not installed` (+ `· showing local estimate`) | `Install…` | `Claude Code isn't installed yet. Install it and sign in once. Claude Desktop, Claude.ai, and Claude Code share the same plan usage.` |
| 7 | Signed out | initial+est / initial+none / reauth+est / reauth+none (4) | `~42% left` / `Sign in needed` + **Sign in** capsule | `Sign in to Claude Code to read your plan usage` | initial: `Signed out of Claude Code` (est: `Estimate · signed out of Claude Code`); reauth: `Signed out of Claude Code · sign in again` (est: `… · showing local estimate`) | `Sign In…` | initial: `Claude Code is signed out. Sign in once and PromptJuice takes it from there.` reauth: `Claude Code's sign-in has expired. Sign in again and PromptJuice takes it from there.` |
| 8 | Update required < 2.1.208 | cached-or-estimate / none (2) | `Update needed` + **Update** capsule | `Update Claude Code to read your plan usage` | `Update Claude Code to track plan usage` | `Update…` | `PromptJuice needs Claude Code 2.1.208 or newer to read plan usage.` |
| 9 | API billing (first-party) | neutral (1) | `API billing` | `Claude Code is using API billing · plan quota unavailable` | `API billing · Claude Console tracks spend` | — (toggle) | Console explanation + subscription sign-in close (first-party ONLY) |
| 10 | External provider | neutral (1) | `External provider` | `Claude Code uses {provider} · plan quota unavailable` | `{Provider} · plan quota unavailable` | — | `Claude Code is set up to use {provider}, which bills through your cloud account. Plan quota doesn't apply, so there's no juice bar to fill.` (NO sign-in close — override survives login under policy D) |
| 11 | Unknown auth | neutral (1) | `Usage unavailable` | `This Claude Code setup isn't supported yet` | `Account type not recognized · usage not tracked` | — | `Claude Code is signed in with an account type PromptJuice doesn't recognize yet, so usage tracking is off for it. A future update may add support.` |
| 12 | Probe/auth/parse failure | cached / estimate / neither (3) | number+clock / `~42% left` / `Having trouble checking` | `From Claude Code · updated at 3:14 PM · having trouble updating` / `Couldn't check usage with Claude Code · trying again automatically` | `Having trouble updating · showing 3:14 PM reading` / `Estimate · having trouble reading Claude Code` / `Having trouble checking usage` | `Retry` | `PromptJuice couldn't get a new reading from Claude Code. It's showing your 3:14 PM reading and will keep trying.` / `PromptJuice couldn't check usage with Claude Code. It will keep trying automatically.` |
| 13 | Provider off | (1) | row hidden | — | `Off` | — | — |

Deleted states: Fresh window (Claude) · rate-limited-retry-unknown · update-recommended
(no newer-version signal exists; only below-minimum update-required).

Estimate footnotes (Settings, cause-matched): install → `This is an estimate from Claude Code's
activity logs on this Mac. Install Claude Code and sign in, and PromptJuice switches to direct
readings automatically.` · sign-in (initial) → same with `Sign in to Claude Code and…` ·
sign-in (reauth) → `This is an estimate from Claude Code's activity logs on this Mac. Sign in
to Claude Code again and PromptJuice switches back to direct readings automatically.` ·
failing → `…PromptJuice checks about every 15 minutes and switches back automatically.`

Legacy (independent axis, Settings-only cards): `Legacy bridge detected` /
`PromptJuice's old status-line bridge is still in ~/.claude/settings.json. It's no longer
needed.` + `Remove…`. The needs-review card is dropped (bridge never shipped externally); if
ownership can't be proven on some rare machine, leave the config untouched and show nothing.

### Aggregate rules (D8)
Only quota-bearing snapshots (subscription readings incl. estimates, and Codex) feed aggregate
severity, menu-bar %, glyph, and notifications. Neutral rows (9–11) are enabled, visible,
non-quota-bearing. No quota-bearing snapshot at all → muted droplet, no % badge, header
`Claude plan usage unavailable` + category detail (`Claude Code is using API billing` /
`Claude Code uses an external provider` / `Account type not recognized`) — never healthy or
100%. With Codex connected, Codex alone drives everything aggregate; merged "running low on
both" never includes a neutral Claude.

Fresh-window matrix tests: Claude-only 0% → `100% left · resets in …`, header normal verdict;
Codex-only genuine signal → unchanged; Codex fresh + Claude active → Codex row `Fresh window`,
header counts down Claude; Codex active + Claude 0% → standard merge, no fresh anywhere.

---

## 4. Settings and sheets

Settings (430×494 unchanged): Providers card = Claude row + Codex row. **Advanced pickers are
deferred out of v1** (Smart cadence automatic; future cadence control labeled
`Refresh Claude usage`). Info icon becomes a click-opened button (was hover). Conditional
button and footnote render per catalog. Legacy cards only when detected.

Measurement popover (final):
- Title: `How this number is measured`
- Body: `PromptJuice reads your Claude plan usage with Claude Code's built-in /usage command.
  These are the same numbers Claude shows you. Claude Desktop, Claude.ai, and Claude Code share
  one plan allowance, so this covers all of them.`
- Privacy paragraph (TARGET copy, gated G1–G4 below): `PromptJuice asks Claude Code for your
  plan usage about every 15 minutes and sends no model prompt. When an estimate is needed, it
  scans local Claude Code activity records and extracts usage totals and timestamps. It does
  not store, display, or transmit conversation text.`
- Dynamic status line per catalog · `Learn more`.

Manual refresh feedback: `Refreshing usage.` / `Usage refreshed.` / debounced
`Just checked · up to date`.

### Sheets (D18 final) — one reusable guidance sheet, three kinds
Shared: numbered steps, explainer, quiet `Check Again`, buttons `Done` + primary
`Copy and Open Terminal`. NO live polling, NO auto-flipping footer in v1 (post-dogfood polish).

Layout requirements (from mockup review): each command sits in its OWN full-width block below
the step text (not inline), monospace, with a copy affordance, and MUST wrap/contain within the
sheet — the install `curl … | bash` command overflows otherwise. `Check Again` and every button
are single-line (`white-space: nowrap`); size the sheet (~360pt) so the three-control row
(`Check Again` / `Done` / `Copy and Open Terminal`) never wraps.

Terminal target: `Copy and Open Terminal` copies the command to the clipboard AND launches
macOS's built-in Terminal.app via `NSWorkspace` by bundle id `com.apple.Terminal`. This is
deterministic — macOS exposes no "default terminal" setting to honor, so we don't guess iTerm/
Warp/Ghostty. Because the command is also on the clipboard, users of another terminal can paste
it into their own; we don't detect or launch third-party terminals in v1. Note: launching may
activate an existing Terminal window rather than opening a new one — UI copy promises only
"copies the command and opens Terminal", nothing about windows.

Shared explainer (verbatim): `PromptJuice will copy the command and open Terminal. Paste it,
press Return, then come back here. PromptJuice will check again automatically.`
Sign-in variant ends `…press Return, then follow the browser prompts. PromptJuice will check
again automatically.` Unknown-provenance variant drops the "copy" clause (nothing is copied).

| | Install | Sign in | Update |
|---|---|---|---|
| Sheet title | `Install Claude Code` | `Sign in to Claude Code` | `Update Claude Code` |
| Subtitle | `One-time setup. Claude Desktop, Claude.ai, and Claude Code share the same plan allowance.` | `Use the same Claude account you use in Claude Desktop or Claude.ai.` | `PromptJuice needs Claude Code 2.1.208 or newer to read plan usage.` |
| Copied command | `curl -fsSL https://claude.ai/install.sh \| bash` (native; alt: `brew install --cask claude-code`, `npm install -g @anthropic-ai/claude-code`) | `claude auth login` — the documented focused sign-in flow (cli-reference; flags `--email`, `--sso`, `--console`). `/login` stays as secondary copy for users already inside Claude Code | selected by install-method detection, see below |
| Step 2 | `Once installed, sign in with your Claude account` | `Complete the browser prompts, then return to PromptJuice.` | `PromptJuice picks up the new version automatically.` |
| Extra | download link inline (claude.com/claude-code) | — | footer `Current version {x} · required 2.1.208`; native installs auto-update in background, so this state is rare |

**Update command by executable provenance** (detect from the resolved `claude` path):
native (`~/.local/bin/claude` → `~/.local/share/claude/versions/…`) → `claude update` ·
Homebrew (Cellar/Caskroom paths, Apple Silicon `/opt/homebrew` or Intel `/usr/local`) →
`brew upgrade claude-code` · npm global → `npm install -g @anthropic-ai/claude-code@latest` ·
unknown → the sheet shows the resolved executable path, then native, Homebrew, and npm
alternatives as three separate full-width command blocks, each with its own copy affordance;
the primary action for this variant becomes `Open Terminal` and copies NOTHING automatically
(`Copy and Open Terminal` is reserved for a known provenance with one selected command). Never
copy a guessed command. Fixtures: native, Homebrew AS, Homebrew Intel, npm, custom symlink,
unknown — plus a presentation and action test for the unknown-provenance sheet variant.
Rendered validation of the unknown-provenance mockup: 368pt wide, no horizontal overflow,
single-line action row. At 135% text enlargement it grows vertically (~550→739pt, action row
still one line, still no horizontal overflow) — so accessibility text sizes require a TALLER
sheet with a scrollable content region, never a wider one; the action row is pinned and never
wraps.

**Journey-scoped rechecks** (Check Again AND debounced ≥30s app-activation re-probe; never
`/usage`): CLI missing → locator + version + auth · Update required → version + auth ·
Signed out → auth only.

**Install → Sign in transition:** when the open Install sheet's recheck finds the CLI present
but signed out, the sheet advances to the Sign In journey in place — a two-stage flow
(Install → return → Sign in → return → connected), never a dead end.

Behavioral limits (D10): both recheck paths — `Check Again` AND the ≥30s-debounced
app-activation re-probe — run the SAME journey-scoped check set defined above (CLI missing →
locator + version + auth · Update required → version + auth · Signed out → auth only). That
journey-scoped table is the single rule; no path ever invokes /usage — usage refresh belongs to
the coordinator.

Commands VERIFIED against official docs (code.claude.com/docs/en/setup, /cli-reference,
2026-07): install `curl -fsSL https://claude.ai/install.sh | bash` (native, recommended);
sign in `claude auth login` — the documented focused shell sign-in (subcommands: `auth login`
with `--email`/`--sso`/`--console`, `auth logout`, `auth status`); `/login` is the in-TUI
alternative, kept as secondary copy only; update per install-method detection above. Internal
probes CONFIRMED: `claude --version` → plain text e.g. `2.1.211 (Claude Code)`;
`claude auth status` → JSON by default, exit code 0 = logged in / 1 = signed out, `--text` for
human-readable. The `claude auth status` JSON field names used in this spec (loggedIn /
authMethod / apiProvider / subscriptionType) are EXPECTED/PROVISIONAL — not publicly documented;
the auth classifier stays provisional until Jeremy's sanitized capture confirms them. Whether
`claude auth login` exits cleanly after browser auth completes is undocumented and NOT a slice
gate: the flow depends on app-activation rechecks plus auth status, not on the Terminal process
exiting — record the actual behavior as a dogfood observation.

Legacy removal sheet: `Remove the legacy bridge` · `PromptJuice restores statusLine.command in
~/.claude/settings.json to:` + exact-change preview + legend `Your command, restored` /
`PromptJuice bridge, removed` · `Cancel` / `Remove Bridge` · success `Bridge removed` /
`Your Claude settings are back to normal. Usage now comes from Claude Code's /usage.` There is
no review sheet: LegacyBridgeStatus is only none/removable, and unprovable ownership stays
untouched and silent.

Accessibility: row value mirrors state incl. freshness (`42% left, updated at 3:14 PM, resets
in 2h 30m`); clock icon label `Updated at 3:14 PM` (replaces `Reading from 3:14 PM`); journey
capsules are REAL buttons (current `setUpCue` is a Text with AppKit click routing —
`PromptJuicePanelView.swift:290-302`) labeled `Install Claude Code` / `Sign in to Claude Code` /
`Update Claude Code`, hint `Opens PromptJuice Settings`; info icon is a button.

---

## 5. Gates

**Privacy-copy gate (D15).** The shipping estimator (`ClaudeLocalLogUsageReader`) uses
JSONSerialization over bounded JSONL records with nested dictionary access — the privacy
paragraph is TARGET copy and ships only when:
- G1 estimator refactored to narrow typed decoding (or equivalent extraction boundary) that
  immediately discards conversation-bearing fields, retaining only timestamps, request/message
  identifiers for deduplication, sidechain state, and token totals;
- G2 raw JSONL records and conversation fields can never enter logs, caches, errors, fixtures,
  analytics, or UI state;
- G3 tests prove persisted snapshots contain only derived usage information;
- G4 repository-wide logging review passes.

**Optional B5 compliance note (D16) — not a gate.** Network model (verbatim, also for the
Anthropic request):
PromptJuice contains no Claude HTTP client and receives no Claude credential; it launches the
user-installed Claude Code executable locally; Claude Code may make its own authenticated
request to Anthropic's usage endpoint when /usage runs; PromptJuice parses the resulting
terminal screen; the activity-log estimator performs local file reads and sends no log content
anywhere. DECISION (B5): the Anthropic clarification is an OPTIONAL courtesy, not a gate —
comparable tools ship without it and this approach is more conservative (no credentials, no
model calls). Local, dogfood, and limited use proceed freely; a broad public launch optionally
sends the note or ships with the passive-data fallback (estimator-only) ready. Not pursued now.

**Bridge migration (D17) — SIMPLIFIED (bridge confirmed never shipped externally).** The author
confirms the status-line bridge never shipped beyond their own machines (the one repo recipient
uses Codex, not Claude). Consequences: new installs never get the bridge; the author's own
dogfood machine gets an ownership-verified `Remove…` cleanup (content/hash match, user-authored
status lines preserved, atomic write, script deleted last). The **needs-review path (state 16)
is dropped** — on the vanishingly rare install where ownership can't be proven, PromptJuice
leaves `~/.claude/settings.json` untouched and shows nothing, rather than building a Review UI
for ~0 users. Do NOT convert `ClaudeBridgeInstaller` to cleanup-only yet; keep
`scripts/build_app.sh:36,38` and `ci.yml:18,62` intact until the dogfood gate, then delete.

---

## 6. Fixtures

Category 1 — synthetic, authorable now: flat /usage screens (session only, session+weekly,
0% used, ANSI residue, truncated, malformed); cached-bars set F-RL1 (bars + "as of", session),
F-RL2 (+weekly), F-RL3 (rate-limit text, no bars), F-RL4 (bars, unparseable "as of") plus "as
of" timestamp variants (12-hour, 24-hour locale, timezone/DST transition, ANSI residue inside
the timestamp, malformed); auth status permutations (additive harmless fields, missing required
fields, unknown discriminator values, expired/revoked-OAuth reauth shape); version strings;
locator/provenance outcomes (native, Homebrew Apple Silicon, Homebrew Intel, npm, custom
symlink, unknown); corrupt persisted nextAttemptAt. Probe results carry BOTH the usable
snapshot and the backoff signal (they are not mutually exclusive).

Transition tests: T-RL1 F-RL1/2 → snapshot updated, updatedAt = "as of" time, backingOff, state-3
presentation with next-check suffix · T-RL2 F-RL3 → no snapshot change, backingOff, row
`Next check 3:45 PM` · T-RL3 F-RL4 → prior snapshot retained / parse-failure path, never
fabricated freshness · T-RL4 recovery clears backoff.

Category 2 — sanitized OSS: CodexBar fixtures with repo URL, commit hash, license recorded.

Category 3 — live captures. **Boundary: Codex prepares the harness but never executes it and
never invokes Claude Code. Jeremy runs the approved captures himself after reviewing the
script.** Approved now (B3, read-only): current subscription /usage, `claude auth status`,
`claude --version`. Separately approved FUTURE work, not slice 1: Console login changes
(`claude auth login --console` can replace the current login — never without approval + a
written isolation/recovery plan) and genuine rate-limit captures. The auth classifier stays
provisional until Jeremy's sanitized auth-status capture lands.

Harness requirements: creates a private scratch directory with owner-only permissions (0700)
containing a dedicated EMPTY working directory — every Claude Code capture process runs from
that controlled cwd; stores raw files owner-readable only (0600); redacts emails, organization/account IDs, UUIDs,
usernames, and absolute paths; PRESERVES the lexical timestamp format, timezone shape,
ANSI/control-sequence structure, and surrounding parser-relevant text — it never normalizes
away the exact syntax a fixture is meant to prove; produces sanitized output for Jeremy to
inspect before anything is copied into the repository
(`app/PromptJuiceTests/Fixtures/Claude/`, with provenance header).

## 7. Test/build/docs impact

- **Mandatory Computer Use UI gate:** every implementation slice that changes user-visible
  SwiftUI or AppKit behavior must be exercised in the running PromptJuice macOS app with the
  `@Computer` Computer Use plugin. Verify every affected state, action, transition, sheet,
  popover, tooltip, and Settings row, including rendered copy, layout, button behavior,
  focus/activation behavior, and the specified normal and enlarged-text presentation. Record
  the states exercised and retain screenshot or app-state evidence in the slice report.
  Automated unit, matrix, and snapshot tests remain required; a UI-changing slice completes
  only when both automated checks and Computer Use verification pass. Stop at required account,
  permission, login, or consequential-action handoffs and follow the Computer Use confirmation
  policy; use deterministic fixtures or preview/test states for remaining visual coverage.
- `ClaudePresentationMatrixTests.swift` — rewrite to the 22-scenario catalog (pivot on access ×
  refresh × snapshot, not `bridgeCurrent`), covering all four signed-out combinations.
- `PromptJuiceViewModelTests.swift:847-1124` + statusDetail fixtures (372, 1397, 1592, 2324,
  2343) · `PanelToolTipViewTests.swift:8,37,55` literal inputs · `JuicebarPanelControllerTests`
  fixture/gating · new: neutral-row aggregate exclusion, sole-neutral header, fresh-window
  provider gating, relative-time cutover, cached-bars transitions, forward-compat auth.
- Previews: delete only the five setup previews (`SettingsView.swift:978-1006`); ADAPT AND KEEP
  the measurement-popover and provider-row shells (`:855-976`) used by `PanelSnapshotTests`.
- Bridge journey deletion (`SettingsView.swift:490-852`), bridge script/build/CI/docs removal:
  AFTER the migration gate only.
- Docs: README 79, 96–116, 124, 182, 192, 199 · provider-integrations 59–149 · prompt-juice
  54–58, 87–111 · states-and-colors 90–111, 174 (rewrite matrix to this catalog) · archive the
  two bridge docs at gate time.
- String sweep (at gate): the full bridge-era delete list from v6 plus the four withdrawn
  claims in section 2.

## 8. Sequence (B1/B2/B3 approved · design ready — execution awaits Jeremy's explicit start instruction)

0. Consolidate: copy this spec into the worktree at `docs/claude-usage-ui-implementation.md`;
   banner `claude-usage-plan.md`'s superseded decisions.
1. Slice 1: author category-1 synthetic fixtures; evaluate category-2 OSS fixtures; PREPARE
   (never execute) the capture harness per section 6. **Hard stop after slice 1:** Codex
   reports — synthetic fixture inventory · CodexBar provenance/license verdict · harness
   location · exact review/run instructions for Jeremy · any fixture finding that invalidates
   this spec — and stops. Jeremy reviews the harness and decides when to run the approved
   read-only captures (subscription /usage, auth status, version) in a later step. Codex never
   executes the harness.
2. Locator, version gate (2.1.208), install-method/provenance detection, fail-closed
   five-category auth classification, with tests. Write the auth-status decoder against
   Jeremy's real captured shape (classifier provisional until then). `claude auth login` exit
   behavior is a dogfood observation, not a gate.
3. Flat PTY transport (fixed command allowlist) + pure /usage parser, fixture tests.
4. Access/refresh state, client-owned cooldown, cache, coordinator, source ladder, behind the
   dogfood switch; bridge stays hidden fallback.
5. G1–G4 estimator privacy refactor (gates the privacy copy).
6. Presentation layer per this spec: journeys, neutral rows, sole-neutral headers, sheets with
   journey-scoped rechecks and the Install→Sign in transition, accessibility, the 22-scenario
   matrix tests (incl. the unknown-provenance sheet variant and all four signed-out
   combinations), plus native SwiftUI snapshots of the sheet footer at minimum macOS text size
   and with accessibility text enlargement. Build and run PromptJuice, then use `@Computer` to
   exercise and capture evidence for every affected UI state and interaction; this step remains
   incomplete until the mandatory Computer Use UI gate in section 7 passes.
7. Technical + product dogfood; remove Jeremy's verified bridge via the Remove path.
8. Delete the fallback bridge subsystem (script, build_app.sh, ci.yml, installer, watcher,
   docs) + repo-wide string sweep before public distribution.
9. Optional, unscheduled: Anthropic clarification note (B5) if/when a broad public launch
   approaches; passive-data fallback stays ready either way.

## 9. Jeremy's decision list

- **B1 — APPROVED.** Credential policy D as strengthened (section 1).
- **B2 — APPROVED.** Minimum Claude Code 2.1.208 + below-minimum update journey.
- **B3 — APPROVED (read-only captures).** Adds fixtures + the unit tests that consume them:
  the `/usage` screen parser tests, the `claude auth status` classifier tests, the version-gate
  tests, and the cached-bars transition tests (F-RL1–F-RL4 / T-RL1–T-RL4). Each real capture is
  approved individually; login-state captures still need a written isolation/recovery plan.
- **B5 — DEFERRED / OPTIONAL.** Not a blocker. Comparable tools ship without Anthropic
  clarification and PromptJuice is more conservative (no credentials, no model calls). Ship
  dogfood/limited freely; broad public launch optionally sends the note or ships the
  passive-data (estimate-only) fallback. Not being pursued now.
- **Bridge — RESOLVED.** Never shipped externally; needs-review path dropped.
- **Ampersand — RESOLVED.** Keep "Copy and Open Terminal" (Apple Style Guide).
- **Only genuine open unknown:** exact `claude auth status` JSON field names (undocumented),
  confirmed by the first B3 capture before the classifier finalizes.
