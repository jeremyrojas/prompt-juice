# Provider Integrations

PromptJuice uses local provider adapters that return normalized snapshots for the UI and alert engine. Each snapshot includes provider identity, rate windows, source, confidence, update time, and optional status detail.

## Codex

PromptJuice reads Codex usage through the local Codex app-server:

1. Locate the Codex executable.
2. Launch `codex app-server` over stdio.
3. Complete the initialization handshake.
4. Call `account/rateLimits/read`.
5. Prefer `rateLimitsByLimitId["codex"]`, with `rateLimits` as the compatible fallback.
6. Map the primary window to the visible session and retain a valid secondary weekly window.

Executable lookup order:

1. `PROMPTJUICE_CODEX_PATH`
2. `/Applications/Codex.app/Contents/Resources/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. `which codex`

### Codex source labels

- `codexAppServer` + `exact`: a complete current primary window.
- `codexCache` + `stale`: a valid last-good window carried through a read failure.
- `codexAppServer` + `unavailable`: executable, launch, handshake, timeout, server, or parser failure.

Set an explicit executable path when automatic lookup misses Codex:

```bash
export PROMPTJUICE_CODEX_PATH="/Applications/Codex.app/Contents/Resources/codex"
```

## Claude

PromptJuice reads Claude plan usage through Claude Code's built-in `/usage` screen. The production ladder is:

1. Current exact `/usage` reading.
2. Valid last-good exact reading from the derived-only cache.
3. Local Claude Code activity estimate.
4. Unavailable state with a guided recovery action when applicable.

### Prerequisites

PromptJuice locates Claude Code through known native, Homebrew, npm, and user-local paths. It then runs bounded noninteractive version and authentication probes. Direct readings require:

- Claude Code at the supported minimum version or newer;
- subscription authentication;
- one-time trust for PromptJuice's dedicated empty probe workspace when Claude requests it.

Settings exposes guided Install, Sign In, Update, and Workspace Trust journeys. Each journey shows the exact command, supports copy/open-in-Terminal actions where appropriate, and rechecks the relevant prerequisite.

### `/usage` transport

The usage probe launches Claude Code in a pseudo-terminal with a fixed allowlist of arguments and environment values. It waits for command readiness, sends the exact `/usage` command, answers only the allowlisted terminal cursor-position query, parses quota rows, and terminates the process group within bounded time and output limits.

The probe sends zero model prompts. PromptJuice logs lifecycle milestones and typed outcomes only. Raw terminal output stays inside the transient parser boundary.

### Scheduling and cooldown

PromptJuice checks Claude on launch, activation, wake, panel open, reset boundaries, and a bounded timer schedule. Refreshes coalesce while a probe is active. The scheduler enforces freshness, debounce, hourly attempt-budget, provider-enabled, awake, and online gates.

When Claude returns its usage endpoint rate limit, PromptJuice preserves the last usable reading and advances through persisted 5, 15, 30, and 60 minute cooldowns. Relaunching during cooldown restores the account category, cached reading, and next-attempt time without starting another probe.

### Local estimate

When a direct reading is unavailable, PromptJuice can scan bounded recent Claude project logs from:

- `CLAUDE_CONFIG_DIR`
- `~/.config/claude/projects`
- `~/.claude/projects`

The reader decodes a narrow usage-only projection, deduplicates repeated usage entries, groups activity into five-hour blocks, and derives an active-block estimate. Conversation fields disappear at the typed decode boundary. The UI labels this source `claudeLocalLogs` with `estimated` confidence.

### Claude source labels

- `claudeUsageCLI` + `exact`: current plan usage parsed from `/usage`.
- `claudeUsageCLI` + `stale`: a saved reading reported by Claude Code.
- `claudeCache` + `stale`: a valid last-good exact window.
- `claudeLocalLogs` + `estimated`: a bounded local activity estimate.
- `claudeUsageCLI` + `unavailable`: no usable direct, cached, or estimated reading.

### Troubleshooting

Verify the local CLI and authentication state:

```bash
claude --version
claude auth status
```

PromptJuice Settings reports the current category and offers the matching guided action. A rate-limit state includes the next automatic check time. A workspace-trust state opens the dedicated workspace in Terminal for one-time approval.
