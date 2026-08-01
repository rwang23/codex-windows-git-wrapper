# Changelog

All notable changes to this project are documented here. Earlier history remains available in Git.

## [2026-07-31]

### Added

- Added `scripts\codex-guard.ps1` as a single operator entry point for read-only `check`, scoped `repair`, exact-target `stop`, and recommended-switch `launch` commands, with regression coverage and bilingual documentation.

## [2026-07-16]

### Documentation

- Added concise bilingual search terms for the Windows popup/console symptom family, while explicitly separating the guard from upstream CPU and crash fixes.
- Added an agent-first operating brief at the top of the English README and a linked Simplified Chinese README.
- Clarified the observed brokered-window mitigation: switching the current user's default terminal from Automatic/Windows Terminal delegation to Windows Console Host stopped the captured `Terminal` flash symptom, while remaining a reversible, symptom-specific workaround rather than a claim to fix every Codex performance or stability issue.
- Added a Simplified Chinese Windows performance runbook covering the multi-task process model, MCP/Skill boundaries, CodeGraph `--liftoff-only`, Node REPL diagnostics, incremental pre-compaction cards, BB Browser daemon recovery, Docker/WSL resource limits, update checks, and rollback.

### Changed

- Added an opt-in, wrapper-scoped temporary-directory configuration. It gives Codex-launched Git, Command Prompt, and PowerShell child processes a dedicated `TEMP`/`TMP` without changing the user's or system's global environment variables.
- Added a reversible `-UseWindowsConsoleHost` compatibility mode for blank, focus-stealing Windows Terminal windows created when automatic terminal delegation brokers Codex console launches through `svchost.exe`.
- Extended status diagnostics with the current default-terminal mode and corrected persistent `PATH` checks to compare the actual wrapper install directory.
- Renamed the public project to **Codex Windows Guard** and the repository to `codex-windows-guard`; the name now reflects the focused Windows compatibility scope without promising broad system optimization.
- Promoted `scripts\start-codex-with-windows-guard.ps1` to the canonical launcher. Both the former console-named launcher and `scripts\start-codex-with-git-wrapper.ps1` remain compatibility forwarders.
- Expanded the guard beyond `ConsoleWindowClass` so it can suppress the persistent blank-window variant owned by the packaged Codex backend or its known console helpers.
- Added coverage for the Chrome-parented `cmd.exe` native-messaging bridge used by the bundled Codex Chrome plugin.
- Added a sparse startup/30-second existing-window scan to recover from process-ancestry timing races without introducing continuous process-table polling.
- Gated each existing-window scan on a visible candidate owner before reading the process graph, reducing idle CPU cost during upstream process storms.

### Added

- `scripts\configure-codex-temp.ps1`, launcher `-TempDir` support, status visibility, and regression coverage for TEMP/TMP inheritance plus configuration rollback.
- An isolated registry regression test plus `scripts\configure-default-terminal.ps1`, which backs up and restores only the two current-user terminal delegation values.
- A bounded diagnostic log containing only matched PID, executable, window class, and rule information.
- Status output and regression coverage for the diagnostic log and the new process-graph rules.
- A read-only `scripts\health-snapshot.ps1` command with JSON output, stdio/MCP service-root aggregation, detached-candidate reporting, and BB Browser daemon health checks that never expose command lines or daemon tokens.
- A focused health-snapshot regression test that checks the no-mutation boundary and the versioned JSON contract.

## [2026-07-15]

### Changed

- Expanded the native console-window guard from Git-only ancestry to targeted `git.exe`, `cmd.exe`, `powershell.exe`, and `pwsh.exe` ancestry beneath ChatGPT Codex Desktop.
- Added a process-graph self-test and made the regression harness wait for the GUI guard's actual exit code.

## [2026-07-14]

### Added

- A narrowly scoped native console-window guard for Git consoles launched beneath ChatGPT Codex Desktop.
- Regression coverage for both current `ChatGPT.exe` and legacy `Codex.exe` process names.
- Portable installation/launch instructions and an agent maintenance brief.

### Changed

- Documentation now distinguishes the visible-window workaround from the upstream Git polling, process-leak, CPU, and crash fixes still required in Codex.
