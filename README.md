# Codex Windows Git Wrapper

Temporary workaround for Windows ChatGPT/Codex App users who see transient `git.exe`, `powershell.exe`, or `conhost.exe` windows flashing while Codex runs tasks.

This project is intentionally small and conservative. Its default mode does not patch Codex, replace Git, PowerShell, or Command Prompt, or change persistent system configuration. It provides a launcher that starts Codex with a process-local `PATH` entry pointing to small `git.exe`, `powershell.exe`, and `cmd.exe` wrappers.

Recent Microsoft Store / MSIX ChatGPT/Codex builds can activate through Windows in a way that bypasses the launcher process's `PATH`, while still starting the system Git for Windows `cmd\git.exe` directly. For that specific case, this repository installs a small **Codex Git console window guard**. It listens only for visible console windows whose ancestry contains both `ChatGPT.exe` and `git.exe`, then immediately hides that window. It never replaces the system Git executable, so normal PowerShell Git commands keep their synchronous behavior.

By default the wrappers are installed under `%LOCALAPPDATA%\OpenAI\Codex\wrapper-bin`, not under `.codex`. This avoids sandbox ACLs that recent Codex builds can place on files below `.codex`.

For current Codex Desktop builds, the launcher can also disable the `shell_snapshot` feature. This is a separate Windows issue: Codex's background process polling can start visible PowerShell/conhost windows even when Git itself is wrapped.

## Problem

On some Windows machines, the Codex desktop app repeatedly launches Git commands during task execution. Because Git for Windows `git.exe` is a console executable, a `git.exe` / console window may flash briefly if Codex starts it from a GUI process without hiding the console window.

Known related reports:

- <https://github.com/openai/codex/issues/24910>
- <https://github.com/openai/codex/issues/17229>
- <https://github.com/openai/codex/issues/20933>
- <https://github.com/openai/codex/issues/22085>
- <https://github.com/openai/codex/issues/29110>
- <https://github.com/openai/codex/issues/26613>

The upstream fix should come from Codex launching Git with the appropriate Windows no-console/no-window flags. This repository is only a local workaround.

## What This Does

The wrapper is a tiny Windows GUI executable installed as `git.exe`, `powershell.exe`, and `cmd.exe`. It selects the real target from its own filename, starts that executable with `CREATE_NO_WINDOW`, waits for it to exit, and returns the same exit code. Arguments and standard streams are forwarded.

When a native C++ compiler is available, the installer builds a native wrapper first. If no native compiler is available, it falls back to the managed C# wrapper.

The Git wrapper target is supplied by:

1. `CODEX_REAL_GIT` environment variable set by the launcher.
2. `real-git.txt` in the wrapper install directory.
3. Common Git for Windows install paths as a fallback.

When Git for Windows provides both `cmd\git.exe` and `mingw64\bin\git.exe`, the installer selects `mingw64\bin\git.exe` deliberately. `cmd\git.exe` is a small dispatcher which starts a second Git process and can create its own `conhost.exe`; bypassing that dispatcher is required for the no-window wrapper to cover the actual Git command. The installer excludes Codex's private cached Git runtime, which can be replaced during a Desktop update.

The PowerShell wrapper uses `CODEX_REAL_POWERSHELL`, then `real-powershell.txt`, then the built-in Windows PowerShell path under `System32`. The Command Prompt wrapper uses `CODEX_REAL_CMD`, then `real-cmd.txt`, then `System32\cmd.exe`.

When a native C++ compiler is available, the installer also builds `codex-console-window-guard.exe`. The launcher starts it before Codex. The guard has no window of its own and ignores console windows that are not in a `ChatGPT.exe` → `git.exe` process tree, so ordinary terminal, PowerShell, and Git use are left alone.

## What This Does Not Do

- It does not replace your installed Git or modify its directory.
- It does not modify system or user `PATH`.
- It does not modify the registry.
- It does not reduce Codex's Git polling frequency.
- The console guard targets Git console windows only. It does not suppress a separate PowerShell/CMD window that Codex intentionally opens for an interactive command.
- It hides PowerShell console windows but cannot remove the Desktop app's internal PowerShell/CIM telemetry work. Disabling `shell_snapshot`, clearing only invalid process-manager state, and keeping generated files ignored can reduce amplification; the full CPU fix still belongs upstream.

