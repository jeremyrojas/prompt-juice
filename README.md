# PromptJuice

PromptJuice is a native macOS menu-bar app with a top-center Juicebar for checking how much Claude and Codex usage is left before the current limit window resets.

The first milestone is a static concept prototype: a native Juicebar, menu-bar icon, simulated usage data, and playful alerts. Account connections can follow after the interaction feels right.

## Docs

- Next implementation plan: [PLAN.md](PLAN.md)
- Product and MVP plan: [docs/prompt-juice.md](docs/prompt-juice.md)
- OSS usage tools research: [docs/oss-usage-tools-research.md](docs/oss-usage-tools-research.md)
- Claude statusline bridge: [docs/claude-statusline-bridge.md](docs/claude-statusline-bridge.md)
- Usage state board: [design/prompt-juice-states.html](design/prompt-juice-states.html)

## Project Layout

```text
app/
  PromptJuice/
    App/          App entry points and app lifecycle
    UI/           Juicebar panel, menu-bar views, settings UI
    Models/       Usage windows, snapshots, alert state
    Providers/    Demo, Codex, and Claude usage sources
    Services/     Notifications, Keychain, actions, storage
    Resources/    Assets, Info.plist, app resources
  PromptJuiceTests/
  PromptJuiceUITests/
design/
  assets/         Visual references, icons, screenshots
docs/             Product and technical planning
prototypes/       Scratch/demo experiments
scripts/          Build and developer helpers
```

## Development Notes

Recommended stack:

- Swift.
- AppKit for top-level Juicebar behavior.
- SwiftUI for simple settings and reusable views.
- `NSStatusItem` for the menu-bar icon.
- Borderless floating `NSWindow` for the Juicebar surface.
- `UserNotifications` for native alerts.
- Keychain for future account credentials.

## Run The Prototype

Build a local app bundle:

```bash
./scripts/build_app.sh
```

Build and open the app:

```bash
./scripts/run_app.sh
```

Current prototype behavior:

- Launches as a macOS accessory app.
- Shows a droplet in the menu bar.
- Displays a demo Juicebar alert shortly after launch.
- Uses a rounded liquid-glass panel with provider rows, capacity bars, and status chips.
- Clicking a Claude or Codex row updates the headline/detail for that provider.
- Snooze briefly confirms, hides the Juicebar, and keeps the current demo window quiet.
- Places the panel on the display under the cursor for smoother multi-monitor use.
- Left-click the menu-bar icon to manually show or hide the usage panel.
- Right-click the menu-bar icon for demo controls and quit.
- Right-click threshold controls adjust remaining-time and remaining-juice alert rules.
- Right-click notification controls request permission and send a demo notification.
- Generates a simple PromptJuice app icon during bundle builds.
- Demo data is static; Claude and Codex account connections come later.
