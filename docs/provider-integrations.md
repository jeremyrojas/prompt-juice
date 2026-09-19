# Provider Integrations

PromptJuice uses local provider adapters that return normalized snapshots for the UI and alert engine. Each snapshot includes provider identity, rate windows, source, confidence, update time, and optional status detail.

## Codex

PromptJuice reads Codex usage through the local Codex app-server:

1. Locate the Codex executable.
2. Launch `codex app-server` over stdio.
3. Complete the initialization handshake.
4. Call `account/rateLimits/read`.
5. Prefer `rateLimitsByLimitId["codex"]`, with `rateLimits` as the compatible fallback.
6. Classify every usable window by `windowDurationMins`, regardless of whether it appears in the primary or secondary slot.

`300` minutes is a **5-hour limit**; `10080` minutes is **Weekly**. Any other duration stays visible with a label made from its actual length, such as **24-hour limit** or **3-day limit**, and is logged once. The shortest reported cadence is the main row. Codex Pro currently reports Weekly in the primary slot with no secondary; lower-tier plans are expected to report 5-hour plus Weekly. The lower-tier test fixture is inferred, and its live shape still needs validation on a non-Pro account.

Executable lookup order:

1. `PROMPTJUICE_CODEX_PATH`
2. `/Applications/ChatGPT.app/Contents/Resources/codex`
3. `/Applications/Codex.app/Contents/Resources/codex`
4. `/opt/homebrew/bin/codex`
5. `/usr/local/bin/codex`
6. `which codex`

### Codex source labels

- `codexAppServer` + `exact`: current usable windows from the app-server response.
- `codexCache` + `stale`: a valid last-good window carried through a read failure.
- `codexAppServer` + `unavailable`: executable, launch, handshake, timeout, server, or parser failure.

Set an explicit executable path when automatic lookup misses Codex:

```bash
export PROMPTJUICE_CODEX_PATH="/Applications/ChatGPT.app/Contents/Resources/codex"
```

## Claude

PromptJuice reads Claude plan usage through Claude Code's built-in `/usage` screen. The production ladder is:

1. Current exact `/usage` reading.
2. Valid last-good exact reading from the derived-only cache.
3. Local Claude Code activity estimate.
4. Unavailable state with a guided recovery action when applicable.

The parser carries Claude's 5-hour, all-models Weekly, and model-specific weekly windows (including Fable) into the provider snapshot. Each window retains its own reset timestamp and update time. The all-models Weekly can lock the whole provider at 0%; a model-specific weekly affects its own model row.

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
