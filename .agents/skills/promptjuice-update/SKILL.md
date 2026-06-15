---
name: promptjuice-update
description: Update an installed PromptJuice app from a local Git checkout on macOS. Use when a user asks Codex or another AI coding agent to pull the latest PromptJuice changes, rebuild PromptJuice.app, replace the installed app, or follow the repository's AI-agent update instructions.
---

# PromptJuice Update

## Overview

Update PromptJuice for a Mac user from this repository checkout. Prefer the bundled script so pull, build, app replacement, and launch behavior stay consistent.

## Workflow

1. Confirm the current directory is the PromptJuice repository root or a subdirectory inside it.
2. Run the update helper:

```bash
.agents/skills/promptjuice-update/scripts/update_promptjuice.sh
```

3. If the helper stops because the checkout has local changes, summarize the changed files and ask whether the user wants to stash, commit, or handle them manually.
4. If the helper reports a macOS security prompt, tell the user to right-click the installed `PromptJuice.app`, choose **Open**, and approve the prompt.
5. Report the updated commit and install path shown by the helper.

## Notes

- The helper uses `git pull --ff-only`.
- The helper uses `scripts/build_app.sh`.
- The helper installs to the existing PromptJuice location when found, otherwise `/Applications` when writable and `~/Applications` when needed.
- The helper quits a running PromptJuice process before replacing the app.
