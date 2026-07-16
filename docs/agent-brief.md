# Agent Brief

## Project Snapshot

- Last reviewed: 2026-07-16
- Purpose: reversible Windows console-window guard for visible ChatGPT Codex Desktop Git, PowerShell, CMD, conhost, brokered Windows Terminal windows, and wrapper-scoped temporary-directory configuration.
- Project root: repository root; use relative paths and do not require a particular clone location.
- Users: Windows users of ChatGPT Codex Desktop who see Git, PowerShell, CMD, or conhost flashes.
- Scope: Windows only; support current `ChatGPT.exe` and legacy `Codex.exe` package names.
- Stack: PowerShell installers/launchers, native C++ console-window guard, native or managed GUI wrappers.
- Canonical package manager: none; scripts compile the local wrapper sources directly.
- Runtime: local user machine only; no service, deployment, customer data, or credentials.
- Production/live-data sensitivity: no live data; GitHub pushes and comments are public external effects and require explicit user authorization.

## Read First

1. `README.md` for install, launch, rollback, and user-facing safety rules.
2. `scripts\install.ps1`, `scripts\start-codex-with-console-guard.ps1`, `scripts\configure-default-terminal.ps1`, and `scripts\configure-codex-temp.ps1` before changing installation or launch behavior.
3. `scripts\codex-package.ps1` before changing package/process discovery.
4. `src\CodexConsoleWindowGuard.cpp` and `tests\console-window-guard-regression.ps1` before changing window filtering.
5. `scripts\health-snapshot.ps1` and `tests\health-snapshot-regression.ps1` before changing process-health diagnostics.

Do not inspect generated `bin/` or `obj/` output unless build diagnosis requires it.

## Design Constraints

- Never replace, rename, patch, or manually copy the user's real `git.exe`.
- Never persist the wrapper directory in system/user `PATH`.
- Leave the registry untouched by default. The explicit `-UseWindowsConsoleHost` path may change only `HKCU\Console\%%Startup` values `DelegationConsole` and `DelegationTerminal`, with exact backup and restore coverage.
- Never change user-level or machine-level `TEMP`/`TMP`. The explicit temporary-directory path must be stored beside the wrappers, affect only wrapper children, and leave the actual temporary files intact when disabled.
- Keep wrappers process-local to Codex launches.
- Keep the guard narrowly scoped to an exact window owner/process graph: targeted shell owners under ChatGPT/Codex, packaged Codex backend/helper owners under `ChatGPT.exe`, or a Chrome-parented `cmd.exe` native-host bridge. Never hide arbitrary descendants or all windows of a generic class.
- Preserve the bounded, command-line-free guard log and its 1 MiB truncation limit.
- Keep the health snapshot observation-only. It may read process, package, listener, and daemon-registration state, but must never start, stop, suspend, or modify anything; it must not serialize command lines or daemon tokens.
- Preserve the sparse startup/30-second rescan schedule and its visible-candidate gate; do not turn the guard into another high-frequency process poller.
- Preserve normal PowerShell Git behavior. Do not turn the system Git executable into a GUI executable.
- `-Force` stops Codex. Never run it from an active Codex task; give the user an external PowerShell command instead.

## Workflow Routing

- Documentation-only change: update `README.md`, then verify links, portability, and `git diff --check`.
- Wrapper/launcher behavior change: change the smallest relevant source/script and run the focused regression test.
- Package-name or process-tree change: cover both `ChatGPT.exe` and `Codex.exe` in the guard/package tests.
- Process-health diagnostic change: preserve the no-mutation and no-sensitive-output contract, then run `tests\health-snapshot-regression.ps1`.
- Default-terminal change: use an isolated HKCU test key, verify idempotent backup, and restore the original values exactly.
- Wrapper temporary-directory change: verify configuration rollback and real child-process `TEMP`/`TMP` inheritance through the compiled wrapper.
- Upstream Windows issue research: distinguish visible-window mitigation from the root Git polling, process leak, CPU, or crash issue; do not claim this repository fixes the upstream cause.
- GitHub issue/comment/push: requires explicit user authorization and fresh remote/issue readback.

## Canonical Commands

```powershell
# Install into the default user-local wrapper directory
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1

# Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\status.ps1

# Read-only process health
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\health-snapshot.ps1 -AsJson

# Focused regression checks
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\install-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\launcher-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\console-window-guard-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\default-terminal-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\codex-temp-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\health-snapshot-regression.ps1
```

## Verification Rules

- Code/launcher behavior: focused regression test on Windows.
- Guard filter: simulate both desktop process names, verify `--once` exits after the expected console event, run the process-graph self-test, and verify the matched-window log.
- Health snapshot: execute both human and JSON views, enforce the read-only command boundary, and confirm command lines and daemon tokens are absent.
- Documentation: no machine-specific clone paths, no secrets, and no undocumented safety trade-offs.
- Release: run all focused regression checks, `git diff --check`, and `workflow-lint.ps1` before push.

## Verification Bundles

- Authoritative target: the current clone, branch, worktree state, and remote URL.
- Code or launcher change: the matching regression script plus `git diff --check`.
- Public documentation: focused path/portability scan and rendered Markdown review.
- GitHub publish/comment: fresh remote or issue readback after the external action.

## Live Operation Gates

This project has no production service or customer data. Before a public GitHub push, release, or issue comment, confirm the target repository/account, the exact commit or comment body, user authorization, and post-action readback.

## Tooling Map

- `scripts\install.ps1`: builds/installs local wrappers and the optional guard.
- `scripts\start-codex-with-console-guard.ps1`: canonical launcher for the process-local wrapper environment and console guard.
- `scripts\start-codex-with-git-wrapper.ps1`: compatibility forwarder for older commands; new docs must use the canonical launcher.
- `scripts\status.ps1`: read-only install/runtime diagnostics.
- `scripts\health-snapshot.ps1`: read-only Codex app-server, stdio/MCP service-root, detached-candidate, memory, and BB Browser daemon diagnostics.
- `scripts\configure-default-terminal.ps1`: opt-in current-user Console Host mitigation with exact backup/restore.
- `scripts\configure-codex-temp.ps1`: opt-in wrapper-scoped temporary directory with backup/restore of its local configuration only.
- `scripts\remove.ps1`: removes the local wrapper/guard install.
- `tests\*.ps1`: focused Windows regression checks.

## Known Pitfalls

- MSIX files under `WindowsApps` can deny a normal `Test-Path` check even when the app can launch; use the manifest-derived package information.
- Some MSIX activation paths bypass process-local `PATH`. The console guard is the fallback for targeted shell/backend/native-host windows, not a global console suppressor.
- Automatic default-terminal selection can broker console UI through `WindowsTerminal.exe` and `OpenConsole.exe`, whose service-owned process graph cannot be safely attributed to Codex. Prefer the explicit, reversible Console Host mode over hiding all Windows Terminal windows.
- The MSIX/AppX fallback can bypass process-local environment inheritance. A dedicated TEMP directory is therefore a wrapper-child optimization, not a claim that every Desktop Codex process will use it.
- Current Codex builds can retain duplicate MCP process pools. The guard may hide their launcher windows, but it must not claim to deduplicate or reap those processes.
- `-DisableShellSnapshot` and `-SuppressProcessSampling` target separate PowerShell/process-telemetry symptoms and have documented trade-offs.
