# Claude Statusline Bridge Plutil Plan

## Goal

Move Claude live-readings setup from a required `jq` install to macOS-bundled `/usr/bin/plutil`, while keeping the current `jq` transform available as a tested rollback path.

Preserve the existing PromptJuice confidence hierarchy: exact statusline cache, last-good statusline cache, local-log estimate, unavailable.

## Context

- [scripts/claude-statusline-bridge.sh](../scripts/claude-statusline-bridge.sh): bridge script that reads Claude Code statusline JSON from stdin, writes PromptJuice's sanitized cache, then delegates to the user's statusline command.
- [app/PromptJuice/Services/ClaudeBridgeInstaller.swift](../app/PromptJuice/Services/ClaudeBridgeInstaller.swift): computes and applies the Claude `statusLine.command` setup plan; currently probes and warns for `jq`.
- [app/PromptJuice/Providers/ClaudeProviderClient.swift](../app/PromptJuice/Providers/ClaudeProviderClient.swift): reads the statusline cache and already accepts numeric fields as numbers or strings.
- [app/PromptJuiceTests/ProviderClientTests.swift](../app/PromptJuiceTests/ProviderClientTests.swift): contains bridge smoke tests currently gated by `jq`.
- [app/PromptJuiceTests/ClaudeBridgeInstallerTests.swift](../app/PromptJuiceTests/ClaudeBridgeInstallerTests.swift): covers installer planning, wrapping, idempotency, and `jq` detection.
- [app/PromptJuiceTests/PanelSnapshotTests.swift](../app/PromptJuiceTests/PanelSnapshotTests.swift): includes setup-preview snapshots with `jq` present/missing states.
- [docs/claude-statusline-bridge.md](claude-statusline-bridge.md): user-facing setup and troubleshooting docs.
- [docs/provider-integrations.md](provider-integrations.md): provider source hierarchy and troubleshooting docs.
- [README.md](../README.md): public setup and integration overview.

## Phases

### Phase 1: Add Reversible Parser Selection

**Subtasks**

- Introduce `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER`.
- Support `plutil`, `jq`, and `auto`.
- Default to `plutil`.
- Preserve the current `jq` transform in a named fallback function.
- Keep delegated statusline execution after every parser outcome.

**Files changed**

- `scripts/claude-statusline-bridge.sh`
  - Add `parser="${PROMPTJUICE_CLAUDE_STATUSLINE_PARSER:-plutil}"`.
  - Move the existing `jq` payload transform into `write_promptjuice_cache_jq`.
  - Add `write_promptjuice_cache_plutil` as the new default path.
  - Add `write_promptjuice_cache` as the parser dispatcher.
  - Keep `run_delegate` behavior unchanged.

Parser dispatcher shape:

```bash
write_promptjuice_cache() {
  case "${PROMPTJUICE_CLAUDE_STATUSLINE_PARSER:-plutil}" in
    jq) write_promptjuice_cache_jq ;;
    auto) write_promptjuice_cache_plutil || write_promptjuice_cache_jq ;;
    plutil|*) write_promptjuice_cache_plutil ;;
  esac
}
```

**Verification**

- Run the bridge manually with sample Claude statusline JSON.
- Confirm `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=plutil` writes a cache.
- Confirm `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=jq` writes the same cache on machines with `jq`.
- Confirm `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=auto` writes a cache through `plutil`.
- Confirm the delegate command receives the original stdin every time.

### Phase 2: Implement Plutil Extraction And Validation

**Subtasks**

- Extract fields with `/usr/bin/plutil -extract ... raw - -n`.
- Validate required fields after extraction.
- Normalize the cache payload.
- Keep cache writes atomic.
- Treat malformed or incomplete input as cache-unavailable.

**Files changed**

- `scripts/claude-statusline-bridge.sh`
  - Add `extract_raw_plutil`.
  - Add `json_escape`.
  - Add numeric validation for `used_percentage`.
  - Add duration normalization.
  - Add `write_payload_atomic`.
  - Write only this cache shape:

```json
{
  "rate_limits": {
    "five_hour": {
      "used_percentage": 12.5,
      "resets_at": "1800001800",
      "duration_minutes": 300
    }
  }
}
```

Validation requirements:

- `used_percentage` accepts integer, float, or numeric string.
- `used_percentage` must be finite and greater than or equal to `0`.
- `resets_at` must be present and non-empty.
- `duration_minutes` accepts integer, float, or numeric string.
- `window_minutes` accepts integer, float, or numeric string.
- Duration precedence is `duration_minutes`, then `window_minutes`, then `300`.
- Invalid optional duration falls back to `300`.
- Invalid required fields skip the cache write.

**Verification**

- Feed numeric and string `used_percentage` samples.
- Feed numeric and ISO string `resets_at` samples.
- Feed missing, negative, and non-numeric `used_percentage` samples.
- Feed missing `resets_at`.
- Feed malformed JSON.
- Confirm invalid inputs skip cache writes and still run the delegate.
- Confirm cache files contain only `rate_limits.five_hour`.

### Phase 3: Update Installer And Settings UX

**Subtasks**

- Remove the required `jq` install warning from normal setup.
- Replace `jqInstalled` concepts with parser readiness only if the UI still needs a readiness flag.
- Add a diagnostic for missing `/usr/bin/plutil` if a diagnostic path remains useful.
- Remove or update setup previews that represent missing `jq`.

**Files changed**

- `app/PromptJuice/Services/ClaudeBridgeInstaller.swift`
  - Remove `jqProbe`, `jqInstalled`, and `systemHasJQ` from the normal setup plan.
  - Add a lightweight `/usr/bin/plutil` readiness check if needed for diagnostics.
  - Update `Plan.summary` so setup copy describes live readings and delegated statusline preservation.
- `app/PromptJuice/UI/SettingsView.swift`
  - Remove missing-`jq` UI copy and previews.
  - Add parser diagnostic presentation only if `ClaudeBridgeInstaller.Plan` still exposes one.
- `app/PromptJuiceTests/ClaudeBridgeInstallerTests.swift`
  - Replace `jq` probe tests with parser-readiness or no-warning tests.
- `app/PromptJuiceTests/PanelSnapshotTests.swift`
  - Remove missing-`jq` snapshot coverage.
  - Add parser diagnostic snapshot coverage only if the UI exposes a diagnostic.

**Verification**

- Run installer unit tests.
- Render existing settings/setup snapshots.
- Confirm setup copy contains no required `jq` install instruction.
- Confirm setup still wraps an existing statusline command and stays idempotent.

### Phase 4: Expand Bridge Test Coverage

**Subtasks**

- Convert bridge smoke tests to run through `plutil` by default.
- Keep explicit `jq` mode tests gated by local availability.
- Add privacy and malformed-input coverage.
- Confirm Swift reader compatibility with the new cache payload.
- Lock the Claude presentation hierarchy in tests so parser changes cannot regress setup/live/estimate states.

**Files changed**

- `app/PromptJuiceTests/ProviderClientTests.swift`
  - Remove `requireJQ()` from default bridge smoke tests.
  - Add `requireJQ()` only around explicit `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=jq` tests.
  - Add cases for:
    - numeric `used_percentage`,
    - string `used_percentage`,
    - numeric `resets_at`,
    - ISO string `resets_at`,
    - missing `rate_limits.five_hour`,
    - missing `used_percentage`,
    - negative `used_percentage`,
    - non-numeric `used_percentage`,
    - missing `resets_at`,
    - invalid duration fallback,
    - `window_minutes` fallback,
    - malformed JSON,
    - delegate preservation,
    - privacy stripping,
    - atomic write completeness.
- `app/PromptJuice/Providers/ClaudeProviderClient.swift`
  - Adjust only if the new cache payload reveals a reader gap.
- `app/PromptJuiceTests/ClaudePresentationMatrixTests.swift`
  - Confirm parser changes do not alter existing Claude presentation states:
    - exact statusline cache shows live/exact status,
    - stale last-good cache stays stale until reset,
    - local-log fallback stays estimated,
    - missing statusline cache plus no local estimate stays unavailable,
    - bridge missing still exposes setup affordance,
    - bridge installed with no cache stays awaiting terminal/session guidance,
    - setup affordance remains hidden when bridge is installed,
    - disabled provider row stays `Off` with no setup affordance.
