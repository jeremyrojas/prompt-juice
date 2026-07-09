<div align="center">
  <img src="design/assets/promptjuice-mascot-happy.png" alt="PromptJuice green droplet mascot" width="128">
  <h1>PromptJuice</h1>
  <p><strong>Make every usage window worth the squeeze.</strong></p>
  <p>A native macOS menu-bar gauge for Claude and Codex usage windows.</p>
</div>

PromptJuice keeps the useful part of your AI rate limits visible: how much
session capacity remains, when it resets, and how fresh the reading is. The
menu-bar droplet gives you the glance; the Juice Bar gives you the details.

PromptJuice is built around one valuable moment: **plenty of capacity remains,
and very little time remains before the window resets**. You choose the time and
remaining-juice thresholds that define that moment. When both are met, the
droplet turns orange and PromptJuice can send one timely macOS notification.

That orange window is your cue to spend bigger: start the ambitious task, fan
work out to more agents, use fast mode, or reach for a stronger model while the
capacity is already yours. Squeeze the window before the window resets.

## Quick Start

### Requirements

- macOS 14 Sonoma or later.
- Git and a Swift 6 toolchain. Xcode 16 or later includes Swift 6.
- Access to this private repository.
- Codex or Claude Code installed for live provider readings.

### Install From Source

```bash
git clone https://github.com/jeremyrojas/prompt-juice.git
cd prompt-juice
.agents/skills/promptjuice-install/scripts/install_promptjuice.sh
```

The installer builds `PromptJuice.app`, installs it in `/Applications` when
writable or `~/Applications` otherwise, and opens it. Choose Claude, Codex, or
both on first launch.

If macOS blocks the preview build, right-click `PromptJuice.app`, choose
**Open**, and approve the prompt.

### Install With An AI Agent

Give a coding agent this instruction:

```text
Clone https://github.com/jeremyrojas/prompt-juice.git, read README.md and .agents/skills/promptjuice-install/SKILL.md, then follow the skill to build, install, and open PromptJuice on this Mac.
```

The repository also includes a dedicated update skill, so future refreshes stay
on the same well-tested path.

## What You Get

- A menu-bar droplet whose fill reflects remaining session capacity.
- A compact Juice Bar with Claude and Codex percentages and reset countdowns.
- Clear **Live**, **Earlier**, **Estimate**, and **Not set up** confidence labels.
- Configurable time-to-reset and remaining-capacity thresholds for the orange cue.
- One merged macOS notification for providers that enter the same use-soon moment.
- A pinnable, draggable Juice Bar that remembers its position.
- Local caches that carry valid last-good readings through brief provider outages.

Left-click the menu-bar droplet to open the Juice Bar. Right-click the droplet or
the panel for **Pin Juicebar**, **Settings**, and **Quit PromptJuice**.

## How PromptJuice Reads Usage

PromptJuice reads provider state locally and normalizes it into the same compact
view. Every row identifies the quality of its reading:

| Label | Meaning |
| --- | --- |
| **Live** | Exact, current provider data. |
| **Earlier** | A still-valid last-good window from the local cache. |
| **Estimate** | A local activity-based approximation. |
| **Not set up** | The provider or its live-reading bridge needs attention. |

### Codex

PromptJuice locates the local Codex executable, launches `codex app-server` over
stdio, and calls `account/rateLimits/read`. Install and sign in to Codex, then
PromptJuice can read the primary session window automatically. A valid secondary
weekly window is cached for future UI.

Automatic lookup checks the Codex app, Homebrew locations, and `PATH`. Set
`PROMPTJUICE_CODEX_PATH` when the executable lives elsewhere:

```bash
export PROMPTJUICE_CODEX_PATH="/Applications/Codex.app/Contents/Resources/codex"
```

### Claude

Claude Code can provide exact five-hour and seven-day usage windows through its
status line. In PromptJuice, open **Settings -> Claude -> Set up live readings**,
review the proposed change, and enable the bridge. Claude Code refreshes the
local bridge every 10 seconds while a terminal session is open.

The bridge adds one entry to `~/.claude/settings.json`, preserves an existing
status-line command by wrapping it, and writes sanitized rate-limit fields to:

```text
~/Library/Application Support/PromptJuice/ClaudeStatus/
```

Claude desktop usage alone produces an **Estimate** from local Claude activity
logs because the desktop app does not currently run Claude Code status lines.
When all known five-hour windows expire, PromptJuice shows **Fresh window** at
100% session remaining until Claude supplies the next window.

Detailed setup and troubleshooting live in
[Provider Integrations](docs/provider-integrations.md) and the
[Claude Statusline Bridge guide](docs/claude-statusline-bridge.md).

## Privacy

PromptJuice processing and caches stay on your Mac. The app includes zero
analytics and zero hosted backend:

- Codex usage comes from the local Codex app-server process.
- Claude exact usage comes from the local status-line bridge cache.
- Claude estimates come from local activity metadata.
- Cached snapshots contain normalized usage windows and update times.

Codex and Claude Code continue to use their own provider connections and account
sessions.

## Update

Run the update helper from a clean PromptJuice checkout:

```bash
.agents/skills/promptjuice-update/scripts/update_promptjuice.sh
```

It fetches and fast-forwards the current branch, rebuilds the app, replaces the
installed copy, and reopens PromptJuice.

An AI agent can follow the same contract:

```text
Read .agents/skills/promptjuice-update/SKILL.md and follow it to update my installed PromptJuice app from GitHub.
```

## Develop

Build and open a local app bundle:

```bash
./scripts/run_app.sh
```

Run the test suite:

```bash
swift test
```

Build a release-configured bundle:

```bash
CONFIGURATION=release ./scripts/build_app.sh
```

The bundle is written to `build/PromptJuice.app`. GitHub Actions runs the Swift
build and tests, shell validation, metadata checks, and app-bundle verification
for pull requests and pushes to `main`.

## Preview Status

PromptJuice is early preview software distributed from source. Local builds use
a stable ad-hoc signing requirement so notification permission survives rebuilds.
A public release should use Apple Developer ID signing and notarization.

Current boundaries:

- Provider rows show the active session window at a fixed height.
- Weekly windows are read and cached while their dedicated UI is being refined.
- Exact Claude readings require Claude Code in a terminal session.

## Project Map

```text
app/PromptJuice/       App lifecycle, UI, models, providers, and services
app/PromptJuiceTests/  Unit, integration, and snapshot coverage
.agents/skills/        Agent-safe install and update workflows
design/                Product states and visual assets
docs/                  Integration and implementation references
scripts/               Build, run, icon, and Claude bridge helpers
```

## Documentation

- [Product overview](docs/prompt-juice.md)
- [Provider integrations](docs/provider-integrations.md)
- [Claude statusline bridge](docs/claude-statusline-bridge.md)
- [Usage state board](design/prompt-juice-states.html)

Keep the prompts flowing. Down to the last drop.
