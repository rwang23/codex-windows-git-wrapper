# Changelog

All notable changes to this project are documented here. Earlier history remains available in Git.

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
