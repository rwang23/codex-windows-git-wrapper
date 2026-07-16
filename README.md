# Codex Windows Git Wrapper

Small, reversible workaround for **Windows** users of the ChatGPT Codex desktop app who see `git.exe`, `powershell.exe`, `cmd.exe`, or `conhost.exe` windows flash while Codex is working.

> This is a Windows-only compatibility tool. It supports both current `ChatGPT.exe` desktop packages and older `Codex.exe` packages; it is not a macOS or Linux Git wrapper.

## What problem does it address?

On some Windows installations, the Codex desktop app starts Git or PowerShell from a GUI process. Git for Windows is normally a console application, so a console window can briefly appear. Some recent Microsoft Store / MSIX builds can also launch through Windows in a way that bypasses the launcher's process-local `PATH`.

The upstream fix belongs in Codex: its Windows subprocesses should be created without a visible console window. This repository is a local mitigation while that behavior is being fixed upstream.

Related upstream discussion:

- [Git root metadata probes / high Git startup activity](https://github.com/openai/codex/issues/29110)
- [PowerShell and conhost flashing on Windows](https://github.com/openai/codex/issues/26613)
- [Long-lived PowerShell parser / blank-window variant](https://github.com/openai/codex/issues/18984)
- [Git/conhost orphan behavior](https://github.com/openai/codex/issues/17229)
- [Duplicate MCP/app child processes](https://github.com/openai/codex/issues/32997)
- [Current Windows Git process storm](https://github.com/openai/codex/issues/33450)

## Compatibility and safety boundaries

| Area | Supported behavior |
| --- | --- |
| Operating system | Windows only |
| Desktop package names | Current `ChatGPT.exe` and legacy `Codex.exe` MSIX packages |
| Git | Git for Windows; the installer prefers the direct `mingw64\bin\git.exe` executable when available |
| PowerShell | Windows PowerShell wrapper for Codex-launched commands; PowerShell 5.1 or newer to run the scripts |
| Native compiler | Optional, but needed to build the console-window guard. The process-local wrappers still work without it. |

This project deliberately does **not**:

- Replace, rename, patch, or otherwise modify your installed Git executable.
- Modify the system or user `PATH`, registry, or package installation.
- Hide arbitrary application windows. The guard evaluates the exact window-owning process graph. It covers targeted Git/CMD/PowerShell processes beneath ChatGPT/Codex, the packaged `codex.exe` backend and known console helpers beneath `ChatGPT.exe`, and the Chrome-parented `cmd.exe` bridge used by the bundled Chrome native host. It does not hide unrelated terminals or arbitrary GUI descendants.
- Reduce Codex's underlying Git polling frequency, deduplicate MCP process pools, or fix every possible CPU/crash issue.

The default install location is `%LOCALAPPDATA%\OpenAI\Codex\wrapper-bin`, outside `.codex`, because recent Codex builds can apply restrictive ACLs below `.codex`.

## How it works

1. `scripts\install.ps1` builds small GUI wrappers named `git.exe`, `powershell.exe`, and `cmd.exe` in the wrapper directory. They forward arguments, standard streams, and exit codes to the real executables without creating a console window.
2. `scripts\start-codex-with-git-wrapper.ps1` starts Codex with that directory at the front of its **process-local** `PATH`.
3. When a native C++ compiler is available, the installer also builds `codex-console-window-guard.exe`. The guard covers MSIX activation paths that bypass the local `PATH`: it observes new top-level windows and uses a sparse startup/30-second rescan so process-ancestry races and persistent blank helper windows are not missed. A rescan reads the process graph only after it finds a visible candidate window, avoiding idle process-table polling.
4. The launcher reads the installed MSIX manifest rather than hard-coding the executable name. It therefore handles current `app\ChatGPT.exe` and older `app\Codex.exe` layouts.
5. The guard records each window it actually hides in `%LOCALAPPDATA%\OpenAI\Codex\wrapper-bin\codex-console-window-guard.log`. The log contains only a timestamp, PID, executable name, window class, and matching rule; it does not record command lines or window text.

The guard is intentionally an observation-and-hide fallback. It never turns the real Git executable into a GUI executable, because that would make ordinary PowerShell Git commands behave asynchronously.

## Prerequisites

- Windows with Git for Windows installed and available on `PATH`.
- PowerShell 5.1 or later.
- The ChatGPT Codex desktop app installed from the Microsoft Store/MSIX channel.
- Optional: Visual Studio Build Tools or another native C++ compiler if you want the console-window guard. If it is unavailable, installation succeeds with the process-local wrappers only.

## First-time installation

Clone the repository anywhere you prefer, then run the installer. This example uses a generic directory under your user profile, not a machine-specific project path:

```powershell
$repo = Join-Path $env:USERPROFILE "codex-windows-git-wrapper"
git clone https://github.com/rwang23/codex-windows-git-wrapper.git $repo
& (Join-Path $repo "scripts\install.ps1")
```

If Git is in a nonstandard location, find it first:

```powershell
Get-Command git -All
```

Then provide the real executable explicitly:

```powershell
& (Join-Path $repo "scripts\install.ps1") -RealGit "C:\Path\To\Git\mingw64\bin\git.exe"
```

The installer records the real Git, PowerShell, and Command Prompt paths inside its own wrapper directory. It does not alter persistent environment variables.

## Daily launch: one copy-paste command, no `cd`, no `git pull`

After the first install, use this command from an **external PowerShell window**. It starts the existing wrappers and console guard; it does not pull the repository or rebuild anything.

```powershell
$repo = Join-Path $env:USERPROFILE "codex-windows-git-wrapper"; & (Join-Path $repo "scripts\start-codex-with-git-wrapper.ps1") -DisableShellSnapshot -SuppressProcessSampling -Force
```

`-Force` closes a running ChatGPT/Codex desktop process before restarting it. Save your work first, and **never run this command from an active Codex task**, because it will terminate that task.

If Codex is already closed, you can omit `-Force`:

```powershell
$repo = Join-Path $env:USERPROFILE "codex-windows-git-wrapper"; & (Join-Path $repo "scripts\start-codex-with-git-wrapper.ps1") -DisableShellSnapshot -SuppressProcessSampling
```

### Optional launch switches

| Switch | When to use it | Trade-off |
| --- | --- | --- |
| `-Force` | Restart Codex when it is already running. Run only from external PowerShell. | Terminates current desktop tasks. |
| `-DisableShellSnapshot` | Codex is repeatedly starting PowerShell/conhost for shell/process snapshots. Requires the `codex` CLI to be available. | Disables the background `shell_snapshot` feature in Codex user configuration. |
| `-SuppressProcessSampling` | Desktop process sampling is creating high CPU or repeated PowerShell/CIM activity. | Process CPU/metadata views in the desktop app can be incomplete while enabled. |

The optional switches address different symptoms. The console guard is for Codex-launched Git, Command Prompt, and PowerShell console flashes; the snapshot and sampling switches are for separate PowerShell/process-telemetry activity.

## Update or repair deliberately

Do not run `git pull` every time you launch Codex. Update only when you want a newer workaround version or need to repair the installed wrapper:

```powershell
$repo = Join-Path $env:USERPROFILE "codex-windows-git-wrapper"
git -C $repo pull --ff-only
& (Join-Path $repo "scripts\setup-and-start.ps1") -DisableShellSnapshot -SuppressProcessSampling -Force
```

For a first-time clone-or-update from any directory, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$repo = Join-Path $env:USERPROFILE 'codex-windows-git-wrapper'; if (-not (Test-Path -LiteralPath $repo)) { git clone https://github.com/rwang23/codex-windows-git-wrapper.git $repo } else { git -C $repo pull --ff-only }; & (Join-Path $repo 'scripts\setup-and-start.ps1') -Force"
```

Again, run a `-Force` command only from outside Codex.

## Check status and remove the workaround

Status:

```powershell
$repo = Join-Path $env:USERPROFILE "codex-windows-git-wrapper"; & (Join-Path $repo "scripts\status.ps1")
```

The status report includes the detected app package, wrapper install path, real Git path, console-guard presence/running state, recent guard-log matches, current Git resolution, persistent `PATH` checks, and running Codex processes.

Rollback is simple. Close Codex, then run:

```powershell
$repo = Join-Path $env:USERPROFILE "codex-windows-git-wrapper"; & (Join-Path $repo "scripts\remove.ps1")
```

No Git installation files need to be restored, because this project never changes them. You can also close Codex and launch it normally from the Start menu; the wrappers apply only to Codex launched by this project.

## Troubleshooting

### The console guard is missing

`status.ps1` will report whether `codex-console-window-guard.exe` was built. If it is missing, install Visual Studio Build Tools/C++ (or another supported native compiler), then run `scripts\install.ps1` again. The standard process-local wrappers can still help when the guard is unavailable.

### `Test-Path: Access is denied` under `WindowsApps`

Newer MSIX packages can deny ordinary file-read checks under `WindowsApps` even though Windows can launch the app. The launcher intentionally reads the app manifest and attempts the declared executable; it falls back to the registered AppsFolder entry if direct MSIX launch is denied. This warning does not mean the wrapper itself is corrupted.

### Git, Command Prompt, or PowerShell windows still appear

Run `status.ps1` first. Check whether the guard is present and running, whether the installed app package is detected, and whether the recent log contains one of these rules:

- `codex-shell`: Git, CMD, PowerShell, or pwsh beneath ChatGPT/Codex.
- `codex-backend`: the packaged Codex backend or a known console helper beneath `ChatGPT.exe`.
- `chrome-native-host`: the `cmd.exe` bridge launched by Chrome for the bundled Codex Chrome native host.

No matching log entry means the remaining window has a different owner/process graph and should be captured before broadening the guard again. Do not work around that by globally hiding `cmd.exe`, PowerShell, Windows Terminal, or all console windows.

If the issue started after a Codex desktop update, capture the app package version and `status.ps1` output (with any private paths removed) and open or update an upstream issue. The project will keep tracking Windows package behavior, but it cannot replace a native upstream process-launch fix.

### `fondue.exe` or a Windows Features dialog appears

That is not part of the normal flow. It can occur when a managed wrapper cannot load its runtime. Run the installer again, check `status.ps1`, and then launch Codex through the standard launcher. Current native-wrapper builds avoid the known working-directory trigger.

## For Codex and other AI coding agents

Give your agent this instruction:

```text
I am on Windows and the ChatGPT Codex desktop app is flashing Git or console windows.

Use https://github.com/rwang23/codex-windows-git-wrapper as a temporary local workaround.

Requirements:
- Treat this as a Windows-only, cross-version (ChatGPT.exe and Codex.exe) compatibility tool.
- Clone the repository to a user-chosen local folder; do not assume an existing absolute path.
- Do not replace, rename, patch, or manually copy my real Git executable.
- Do not modify system PATH, user PATH, or the registry.
- Run scripts\install.ps1 first and then scripts\status.ps1.
- If Git detection fails, use Get-Command git -All and pass -RealGit with the real Git path.
- Use scripts\setup-and-start.ps1 only when I explicitly approve a Codex restart.
- Never run a -Force launcher command from inside an active Codex task.
- Before finishing, report the external PowerShell launch command and the scripts\remove.ps1 rollback command.
```

An agent may install and verify the files, but a user should run the final `-Force` restart command from an external PowerShell window so no active task is interrupted.

## Contributing and verification

The repository includes focused Windows regression checks. From a clone, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\install-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\launcher-regression.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\console-window-guard-regression.ps1
```

The console-guard test simulates both `ChatGPT.exe` and legacy `Codex.exe` launching a Git console process, verifies diagnostic logging, and asserts process-graph rules for shell launchers, the packaged Codex backend, and the Chrome native-host bridge. It skips only when no native compiler is available.

Please report the desktop package version, the exact visible process/window symptom, and the redacted `status.ps1` output. Do not include personal paths, account data, or tokens.

## Notes

- Do not manually copy, rename, or replace `git.exe`.
- Do not add the wrapper directory to persistent user or machine `PATH`.
- Prefer the smallest workaround needed for your symptom.
- Remove this workaround after Codex fixes the Windows Git process-launch behavior upstream.