## Install

Clone the repository:

```powershell
git clone https://github.com/rwang23/codex-windows-git-wrapper.git
cd codex-windows-git-wrapper
```

Install the wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer detects your real Git path with `Get-Command git -All`, excluding the wrapper install directory.

If your Git is installed somewhere custom, pass the path explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -RealGit "C:\Program Files\Git\cmd\git.exe"
```

Your path may be different. Check with:

```powershell
Get-Command git -All
```

## Normal Launch: No `git pull`

After the wrapper has been installed once, use the existing fast launcher. It does not pull the repository, rebuild the wrapper, or rerun installation. It starts the Codex Git console window guard before launching the app:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\projects\tools\codex-windows-git-wrapper\scripts\start-codex-with-git-wrapper.ps1" -DisableShellSnapshot -SuppressProcessSampling -Force
```

Run it from an **external** PowerShell after saving your work. `-Force` closes the current ChatGPT/Codex Desktop process, so it must not be run from an active Codex task.

## Setup Or Repair And Launch

Use the combined install/check/start script after intentionally updating this repository, after a wrapper repair, or when the wrapper install directory is missing:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -Force
```

If Codex Desktop is flashing PowerShell/conhost windows, use the optional feature workaround:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -DisableShellSnapshot
```

To intentionally update the repository and then force-restart the current ChatGPT/Codex Desktop app from any directory, use this one-line command (adjust the clone path if needed):

```powershell
git -C "C:\projects\tools\codex-windows-git-wrapper" pull; powershell -NoProfile -ExecutionPolicy Bypass -File "C:\projects\tools\codex-windows-git-wrapper\scripts\setup-and-start.ps1" -DisableShellSnapshot -SuppressProcessSampling -Force
```

This writes `shell_snapshot = false` to the Codex user configuration. Restart Codex after running it. It keeps the normal shell tool enabled, but disables the background shell/process snapshot loop.

The launcher reads the executable and application ID from the installed MSIX manifest. This matters because current packages use `app\ChatGPT.exe`, while older releases used `app\Codex.exe`. The same manifest-derived process name is used for running-process detection and `-Force`, so an existing app is actually stopped before the wrapper environment is applied. Hard-coding `Codex.exe` causes the launcher to miss the renamed process and fall back to AppX activation. Even with the correct executable, some current MSIX builds still bypass the process-local wrapper `PATH`; the window guard covers their Git console windows without modifying Git itself.

The launcher does not use `Test-Path` on the protected `WindowsApps` executable; newer package ACLs can deny that read check even when the app is launchable. It starts the manifest-declared executable directly and only falls back to the registered AppsFolder entry if Windows denies the direct launch.

When `-Force` is used, the launcher also checks `.codex\process_manager\chat_processes.json` after stopping the app. If that file is empty, all-zero, or invalid JSON, it is moved to a timestamped backup before restart. Valid process-manager state is left untouched. This addresses a stale-state condition associated with excessive Windows PowerShell/CIM process sampling without deleting recoverable data.

`-SuppressProcessSampling` is an opt-in CPU mitigation for the Windows Desktop app's Electron sampler. The PowerShell wrapper recognizes only the two known internal `Get-CimInstance`/`ConvertTo-Json` process-sampling command shapes and returns an empty JSON array without launching real PowerShell. Ordinary PowerShell commands are forwarded normally. Tradeoff: Desktop process CPU/metadata views may be incomplete while this option is enabled. Omit the switch to restore the original sampling behavior.

Important: do not run the `-Force` command from inside an active Codex task. It closes existing Codex processes so the newly launched Codex process can inherit the wrapper environment.