- `app/PromptJuiceTests/PromptJuiceViewModelTests.swift`
  - Add or update focused tests for:
    - `settingsStatusText(for: .claude)`,
    - `claudeSetupButtonTitle`,
    - `claudeLiveUpgrade`,
    - source tooltip/popover copy,
    - click routing for setup-available vs awaiting-session.
- `app/PromptJuiceTests/PanelSnapshotTests.swift`
  - Keep or add snapshots for disabled provider rows and setup/awaiting/live Claude states if existing matrix coverage leaves a visible UI gap.

**Verification**

- Run `swift test`.
- Confirm default bridge tests pass on a machine with only `/usr/bin/plutil`.
- Confirm explicit `jq` tests skip cleanly when `jq` is unavailable.
- Confirm `ClaudeStatuslineSnapshotReader` parses bridge-written cache as `.claudeStatusline` and `.exact`.
- Confirm test expectations preserve the current status hierarchy and setup affordance rules.

### Phase 5: Update Docs And Troubleshooting

**Subtasks**

- Update bridge docs to describe `plutil` as the default parser.
- Document parser override and rollback commands.
- Update verification commands from `jq .` to `/usr/bin/plutil -p`.
- Keep `jq` override documented as a temporary compatibility path.

**Files changed**

- `docs/claude-statusline-bridge.md`
  - Replace cache inspection examples with `/usr/bin/plutil -p`.
  - Add `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER` documentation.
  - Add rollback example:

```bash
PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=jq bash /path/to/claude-statusline-bridge.sh
```

- `docs/provider-integrations.md`
  - Update Claude troubleshooting commands.
  - Keep source hierarchy unchanged.
- `README.md`
  - Update setup/troubleshooting summary.
  - Mention Claude live readings use macOS-bundled tooling.

**Verification**

- Read docs for command accuracy.
- Run documented sample command.
- Confirm sample cache opens with `/usr/bin/plutil -p`.

### Phase 6: UI Regression With Computer Use

**Subtasks**

- Build and launch PromptJuice.
- Use Computer Use to verify the real macOS UI setup flow when available.
- Capture screenshots for the PR body; keep screenshots out of the repo.
- Exercise the same hierarchy states covered by code tests in the running app.

**Files changed**

- No planned source changes.
- Store temporary screenshots outside the repo, for example `/tmp/promptjuice-verification/`.

**Verification**

- `scripts/run_app.sh` builds and launches.
- Computer Use can open the PromptJuice menu-bar UI or Settings window. If menu-bar windows time out, use macOS UI scripting plus screenshots and record that fallback in the PR body.
- First-run or Settings setup shows Claude live-readings setup with no required `jq` copy.
- Approving setup writes a `statusLine.command` that invokes the bridge.
- Existing user statusline command still renders after bridge execution.
- With bridge installed and no fresh cache, Claude shows awaiting-session guidance and no setup button.
- With a valid synthetic cache, Claude shows live/exact status.
- With cache removed and local logs available, Claude shows estimated status.
- With bridge missing, Claude shows setup-available copy and the setup affordance.
- With Claude provider disabled, Settings shows `Off` and no setup affordance.
- Cache appears at `~/Library/Application Support/PromptJuice/ClaudeStatus/latest.json` after a Claude Code terminal interaction.
- Cache contains only sanitized rate-limit fields.
- Screenshots cover:
  - setup-available,
  - setup sheet,
  - awaiting terminal/session,
  - live/exact from cache,
  - estimated fallback,
  - disabled provider row.

### Phase 7: Final Rollout Checks

**Subtasks**

- Run the full automated test suite.
- Run the documented manual bridge command.
- Verify parser rollback.
- Document rollback in the PR body.
- Add release-note text if the repo has a release-notes file by implementation time.

**Files changed**

- No planned source changes beyond fixes discovered during final verification.

**Verification**

- `swift test` passes.
- Documented sample bridge command writes the expected cache.
- Parser rollback works with `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=jq` on a machine with `jq`.
- PR body lists automated tests, UI regression results, screenshots, rollback path, and any Computer Use fallback used.

## Open Questions

- Keep `PROMPTJUICE_CLAUDE_STATUSLINE_PARSER=auto` long term, or treat it as a migration-only convenience?
- Keep a visible `/usr/bin/plutil` diagnostic in Settings, or rely on unavailable/estimate state if the system tool is missing?
- Remove the `jq` compatibility path after one release or two releases?
