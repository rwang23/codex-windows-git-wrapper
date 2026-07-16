# Changelog

All notable changes to this project are documented here. Earlier history remains available in Git.

## [2026-07-16]

### Changed

- Promoted `scripts\start-codex-with-console-guard.ps1` to the canonical launcher and retained `scripts\start-codex-with-git-wrapper.ps1` as a compatibility forwarder.
- Renamed the public repository from `codex-windows-git-wrapper` to `codex-windows-console-guard` to describe its full targeted scope: Git, Command Prompt, PowerShell, conhost, and the process-aware console-window guard.
- Expanded the guard beyond `ConsoleWindowClass` so it can suppress the persistent blank-window variant owned by the packaged Codex backend or its known console helpers.
- Added coverage for the Chrome-parented `cmd.exe` native-messaging bridge used by the bundled Codex Chrome plugin.
- Added a sparse startup/30-second existing-window scan to recover from process-ancestry timing races without introducing continuous process-table polling.
- Gated each existing-window scan on a visible candidate owner before reading the process graph, reducing idle CPU cost during upstream process storms.

### Added

- A bounded diagnostic log containing only matched PID, executable, window class, and rule information.
- Status output and regression coverage for the diagnostic log and the new process-graph rules.

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