If you want a clone-or-update command that works from any directory (use this only when you actually want to update the repository):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$repo = Join-Path $env:USERPROFILE 'codex-windows-git-wrapper'; if (!(Test-Path -LiteralPath $repo)) { git clone https://github.com/rwang23/codex-windows-git-wrapper.git $repo } else { git -C $repo pull --ff-only }; & (Join-Path $repo 'scripts\setup-and-start.ps1') -Force"
```

If Git is installed in a custom location, pass `-RealGit`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -RealGit "C:\Program Files\Git\cmd\git.exe" -Force
```

## For Codex / AI Agents

If you are using Codex or another AI coding agent, give it this prompt:

```text
I am on Windows and the Codex desktop app is flashing git.exe console windows during tasks.

Please install this temporary workaround:
https://github.com/rwang23/codex-windows-git-wrapper

Requirements:
- Do not replace, rename, or patch my real Git executable.
- Do not modify system PATH or user PATH.
- Clone the repo locally.
- Run scripts\setup-and-start.ps1 only if I explicitly ask you to restart Codex.
- Otherwise run scripts\install.ps1.
- If Git auto-detection fails, run Get-Command git -All and pass the real Git path with -RealGit.
- Run scripts\status.ps1 and confirm persistent user/machine PATH do not contain codex-git-wrapper.
- Do not run scripts\setup-and-start.ps1 -Force or scripts\start-codex-with-git-wrapper.ps1 -Force from inside an active Codex task.
- Tell me the exact external PowerShell command I should run to start Codex with the wrapper.
- Tell me the exact remove command for rollback.
```

The agent should install and verify the workaround, then give you the external PowerShell command to start Codex. It should not run the `-Force` launcher from inside Codex, because that closes Codex and may interrupt the session.

## Codex Git Console Window Guard

The guard is built automatically by `scripts\install.ps1` when a native C++ compiler is available, and the standard launcher starts it before Codex. It receives Windows console-window events and hides only windows with a `ChatGPT.exe` and `git.exe` ancestor chain. This avoids the compatibility problem of replacing `git.exe`: a GUI replacement makes PowerShell treat Git as an asynchronous GUI process.

Check that it is installed and running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\projects\tools\codex-windows-git-wrapper\scripts\status.ps1"
```

If the installer reports that no native C++ compiler is available, the process-local wrappers still work but the guard is unavailable. Install Visual Studio Build Tools/C++ or use the upstream Codex fix when it becomes available.

## Start Codex With The Wrapper

Close Codex completely, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-codex-with-git-wrapper.ps1
```

If Codex is already running, the launcher refuses to continue because existing Codex processes keep their old environment and the wrapper will not apply.

To force-close existing Codex processes first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-codex-with-git-wrapper.ps1 -Force
```

Do not run the `-Force` command from inside an active Codex task, because it will close Codex.

The combined install/check/start script is for repair or post-update setup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -Force
```

## Check Status

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1
```

This reports:

- Codex App version and install location.
- Wrapper install path.
- Configured real Git path.
- Codex Git console window guard presence and running state.
- Current process Git resolution.
- Whether persistent user or machine `PATH` contains the wrapper.
- Running Codex processes.

## Troubleshooting fondue.exe / Windows Features

If a `Windows Features` window or `fondue.exe` appears after installing the wrapper, do not treat that as the normal fix path.

`fondue.exe` is a Windows component used for feature-on-demand prompts. In this workaround, it can appear if the managed wrapper crashes while Windows is loading the .NET runtime. One known trigger is a broken or unavailable current working directory inherited from a Codex process. Current wrapper source avoids reading `Environment.CurrentDirectory` before launching Git.

Recommended recovery:

```powershell
git pull --ff-only
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\status.ps1
```

Then close Codex completely and start it again with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-codex-with-git-wrapper.ps1
```

## Remove

Close Codex, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\remove.ps1
```

You can also restore normal behavior by closing Codex and launching it normally from the Start menu. The wrapper only applies to Codex processes started by `start-codex-with-git-wrapper.ps1`.

## Emergency Recovery

If something goes wrong, close Codex and remove the wrapper and its window guard:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\remove.ps1
```

No Git installation files need to be restored because this workaround never changes them.

## Notes

- Do not manually copy, rename, or replace `git.exe`.
- Do not add the wrapper directory to persistent user or machine `PATH`.
- Remove this workaround after Codex fixes the Windows Git process launch behavior upstream.
