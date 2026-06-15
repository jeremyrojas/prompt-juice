---
name: promptjuice-install
description: Install or set up PromptJuice from a checked-out GitHub repository on macOS. Use when a user asks Codex or another AI coding agent to install PromptJuice, set up PromptJuice, build PromptJuice.app, copy it into Applications, open it, or follow the repository's AI-agent installation instructions.
---

# PromptJuice Install

## Overview

Install PromptJuice for a Mac user from this repository checkout. Prefer the bundled script so the build, app replacement, and launch behavior stay consistent.

## Workflow

1. Confirm the current directory is the PromptJuice repository root or a subdirectory inside it.
2. If the repository is missing, clone `https://github.com/jtrojas24/prompt-juice`, enter the checkout, and continue.
3. Run the install helper:

```bash
.agents/skills/promptjuice-install/scripts/install_promptjuice.sh
```

4. If the helper reports a macOS security prompt, tell the user to right-click the installed `PromptJuice.app`, choose **Open**, and approve the prompt.
5. Report the install path shown by the helper.

## Notes

- The helper uses `scripts/build_app.sh`.
- The helper installs to `/Applications` when writable and `~/Applications` when needed.
- The helper quits a running PromptJuice process before replacing the app.
