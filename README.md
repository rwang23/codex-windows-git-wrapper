# Codex Windows Git Wrapper

Temporary workaround for Windows ChatGPT/Codex App users who see transient `git.exe`, `powershell.exe`, or `conhost.exe` windows flashing while Codex runs tasks.

This project is intentionally small and conservative. It does not patch Codex, replace Git or PowerShell, or change persistent system configuration. It provides a launcher that starts Codex with a process-local `PATH` entry pointing to small `git.exe` and `powershell.exe` wrappers.

For current Codex Desktop builds, the launcher can also disable the `shell_snapshot` feature. This is a separate Windows issue: Codex's background process polling can start visible PowerShell/conhost windows even when Git itself is wrapped.

## Problem

On some Windows machines, the Codex desktop app repeatedly launches Git commands during task execution. Because Git for Windows `git.exe` is a console executable, a `git.exe` / console window may flash briefly if Codex starts it from a GUI process without hiding the console window.

Known related reports:

- <https://github.com/openai/codex/issues/24910>
- <https://github.com/openai/codex/issues/17229>
- <https://github.com/openai/codex/issues/20933>
- <https://github.com/openai/codex/issues/22085>

The upstream fix should come from Codex launching Git with the appropriate Windows no-console/no-window flags. This repository is only a local workaround.

## What This Does

The wrapper is a tiny Windows GUI executable installed as both `git.exe` and `powershell.exe`. It selects the real target from its own filename, starts that executable with `CREATE_NO_WINDOW`, waits for it to exit, and returns the same exit code. Arguments and standard streams are forwarded.

When a native C++ compiler is available, the installer builds a native wrapper first. If no native compiler is available, it falls back to the managed C# wrapper.

The Git wrapper target is supplied by:

1. `CODEX_REAL_GIT` environment variable set by the launcher.
2. `real-git.txt` in the wrapper install directory.
3. Common Git for Windows install paths as a fallback.

The PowerShell wrapper uses `CODEX_REAL_POWERSHELL`, then `real-powershell.txt`, then the built-in Windows PowerShell path under `System32`.

## What This Does Not Do

- It does not replace your installed Git.
- It does not modify your Git install directory.
- It does not modify system or user `PATH`.
- It does not modify the registry.
- It does not reduce Codex's Git polling frequency.
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

## One Command Setup And Launch

If you already cloned this repository locally, run this from an external PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -Force
```

If Codex Desktop is flashing PowerShell/conhost windows, use the optional feature workaround:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-and-start.ps1 -DisableShellSnapshot
```

To update the repository and force-restart the current ChatGPT/Codex Desktop app from any directory, use this one-line command (adjust the clone path if needed):

```powershell
git -C "C:\projects\tools\codex-windows-git-wrapper" pull; powershell -NoProfile -ExecutionPolicy Bypass -File "C:\projects\tools\codex-windows-git-wrapper\scripts\setup-and-start.ps1" -DisableShellSnapshot -Force
```

This writes `shell_snapshot = false` to the Codex user configuration. Restart Codex after running it. It keeps the normal shell tool enabled, but disables the background shell/process snapshot loop.

The launcher reads the executable and application ID from the installed MSIX manifest. This matters because current packages use `app\ChatGPT.exe`, while older releases used `app\Codex.exe`. The same manifest-derived process name is used for running-process detection and `-Force`, so an existing app is actually stopped before the wrapper environment is applied. Hard-coding `Codex.exe` causes the launcher to miss the renamed process and fall back to AppX activation, which does not reliably inherit the process-local wrapper `PATH`.

The launcher does not use `Test-Path` on the protected `WindowsApps` executable; newer package ACLs can deny that read check even when the app is launchable. It starts the manifest-declared executable directly and only falls back to the registered AppsFolder entry if Windows denies the direct launch.

When `-Force` is used, the launcher also checks `.codex\process_manager\chat_processes.json` after stopping the app. If that file is empty, all-zero, or invalid JSON, it is moved to a timestamped backup before restart. Valid process-manager state is left untouched. This addresses a stale-state condition associated with excessive Windows PowerShell/CIM process sampling without deleting recoverable data.

Important: do not run the `-Force` command from inside an active Codex task. It closes existing Codex processes so the newly launched Codex process can inherit the wrapper environment.

If you want a clone-or-update command that works from any directory:

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
- Do not replace or rename my real Git executable.
- Do not copy the wrapper into my Git installation directory.
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

The combined install/check/start script is:

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

If something goes wrong, stop Codex and Git processes:

```powershell
taskkill /F /IM git.exe
taskkill /F /IM codex.exe
taskkill /F /IM Codex.exe
```

Then remove the wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\remove.ps1
```

No Git installation files need to be restored because this workaround never changes them.

## Notes

- Do not copy the wrapper into your Git installation directory.
- Do not rename or replace your real `git.exe`.
- Do not add the wrapper directory to persistent user or machine `PATH`.
- Remove this workaround after Codex fixes the Windows Git process launch behavior upstream.
