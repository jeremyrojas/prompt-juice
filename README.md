# PromptJuice

PromptJuice is a native macOS menu-bar app that shows Claude and Codex usage windows in a compact top-center Juicebar.

It helps answer one question while you work: how much useful AI capacity is left before the current window resets?

## Status

PromptJuice is an early open-source prototype. It currently includes:

- A native macOS accessory app with a menu-bar droplet.
- A floating Juicebar panel with Claude and Codex rows.
- Fixture usage data for tests and previews.
- Live Codex rate-limit reads through the local Codex app-server.
- Claude usage reads through a Claude Code statusline cache, with a local-log estimate fallback.
- Source and confidence labels for exact, estimated, stale, and unavailable data.
- Snooze, refresh, and threshold controls.

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

## Provider Integrations

PromptJuice treats every provider snapshot as local state with a source and confidence label.

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
    UI/           Juicebar panel, menu-bar views, settings UI
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
