# PromptJuice 💧

*Make every usage window worth the squeeze.*

PromptJuice is a native macOS menu-bar app that shows Claude and Codex usage windows in a compact top-center Juice Bar.

It helps answer one question while you work: how much useful AI capacity is left before the current window resets?

## Installation

PromptJuice is early preview software. Install it from source with the bundled install workflow:

```bash
git clone https://github.com/jtrojas24/prompt-juice.git
cd prompt-juice
.agents/skills/promptjuice-install/scripts/install_promptjuice.sh
```

You can also point an AI coding agent at the repository and the install skill file:

```text
Go to https://github.com/jtrojas24/prompt-juice, read README.md, then use the install skill at .agents/skills/promptjuice-install/SKILL.md to set up PromptJuice on this Mac.
```

The install skill builds `PromptJuice.app`, copies it into `/Applications` when possible, falls back to `~/Applications`, and opens the app.

To update later, run this from your local PromptJuice checkout:

```bash
.agents/skills/promptjuice-update/scripts/update_promptjuice.sh
```

Or ask your AI coding agent:

```text
Read .agents/skills/promptjuice-update/SKILL.md and follow it to update my installed PromptJuice app from GitHub.
```

If macOS shows a security prompt for this preview build, right-click `PromptJuice.app`, choose **Open**, and approve the prompt.

## Naming

- **PromptJuice** is the app.
- **Juice Bar** is the floating menu-bar window that opens from the PromptJuice droplet — pull up a stool and check your levels.

## Status

PromptJuice is an early open-source prototype. It currently includes:

- A native macOS accessory app with a menu-bar droplet.
- A floating Juice Bar panel with Claude and Codex rows.
- Fixture usage data for tests and previews.
- Live Codex rate-limit reads through the local Codex app-server.
- Claude usage reads through a Claude Code statusline cache, with a local-log estimate fallback.
- Source and confidence labels for exact, estimated, stale, and unavailable data.
- Snooze, refresh, and threshold controls — set your sweet spot and get nudged when juice dips below it.

## Build And Run

Build a local app bundle:

```bash
./scripts/build_app.sh
```

Build and open the app:

```bash
./scripts/run_app.sh
```

You can also run the test suite directly:

```bash
swift test
```

## How PromptJuice Reads Usage

PromptJuice shows each provider reading with a confidence label:

**Live -> Earlier -> Estimate -> Not set up**

For Claude, Live readings are exact usage numbers from Claude Code's status line. That status line runs only in the Claude Code terminal CLI, and PromptJuice receives the latest exact number after Claude Code finishes an assistant message. It is current as of your last terminal assistant message, not real-time.

If the desktop app is your only Claude surface, PromptJuice stays on Estimate because the desktop app does not support status lines yet. The upstream Claude Code issue is [anthropics/claude-code#41456](https://github.com/anthropics/claude-code/issues/41456).

To get Live readings for Claude: open **Settings -> Claude -> Set up live readings**, approve the status line bridge, then use Claude Code in the terminal.

## Provider Integrations

PromptJuice treats every provider snapshot as local state with a source and confidence label. Think of confidence as freshness: exact is fresh-squeezed, estimated is from concentrate, and stale is past its date.

- `demo` with `exact` confidence powers the built-in prototype data.
- `codexAppServer` with `exact` confidence comes from `codex app-server` and `account/rateLimits/read`.
- `codexCache` with `stale` confidence reuses the last good Codex window when a live read fails before reset.
- `claudeStatusline` with `exact` confidence comes from the Claude Code statusline bridge cache.
- `claudeLocalLogs` with `estimated` confidence comes from local Claude project logs.
- `claudeCache` with `stale` confidence reuses the last good Claude statusline window before reset.
- `unavailable` confidence gives the UI a calm failure state with a short diagnostic.

Read the setup and troubleshooting details in [docs/provider-integrations.md](docs/provider-integrations.md). Claude statusline bridge details live in [docs/claude-statusline-bridge.md](docs/claude-statusline-bridge.md).

## Project Layout

```text
app/
  PromptJuice/
    App/          App entry points and app lifecycle
    UI/           Juice Bar panel, menu-bar views, settings UI
    Models/       Usage windows, snapshots, alert state
    Providers/    Fixture, Codex, and Claude usage sources
    Services/     Notifications and local settings
    Resources/    Info.plist and app resources
  PromptJuiceTests/
design/
  assets/         Visual references, icons, screenshots
docs/             Public product and integration docs
scripts/          Build, run, icon, and bridge helpers
```

## Docs

- Product overview: [docs/prompt-juice.md](docs/prompt-juice.md)
- Provider integrations: [docs/provider-integrations.md](docs/provider-integrations.md)
- Claude statusline bridge: [docs/claude-statusline-bridge.md](docs/claude-statusline-bridge.md)
- Usage state board: [design/prompt-juice-states.html](design/prompt-juice-states.html)

---

*Down to the last drop.*
