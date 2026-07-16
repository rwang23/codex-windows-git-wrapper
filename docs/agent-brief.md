# Agent Brief

## Project Snapshot

- Last reviewed: 2026-07-16
- Purpose: reversible Windows console-window guard for visible ChatGPT Codex Desktop Git, PowerShell, CMD, and conhost windows.
- Project root: repository root; use relative paths and do not require a particular clone location.
- Users: Windows users of ChatGPT Codex Desktop who see Git, PowerShell, CMD, or conhost flashes.
- Scope: Windows only; support current `ChatGPT.exe` and legacy `Codex.exe` package names.
- Stack: PowerShell installers/launchers, native C++ console-window guard, native or managed GUI wrappers.
- Canonical package manager: none; scripts compile the local wrapper sources directly.
- Runtime: local user machine only; no service, deployment, customer data, or credentials.
- Production/live-data sensitivity: no live data; GitHub pushes and comments are public external effects and require explicit user authorization.

## Read First

1. `README.md` for install, launch, rollback, and user-facing safety rules.
2. `scripts\install.ps1` and `scripts\start-codex-with-git-wrapper.ps1` before changing installation or launch behavior.
3. `scripts\codex-package.ps1` before changing package/process discovery.
4. `src\CodexConsoleWindowGuard.cpp` and `tests\console-window-guard-regression.ps1` before changing window filtering.

Do not inspect generated `bin/` or `obj/` output unless build diagnosis requires it.

## Design Constraints

- Never replace, rename, patch, or manually copy the user's real `git.exe`.
- Never persist the wrapper directory in system/user `PATH` or modify the registry.
- Keep wrappers process-local to Codex launches.
- Keep the guard narrowly scoped to an exact window owner/process graph: targeted shell owners under ChatGPT/Codex, packaged Codex backend/helper owners under `ChatGPT.exe`, or a Chrome-parented `cmd.exe` native-host bridge. Never hide arbitrary descendants or all windows of a generic class.
- Preserve the bounded, command-line-free guard log and its 1 MiB truncation limit.
- Preserve the sparse startup/30-second rescan schedule and its visible-candidate gate; do not turn the guard into another high-frequency process poller.
- Preserve normal PowerShell Git behavior. Do not turn the system Git executable into a GUI executable.
- `-Force` stops Codex. Never run it from an active Codex task; give the user an external PowerShell command instead.

## Workflow Routing

- Documentation-only change: update `README.md`, then verify links, portability, and `git diff --check`.
- Wrapper/launcher behavior change: change the smallest relevant source/script and run the focused regression test.
- Package-name or process-tree change: cover both `ChatGPT.exe` and `Codex.exe` in the guard/package tests.
- Upstream Windows issue research: distinguish visible-window mitigation from the root Git polling, process leak, CPU, or crash issue; do not claim this repository fixes the upstream cause.
- GitHub issue/comment/push: requires explicit user authorization and fresh remote/issue readback.

## Canonical Commands

```powershell
# Install into the default user-local wrapper directory
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1

# Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\status.ps1

# Focused regression checks
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\install-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\launcher-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\console-window-guard-regression.ps1
```

## Verification Rules

- Code/launcher behavior: focused regression test on Windows.
- Guard filter: simulate both desktop process names, verify `--once` exits after the expected console event, run the process-graph self-test, and verify the matched-window log.
- Documentation: no machine-specific clone paths, no secrets, and no undocumented safety trade-offs.
- Release: run the three regression checks, `git diff --check`, and `workflow-lint.ps1` before push.

## Verification Bundles

- Authoritative target: the current clone, branch, worktree state, and remote URL.
- Code or launcher change: the matching regression script plus `git diff --check`.
- Public documentation: focused path/portability scan and rendered Markdown review.
- GitHub publish/comment: fresh remote or issue readback after the external action.

## Live Operation Gates

This project has no production service or customer data. Before a public GitHub push, release, or issue comment, confirm the target repository/account, the exact commit or comment body, user authorization, and post-action readback.

## Tooling Map

- `scripts\install.ps1`: builds/installs local wrappers and the optional guard.
- `scripts\start-codex-with-git-wrapper.ps1`: launches Codex with the process-local wrapper environment.
- `scripts\status.ps1`: read-only install/runtime diagnostics.
- `scripts\remove.ps1`: removes the local wrapper/guard install.
- `tests\*.ps1`: focused Windows regression checks.

## Known Pitfalls

- MSIX files under `WindowsApps` can deny a normal `Test-Path` check even when the app can launch; use the manifest-derived package information.
- Some MSIX activation paths bypass process-local `PATH`. The console guard is the fallback for targeted shell/backend/native-host windows, not a global console suppressor.
- Current Codex builds can retain duplicate MCP process pools. The guard may hide their launcher windows, but it must not claim to deduplicate or reap those processes.
- `-DisableShellSnapshot` and `-SuppressProcessSampling` target separate PowerShell/process-telemetry symptoms and have documented trade-offs.
